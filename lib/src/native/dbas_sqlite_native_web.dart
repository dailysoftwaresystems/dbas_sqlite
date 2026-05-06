import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';
import 'package:dbas_sqlite/src/stub/dbas_sqlite_db_stub.dart'
    show sqliteOk, sqliteRow, sqliteDone, sqliteMisuse;
import 'dbas_sqlite_native_interface.dart';
import 'web/dbas_sqlite_web_pool.dart';

/// Web implementation of [DbasSqliteNativeInterface].
///
/// Backed by [DbasSqliteWebPool] (a single Web Worker that loads the
/// WASM module, opens OPFS, and owns the SQLite connection). The
/// platform-interface methods on this class mirror the native FFI
/// contract 1:1, so [DbasSqliteStatement] and [DbasSqliteReader] run
/// the same code path on every platform — only the per-call delegate
/// implementation differs.
///
/// Streaming SELECT / DML lifecycle on web (mirroring native FFI's
/// prepare/bind/step/finalize):
///   1. [prepareQuery] sends `prepareQuery` to the worker, allocates a
///      Dart-side `int` handle, and stashes a [_WebStmtState] keyed by
///      it. The state holds the worker's raw JS BigInt handle, the
///      column metadata, the pending bind buffer, the row chunk cache,
///      and the post-step counter cache.
///   2. The `bind*` methods buffer values Dart-side without round-trips.
///   3. The first [readRowAndCache] call flushes the buffered binds via
///      one `bindParams` round-trip, then steps the statement. To keep
///      [executeScalar] cheap, the **first** step uses the worker's
///      single-row `readRow` action (one row fetched, no waste);
///      **subsequent** steps use the chunked `readRows` action with a
///      50-row chunk so a 10k-row scan is ~200 round-trips instead of
///      ~10000. Rows are dequeued from the cache one per call so the
///      reader API is unchanged.
///   4. When the step path observes `SQLITE_DONE` on a write-shape
///      statement (`columnCount == 0`), the per-stmt counters are
///      eagerly fetched via `getStmtAffectedRows` /
///      `getStmtLastInsertedId` so the synchronous platform getters can
///      return cached values without a round-trip.
///   5. [finalizeStmt] sends `finalizeStmt` to the worker and drops the
///      Dart-side state.
///
/// The no-params [executeSql] platform method (used for
/// `BEGIN`/`COMMIT`/`ROLLBACK`/`VACUUM`/`PRAGMA`) stays mapped to
/// [DbasSqliteWebPool.exec] — single round-trip for system SQL, no
/// counters needed.
class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  /// Worker chunk size for the bulk `readRows` action. Tuned for
  /// 10k-row scans; smaller values increase round-trip count, larger
  /// values increase per-chunk memory. The worker caps at 10000.
  static const int _readRowsChunkSize = 50;

  DbasSqliteWebPool? _pool;
  bool _initialized = false;
  bool _dbOpened = false;
  String _sqliteVersion = '';
  final int _abiVersion = 0;
  int _lastAffectedRows = 0;
  int _lastInsertedId = 0;
  String? _lastError;

  /// Per-handle prepared-statement state. Keyed by the Dart-side
  /// `int` handle returned from [prepareQuery] (a monotonic counter
  /// — see [_nextStmtId]). The worker's actual handle (a JS BigInt)
  /// lives inside [_WebStmtState.rawHandle] so we can echo it back to
  /// the worker without round-tripping through Dart `BigInt`.
  final Map<int, _WebStmtState> _stmts = {};
  int _nextStmtId = 1;

  DbasSqliteNativeWeb(super.dbName);

  static void registerWith(Registrar registrar) {}

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  @override
  String getSqliteVersion() => _sqliteVersion;
  @override
  int getAbiVersion() => _abiVersion;

  /// Populates [_sqliteVersion] from the JS pool by issuing
  /// `SELECT sqlite_version()`. Called from [_ensurePool] after the
  /// pool boots so that the synchronous [getSqliteVersion] accessor
  /// has a real value to return on web. No-op if already populated.
  Future<void> _ensureSqliteVersion() async {
    if (_sqliteVersion.isNotEmpty) return;
    if (_pool == null) return;
    try {
      final rows = await _pool!.query('SELECT sqlite_version()');
      if (rows.isNotEmpty) {
        final first = rows.first.values.first;
        if (first != null) _sqliteVersion = first.toString();
      }
    } catch (e, st) {
      _lastError = 'getSqliteVersion via pool.query failed: $e';
      developer.log(
        'DbasSqliteNativeWeb._ensureSqliteVersion: pool.query failed for "$dbName"',
        name: 'dbas_sqlite.DbasSqliteNativeWeb',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  Future<int> openDb(String path) async {
    _dbOpened = true;
    return 1;
  }

  @override
  Future<bool> databaseExists(String fileName) async {
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    try {
      final result = await pool.send('exists');
      return result == true;
    } finally {
      // Probe-only pool: tear it down so we don't leak a worker for
      // every existence check. Mirrors `attachDb` / `dropDb` /
      // `getContent`, which all close their throw-away pool too.
      await pool.close();
      DbasSqliteWebPool.removePool(dbName);
    }
  }

  @override
  bool isOpened(int dbPtr) => _dbOpened;

  @override
  Future<int> closeDb(int dbPtr, {bool checkpoint = false}) async {
    await _pool?.close();
    _pool = null;
    DbasSqliteWebPool.removePool(dbName);
    _dbOpened = false;
    _stmts.clear();
    return sqliteOk;
  }

  // ── File operations (via worker protocol) ─────────────────────────────

  @override
  Future attachDb(String fileName, List<int> content) async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
      DbasSqliteWebPool.removePool(dbName);
    }
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    await pool.attachStreamChunked(
      Stream.fromIterable([content]),
      totalSize: content.length,
    );
    await pool.close();
    DbasSqliteWebPool.removePool(dbName);
  }

  @override
  Future attachStreamDb(String fileName, Stream<List<int>> stream) async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
      DbasSqliteWebPool.removePool(dbName);
    }
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    await pool.attachStreamChunked(stream);
    await pool.close();
    DbasSqliteWebPool.removePool(dbName);
  }

  @override
  Future<List<int>> getContent(String fileName) async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
      DbasSqliteWebPool.removePool(dbName);
      _dbOpened = false;
    }
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    final bytes = await pool.exportContentStream();
    await pool.close();
    DbasSqliteWebPool.removePool(dbName);
    return bytes;
  }

  @override
  Future<void> streamCopyDb(String sourceFileName, String destFileName) async {
    String destName = destFileName;
    if (destFileName.contains('/')) destName = destFileName.split('/').last;
    await _ensurePool();
    await _pool!.streamCopy(destName);
  }

  @override
  Future dropDb(String fileName) async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
      DbasSqliteWebPool.removePool(dbName);
    }
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    await pool.drop();
    await pool.close();
    DbasSqliteWebPool.removePool(dbName);
    _dbOpened = false;
  }

  // ── No-params SQL (BEGIN/COMMIT/ROLLBACK/VACUUM/PRAGMA) ──────────────
  // Mirrors native's `nativeExecuteSql`: single-statement system SQL with
  // no bindings. Goes through `pool.exec` because the worker's `exec`
  // action can run multi-statement input via sqlite3_exec; it's also a
  // single round-trip versus the prepare/bind/step/finalize fan-out.

  @override
  Future<int> executeSql(int dbPtr, String sql) async {
    await _ensurePool();
    try {
      final result = await _pool!.exec(sql);
      _lastAffectedRows = toIntSafe(result['affectedRows']);
      _lastInsertedId = toIntSafe(result['lastInsertId']);
      _lastError = null;
      return sqliteOk;
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    }
  }

  // ── State accessors (last-write outcome) ──────────────────────────────

  @override
  String? getLastDbError(int dbPtr) => _lastError;
  @override
  int getAffectedRows(int dbPtr) => _lastAffectedRows;
  @override
  int getLastInsertedId(int dbPtr) => _lastInsertedId;
  @override
  int getTotalChanges(int dbPtr) => 0; // not exposed by JS pool today
  @override
  String? getDbFileName(int dbPtr) => dbName;

  @override
  Future<int> setBusyTimeout(int dbPtr, int ms) async {
    // No-op on web — the JS pool has its own internal busy handling.
    return sqliteOk;
  }

  @override
  Future<int> enableWal(int dbPtr) async {
    // The JS pool always opens with WAL via the writer worker, but
    // verify the readback so a pool that silently failed to set WAL
    // (rare — SAB unavailable in some browsers, etc.) surfaces as a
    // non-OK rc instead of a silent success.
    await _ensurePool();
    try {
      final rows = await _pool!.query('PRAGMA journal_mode');
      if (rows.isEmpty) {
        _lastError = 'enableWal: PRAGMA journal_mode returned no rows';
        return 1; // SQLITE_ERROR
      }
      final mode = rows.first.values.first?.toString().toLowerCase() ?? '';
      if (mode != 'wal') {
        _lastError =
            'enableWal: web pool reports journal_mode="$mode", expected "wal"';
        return 1; // SQLITE_ERROR
      }
      return sqliteOk;
    } catch (e) {
      _lastError = 'enableWal: $e';
      return 1; // SQLITE_ERROR
    }
  }

  // ── Prepared-statement lifecycle ──────────────────────────────────────

  @override
  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(int dbPtr, String sql) async {
    await _ensurePool();
    final prep = await _pool!.prepareQueryStream(sql);
    final handle = _nextStmtId++;
    _stmts[handle] = _WebStmtState(
      rawHandle: prep.rawHandle,
      columnCount: prep.columnCount,
      columnNames: prep.columnNames,
    );
    return (
      handle: handle,
      columnCount: prep.columnCount,
      columnNames: prep.columnNames,
    );
  }

  @override
  Future<int> finalizeStmt(int dbPtr, int handle) async {
    final state = _stmts.remove(handle);
    if (state == null) return sqliteOk; // already finalized / unknown
    try {
      await _pool!.finalizeStmt(state.rawHandle);
    } catch (e, st) {
      developer.log(
        'DbasSqliteNativeWeb.finalizeStmt: pool.finalizeStmt failed',
        name: 'dbas_sqlite.DbasSqliteNativeWeb',
        error: e,
        stackTrace: st,
      );
      // Idempotent at the worker side; we already dropped state. Don't
      // surface — finalize is part of cleanup and shouldn't mask the
      // primary error.
    }
    return sqliteOk;
  }

  @override
  Future<int> readRowAndCache(int dbPtr, int handle, RowData cache) async {
    final state = _stmts[handle];
    if (state == null) return sqliteMisuse;
    cache.columnCount = state.columnCount;
    cache.columnNames = state.columnNames;

    // Flush buffered binds on the first call. Subsequent calls reuse
    // the already-bound parameters on the worker stmt — the worker
    // doesn't auto-reset between `readRow`/`readRows` calls.
    if (!state.bindsFlushed) {
      final params = state.mergedParams();
      if (params != null) {
        try {
          await _pool!.bindParams(state.rawHandle, params);
        } catch (e) {
          state.lastError = e.toString();
          cache.columns = null;
          return 1; // SQLITE_ERROR — caller propagates
        }
      }
      state.bindsFlushed = true;
    }

    // Pop a buffered row if we have one.
    if (state.chunk.isNotEmpty) {
      cache.columns = state.chunk.removeFirst();
      return sqliteRow;
    }

    // Cache empty — figure out whether to fetch or signal DONE. The
    // chunk-drained DONE branch must capture counters too, otherwise
    // a write-shape stmt with multi-row chunks (or an
    // INSERT…RETURNING flow that produces rows then DONE) would never
    // populate `affectedRows` / `lastInsertedId` for the synchronous
    // platform getters.
    if (!state.hasMore) {
      cache.columns = null;
      await _captureCountersOnDone(state);
      return sqliteDone;
    }

    try {
      if (!state.firstFetchDone) {
        // First step: single-row fetch. Optimal for `executeScalar`
        // (one row + close, no waste) and only +1 round-trip versus
        // an all-bulk approach for multi-row scans.
        state.firstFetchDone = true;
        final result =
            await _pool!.readRow(state.rawHandle, state.columnNames);
        if (result.rc == sqliteRow) {
          cache.columns = result.columns;
          return sqliteRow;
        }
        // SQLITE_DONE — no row. Capture counters.
        state.hasMore = false;
        cache.columns = null;
        await _captureCountersOnDone(state);
        return sqliteDone;
      }

      // Subsequent steps: bulk-fetch up to chunkSize rows.
      final result = await _pool!.readRows(
          state.rawHandle, state.columnNames, _readRowsChunkSize);
      state.hasMore = result.hasMore;
      for (final row in result.rows) {
        state.chunk.add(row);
      }
      if (state.chunk.isEmpty) {
        cache.columns = null;
        await _captureCountersOnDone(state);
        return sqliteDone;
      }
      cache.columns = state.chunk.removeFirst();
      return sqliteRow;
    } catch (e) {
      state.lastError = e.toString();
      cache.columns = null;
      return 1; // SQLITE_ERROR
    }
  }

  /// Eagerly captures `getStmtAffectedRows` / `getStmtLastInsertedId`
  /// from the worker on the first `SQLITE_DONE` step. Subsequent
  /// synchronous calls to [getStmtAffectedRows] /
  /// [getStmtLastInsertedId] read the cached values without
  /// round-trips, matching the synchronous native API shape.
  ///
  /// Captures unconditionally regardless of column count: `INSERT …
  /// RETURNING` (and similar) has `columnCount > 0` but still mutates
  /// rows, so `affectedRows` / `lastInsertedId` are meaningful and the
  /// caller's `Reader.onClose` reads them.
  ///
  /// Idempotent — only the first DONE drives the worker round-trips;
  /// further calls (e.g. from `readRowAndCache` invoked again after
  /// DONE) are no-ops. Best-effort: failures leave the cached
  /// defaults (-1, "never stepped").
  Future<void> _captureCountersOnDone(_WebStmtState state) async {
    if (state.countersFetched) return;
    state.countersFetched = true;
    try {
      state.affectedRows =
          await _pool!.getStmtAffectedRows(state.rawHandle);
    } catch (e, st) {
      developer.log(
        'DbasSqliteNativeWeb: getStmtAffectedRows failed at SQLITE_DONE',
        name: 'dbas_sqlite.DbasSqliteNativeWeb',
        error: e,
        stackTrace: st,
      );
    }
    try {
      state.lastInsertedId =
          await _pool!.getStmtLastInsertedId(state.rawHandle);
    } catch (e, st) {
      developer.log(
        'DbasSqliteNativeWeb: getStmtLastInsertedId failed at SQLITE_DONE',
        name: 'dbas_sqlite.DbasSqliteNativeWeb',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  String? getLastStmtError(int dbPtr, int handle) =>
      _stmts[handle]?.lastError ?? _lastError;

  @override
  int getStmtAffectedRows(int dbPtr, int handle) =>
      _stmts[handle]?.affectedRows ?? -1;

  @override
  int getStmtLastInsertedId(int dbPtr, int handle) =>
      _stmts[handle]?.lastInsertedId ?? -1;

  // ── Bindings (positional) ─────────────────────────────────────────────
  // All bind methods buffer Dart-side and return SQLITE_OK synchronously
  // (well, via Future). The buffer is flushed in one `bindParams` worker
  // round-trip on the first `readRowAndCache` call, mirroring how native
  // FFI replays one bind call per slot — except batched into a single
  // postMessage for round-trip efficiency.

  Future<int> _bindPositional(int handle, int index, Object? value) async {
    final state = _stmts[handle];
    if (state == null) return sqliteMisuse;
    state.setPositional(index, value);
    return sqliteOk;
  }

  Future<int> _bindNamed(int handle, String name, Object? value) async {
    final state = _stmts[handle];
    if (state == null) return sqliteMisuse;
    state.setNamed(name, value);
    return sqliteOk;
  }

  @override
  Future<int> bindNull(int dbPtr, int handle, int index) =>
      _bindPositional(handle, index, null);
  @override
  Future<int> bindInt(int dbPtr, int handle, int index, int value) =>
      _bindPositional(handle, index, value);
  @override
  Future<int> bindInt64(int dbPtr, int handle, int index, int value) =>
      _bindPositional(handle, index, value);
  @override
  Future<int> bindFloat(int dbPtr, int handle, int index, double value) =>
      _bindPositional(handle, index, value);
  @override
  Future<int> bindDouble(int dbPtr, int handle, int index, double value) =>
      _bindPositional(handle, index, value);
  @override
  Future<int> bindText(int dbPtr, int handle, int index, String value) =>
      _bindPositional(handle, index, value);
  @override
  Future<int> bindBlob(int dbPtr, int handle, int index, List<int> value) =>
      _bindPositional(
          handle, index, value is Uint8List ? value : Uint8List.fromList(value));

  @override
  Future<int> bindNameNull(int dbPtr, int handle, String name) =>
      _bindNamed(handle, name, null);
  @override
  Future<int> bindNameInt(int dbPtr, int handle, String name, int value) =>
      _bindNamed(handle, name, value);
  @override
  Future<int> bindNameInt64(int dbPtr, int handle, String name, int value) =>
      _bindNamed(handle, name, value);
  @override
  Future<int> bindNameFloat(int dbPtr, int handle, String name, double value) =>
      _bindNamed(handle, name, value);
  @override
  Future<int> bindNameDouble(int dbPtr, int handle, String name, double value) =>
      _bindNamed(handle, name, value);
  @override
  Future<int> bindNameText(int dbPtr, int handle, String name, String value) =>
      _bindNamed(handle, name, value);
  @override
  Future<int> bindNameBlob(int dbPtr, int handle, String name, List<int> value) =>
      _bindNamed(handle, name,
          value is Uint8List ? value : Uint8List.fromList(value));

  // ── Per-handle column accessors ──────────────────────────────────────
  // Native uses these inside its own `readRowAndCache` to walk the
  // current row. On web, `readRowAndCache` populates the [RowData]
  // cache directly from the row payload, so these methods are
  // unreachable. Keep them as throwing stubs so a future code path
  // that mistakenly routes through the platform interface fails loudly
  // rather than silently returning defaults.

  Never _webStubUnreachable(String method) => throw UnsupportedError(
      'Web platform does not use per-handle $method — DbasSqliteReader '
      'reads from the per-row RowData cache populated by '
      'readRowAndCache.');

  @override
  bool isNull(int dbPtr, int handle, int colIndex) =>
      _webStubUnreachable('isNull');
  @override
  String getColumnText(int dbPtr, int handle, int colIndex) =>
      _webStubUnreachable('getColumnText');
  @override
  int getColumnInt(int dbPtr, int handle, int colIndex) =>
      _webStubUnreachable('getColumnInt');
  @override
  int getColumnInt64(int dbPtr, int handle, int colIndex) =>
      _webStubUnreachable('getColumnInt64');
  @override
  double getColumnFloat(int dbPtr, int handle, int colIndex) =>
      _webStubUnreachable('getColumnFloat');
  @override
  double getColumnDouble(int dbPtr, int handle, int colIndex) =>
      _webStubUnreachable('getColumnDouble');
  @override
  List<int> getColumnBlob(int dbPtr, int handle, int columnIndex) =>
      _webStubUnreachable('getColumnBlob');
  @override
  int getColumnBytes(int dbPtr, int handle, int columnIndex) =>
      _webStubUnreachable('getColumnBytes');
  @override
  String getColumnName(int dbPtr, int handle, int columnIndex) =>
      _webStubUnreachable('getColumnName');
  @override
  int getColumnType(int dbPtr, int handle, int colIndex) =>
      _webStubUnreachable('getColumnType');
  @override
  int getColumnCount(int dbPtr, int handle) =>
      _webStubUnreachable('getColumnCount');

  // ── Connection pool ──────────────────────────────────────────────────
  // Web has exactly one worker = one connection. The "pool" surface is
  // a placeholder so the platform-agnostic routing logic in
  // DbasSqliteStatement._executeReaderNative works without a kIsWeb
  // branch: every acquire returns the same placeholder ptr (=1) and
  // release is a no-op.

  @override
  Future<int> createPool(String path, int readerCount) async {
    _pool = await DbasSqliteWebPool.create(
        dbName: dbName, readerCount: readerCount);
    _dbOpened = true;
    await _ensureSqliteVersion();
    return 1;
  }

  @override
  int poolGetWriter(int poolPtr) => 1;
  @override
  int poolAcquireReader(int poolPtr) => 1;
  @override
  Future<int> poolAcquireReaderBlocking(int poolPtr, int timeoutMs) async => 1;
  @override
  void poolReleaseReader(int poolPtr, int readerPtr) {}

  @override
  Future<void> closePool(int poolPtr) async {
    await _pool?.close();
    _pool = null;
    DbasSqliteWebPool.removePool(dbName);
    _dbOpened = false;
    _stmts.clear();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<void> _ensurePool() async {
    if (_pool == null) {
      _pool = await DbasSqliteWebPool.create(
        dbName: dbName,
        readerCount: DbasSqliteNativeInterface.workerPoolSize,
      );
      await _ensureSqliteVersion();
    }
  }
}

/// Per-prepared-statement state on the web side.
///
/// One entry lives in [DbasSqliteNativeWeb._stmts] for each open
/// handle. It owns:
///   - the worker's raw JS BigInt handle (echoed back in postMessage
///     payloads, never inspected on the Dart side);
///   - column metadata captured at prepare time;
///   - the pending bind buffer (positional + named), flushed via one
///     `bindParams` round-trip on the first step;
///   - the chunk queue populated by `readRows` and drained one row per
///     `readRowAndCache` call;
///   - the post-step counter cache for write-shape statements
///     (column count == 0).
class _WebStmtState {
  final JSAny rawHandle;
  final int columnCount;
  final List<String> columnNames;

  // Pending binds — flushed before first step.
  final Map<int, Object?> _positional = {};
  final Map<String, Object?> _named = {};
  bool bindsFlushed = false;

  // Step machinery.
  final Queue<List<ColumnData>> chunk = Queue();
  bool hasMore = true;
  bool firstFetchDone = false;

  // Counters cached on first SQLITE_DONE. Default to -1 ("never
  // stepped") to match the platform-interface contract documented on
  // [DbasSqliteNativeInterface.getStmtAffectedRows] — a stmt that
  // never reached DONE (or whose step failed) reports -1, not 0.
  bool countersFetched = false;
  int affectedRows = -1;
  int lastInsertedId = -1;

  String? lastError;

  _WebStmtState({
    required this.rawHandle,
    required this.columnCount,
    required this.columnNames,
  });

  void setPositional(int index, Object? value) {
    _positional[index] = value;
  }

  void setNamed(String name, Object? value) {
    _named[name] = value;
  }

  /// Build the parameter payload for `bindParams`, in the same shape
  /// the worker's `runBinds` accepts (a List for positional, a Map
  /// for named). Returns `null` when nothing has been bound — the
  /// caller skips the round-trip in that case.
  dynamic mergedParams() {
    if (_positional.isNotEmpty) {
      // Build a dense list indexed by 1-based position.
      final maxIndex =
          _positional.keys.fold<int>(0, (a, b) => a > b ? a : b);
      final list = List<Object?>.filled(maxIndex, null);
      for (final entry in _positional.entries) {
        list[entry.key - 1] = _jsifyBindValue(entry.value);
      }
      return list;
    }
    if (_named.isNotEmpty) {
      final out = <String, dynamic>{};
      for (final e in _named.entries) {
        String name = e.key;
        if (!name.startsWith(':') &&
            !name.startsWith('@') &&
            !name.startsWith(r'$')) {
          name = ':$name';
        }
        out[name] = _jsifyBindValue(e.value);
      }
      return out;
    }
    return null;
  }

  /// Adapt a Dart bind value into the JS shape the worker's
  /// `bindParams` expects. Mirrors the conversion previously done in
  /// `DbasSqliteStatement._jsifyBindValue` — kept here so the platform
  /// layer can be the single converter for web.
  static Object? _jsifyBindValue(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is Enum) return value.index;
    // Blobs MUST cross the postMessage boundary as a typed-array so
    // the JS wrapper's bindParams recognises them via
    // `instanceof Uint8Array` and routes through bindBlob. A raw
    // `List<int>` jsifies to a regular JS Array and gets stringified
    // by the bindText fallback, silently corrupting the bytes.
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return value;
  }
}
