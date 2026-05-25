import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';
import 'package:dbas_sqlite/src/stub/dbas_sqlite_db_stub.dart'
    show
        sqliteOk,
        sqliteRow,
        sqliteDone,
        sqliteMisuse,
        sqliteInvalidStmtHandle;
import 'dbas_sqlite_native_interface.dart';
import 'web/dbas_sqlite_web_live_pool.dart';
import 'web/dbas_sqlite_web_pool.dart';
import 'web/dbas_sqlite_web_reader_pool.dart';

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
///   4. On every `SQLITE_DONE` (regardless of column count), the
///      per-stmt counters are eagerly fetched via
///      `getStmtAffectedRows` / `getStmtLastInsertedId` so the
///      synchronous platform getters can return cached values without
///      a round-trip. Capturing unconditionally covers
///      `INSERT … RETURNING` (which has `columnCount > 0` but still
///      mutates rows) as well as plain DML.
///   5. [finalizeStmt] sends `finalizeStmt` to the worker and drops
///      the Dart-side state. Worker failures propagate as a non-OK rc
///      so the reader's `onClose` cleanup block in
///      `DbasSqliteStatement` captures and rethrows them.
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

  /// Connection-role tokens handed to the statement layer as opaque
  /// "pointers". The layer stores one as a `DbasSqliteDb.ptr` and passes
  /// it back as `dbPtr` on every per-statement call; [prepareQuery] routes
  /// reads vs. writes on it. The writer token doubles as the
  /// single-connection / fallback pointer returned by [openDb].
  static const int _writerConn = 1;
  static const int _readerConn = 2;

  /// The live read/write pool. A multi-worker [DbasSqliteWebReaderPool]
  /// (reads on reader connections, writes on the writer connection — true
  /// concurrency) when the page is cross-origin isolated; otherwise a
  /// single-worker fallback. Destructive file operations use a separate
  /// transient [DbasSqliteWebPool] (see [_withTempPool]), never this.
  WebLivePool? _pool;
  bool _initialized = false;
  String _sqliteVersion = '';
  final int _abiVersion = 0;
  int _lastAffectedRows = 0;
  int _lastInsertedId = 0;
  String? _lastError;

  /// Cached SQLite primary / extended rcs from the most recent worker
  /// error. Populated whenever a caught [DbasSqliteWebWorkerError]
  /// flows through any of the methods on this shim that touch the
  /// pool. Returned from [getErrorCode] / [getUniqueErrorCode] so the
  /// public exception can surface both codes parallel to native.
  int? _lastErrorCode;
  int? _lastUniqueErrorCode;

  /// Per-handle prepared-statement state. Keyed by the Dart-side
  /// `int` handle returned from [prepareQuery] (a monotonic counter
  /// — see [_nextStmtId]). The worker's actual handle (a JS BigInt)
  /// lives inside [_WebStmtState.rawHandle] so we can echo it back to
  /// the worker without round-tripping through Dart `BigInt`.
  final Map<int, _WebStmtState> _stmts = {};
  int _nextStmtId = 1;

  // ── Destructive-op / regular-op access discipline ─────────────────────
  //
  // Destructive operations (the [_teardownLivePool] path behind
  // [closeDb] / [closePool] / [attachDb] / [attachStreamDb] / [dropDb] /
  // [getContent]) tear the worker down and replace the OPFS file. If
  // they fire while a statement lifecycle (prepare → bind → read →
  // finalize) or a single-shot [executeSql] is still in flight on the
  // live pool, they sever it and surface a spurious "Pool is closed"
  // error — the symptom seen when a background queue queries the DB at
  // the same moment the login flow attaches a downloaded snapshot.
  //
  // The discipline is a minimal shared/exclusive gate:
  //   - Regular work that OPENS new pool activity ([executeSql],
  //     [prepareQuery], [streamCopyDb]) waits behind [_exclusiveGate]
  //     so it queues after an in-progress destructive op instead of
  //     racing it, and counts itself into [_inFlightCalls] /
  //     [_stmts] so a destructive op can tell when the pool is busy.
  //   - Continuation calls on an already-open statement
  //     (`bind*` / [readRowAndCache] / [finalizeStmt]) are deliberately
  //     NOT gated. Gating them would deadlock: a destructive op holding
  //     the gate waits for the statement to finalize, but the finalize
  //     would be waiting on the gate. Leaving them ungated lets the
  //     open statement drain to completion while the destructive op
  //     waits for quiescence.
  //   - [_teardownLivePool] raises [_exclusiveGate], waits for
  //     quiescence (no in-flight calls, no open statements) bounded by
  //     a timeout, then closes the pool and lowers the gate.

  /// Non-null while a destructive op holds (or is waiting to hold)
  /// exclusive access. New gated work awaits its future.
  Completer<void>? _exclusiveGate;

  /// Count of in-flight gated calls ([executeSql] / [prepareQuery] /
  /// [streamCopyDb]) that have passed the gate but not yet returned.
  /// Combined with `_stmts.isEmpty`, defines pool quiescence.
  int _inFlightCalls = 0;

  /// Completed by [_signalIfQuiescent] when the pool becomes quiescent,
  /// unblocking a destructive op waiting in [_teardownLivePool].
  Completer<void>? _quiescent;

  /// Max time [_teardownLivePool] waits for in-flight work to drain
  /// before forcing the close. Bounds the impact of a leaked (never
  /// finalized) statement — after this the close proceeds and the
  /// leaked op's next call gets a clean "Pool is closed".
  static const Duration _teardownDrainTimeout = Duration(seconds: 5);

  bool get _poolQuiescent => _inFlightCalls == 0 && _stmts.isEmpty;

  /// Enters a gated regular operation: waits behind any in-progress
  /// destructive op, then registers this call as in-flight. The
  /// `_inFlightCalls++` runs synchronously after the final gate
  /// null-check with no `await` between them, so a destructive op
  /// cannot claim the gate between the check and the increment (Dart's
  /// single-threaded loop can't interleave a synchronous run). Pair
  /// every call with [_exitGated] in a `finally`.
  Future<void> _enterGated() async {
    while (_exclusiveGate != null) {
      await _exclusiveGate!.future;
    }
    _inFlightCalls++;
  }

  /// Exits a gated regular operation and wakes a waiting destructive op
  /// if the pool just went quiescent.
  void _exitGated() {
    _inFlightCalls--;
    _signalIfQuiescent();
  }

  /// Wakes a destructive op waiting on quiescence once the last
  /// in-flight call returns / the last open statement is finalized.
  void _signalIfQuiescent() {
    if (_poolQuiescent) {
      _quiescent?.complete();
      _quiescent = null;
    }
  }

  /// Monotonic per-instance diagnostic ID. Lets lifecycle logging
  /// distinguish between sibling instances that share the same pool
  /// via `_pools[dbName]`.
  static int _instanceIdSeq = 0;
  final int _instanceId = ++_instanceIdSeq;

  DbasSqliteNativeWeb(super.dbName) {
    developer.log(
      'DbasSqliteNativeWeb instance id=$_instanceId(dbName=$dbName) constructed',
      name: 'dbas_sqlite.lifecycle',
    );
  }

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
      _captureError(e, 'getSqliteVersion via pool.query failed');
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
    // Single-connection fallback path (`DbasSqlite.openDb` calls this
    // when the caller opts out of pool creation — `readerPoolSize <= 0`
    // — or when `createPool` returned 0). Web has no "no-pool" mode —
    // every worker call routes through a [DbasSqliteWebPool] — so
    // ensure one exists. Without this, the fallback would leave
    // `_pool == null` while [isOpened] (derived from pool liveness)
    // reported false, and the next `openDb()` on the same instance
    // would re-enter this path instead of being a no-op as the
    // idempotent contract promises.
    //
    // Gated so a re-open queued right after a destructive op (e.g. the
    // `openDb` that `DbasSqlite.attachDb` issues) waits for that op to
    // finish instead of racing a fresh pool against it.
    await _enterGated();
    try {
      await _ensurePool();
    } finally {
      _exitGated();
    }
    return 1;
  }

  @override
  Future<bool> databaseExists(String fileName) async {
    // Native FFI parity: `databaseExists` is a no-side-effect probe —
    // it reports whether the DB file is present on disk, and a `false`
    // return MUST NOT cause the file to materialize. The Dart-VM impl
    // is a one-line `File(path).existsSync()`.
    //
    // The previous web implementation routed through the worker —
    // `DbasSqliteWebPool.create()` → `pool.send('exists')` — which
    // forced an `init` round-trip on the worker. `init` calls the
    // WASM lib's `initPersistentFS`, which opens the SQLite DB with
    // create-or-open semantics AND walks `openOpfsHandles` to call
    // `opfsDir.getFileHandle(name, {create: true})` for the four
    // SQLite files (`name.db`, `-journal`, `-wal`, `-shm`). That
    // creates the file as a side-effect, so the immediately-following
    // `exists` action always returned `true` — and any caller that
    // used `databaseExists` as a "should I run the first-time
    // bootstrap?" gate (e.g. `SessionLifecycle._defaultSessionWriter`
    // upserting a row before the migrator has had a chance to create
    // the schema) silently skipped the bootstrap and then crashed on
    // a downstream "no such table" prepare. Symptom seen in consumers:
    // "no such table: dbas_Session" on first-ever login.
    //
    // The fix is to bypass the worker for the probe and check OPFS
    // directly from Dart — no init, no file creation, no side effects
    // — matching native FFI's semantics 1:1.
    //
    // Live-pool short-circuit: if our own [_pool] is alive, the file
    // is loaded into the worker and definitionally exists. Skip the
    // OPFS round-trip in that case (covers the hot path where the DB
    // is already open).
    final live = _pool;
    if (live != null && !live.isClosed) return true;
    return await _opfsFileExists(_normalizedDbName);
  }

  /// OPFS-direct existence probe, no worker / WASM involved. Looks
  /// for the SQLite file at the exact path the WASM lib's
  /// `initPersistentFS` mounts: `dbas_data/<dbName>` under
  /// `navigator.storage.getDirectory()`. The `create: false` options
  /// guarantee a NotFoundError throw when the file (or the parent
  /// `dbas_data` directory) is missing, which we catch and convert to
  /// a `false` return.
  ///
  /// Other failure modes (SecurityError when COOP/COEP isn't set,
  /// QuotaExceededError, TypeError when `navigator.storage` is missing
  /// in a stripped-down WebView, …) are logged before falling through
  /// to `false`. The fallthrough preserves the no-side-effect contract
  /// — `databaseExists` is allowed to be wrong-but-fail-closed; the
  /// downstream bootstrap will then re-hit the same broken OPFS and
  /// surface the real error from there. Logging here ensures the
  /// originating cause isn't lost in the symptom downstream.
  Future<bool> _opfsFileExists(String fileName) async {
    try {
      final root = await web.window.navigator.storage.getDirectory().toDart;
      final dir = await root
          .getDirectoryHandle(
            _opfsDataDirName,
            web.FileSystemGetDirectoryOptions(create: false),
          )
          .toDart;
      await dir
          .getFileHandle(
            fileName,
            web.FileSystemGetFileOptions(create: false),
          )
          .toDart;
      return true;
    } catch (e, st) {
      // Read the DOMException discriminator via the spec-guaranteed
      // `${name}: ${message}` stringifier (WHATWG WebIDL) instead of
      // `is web.DOMException`. The analyzer's
      // `invalid_runtime_check_with_js_interop_types` lint flags
      // runtime checks against JS interop extension types as
      // platform-inconsistent — every Dart value on web is also a JS
      // value at runtime, so `is`/`as` doesn't mean what it looks
      // like. Pattern-matching on toString() sidesteps the interop
      // type system altogether.
      final msg = e.toString();
      if (msg.startsWith('NotFoundError:')) return false;
      developer.log(
        'DbasSqliteNativeWeb._opfsFileExists: OPFS probe for '
        '"$fileName" failed with a non-NotFoundError; treating as '
        'not-present so caller bootstrap proceeds.',
        name: 'dbas_sqlite.DbasSqliteNativeWeb',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// dbName normalized to the on-disk filename the WASM lib uses.
  /// Mirrors `initialize()` in `dbas_sqlite.js`:
  /// `this.dbName = e.endsWith(".db") ? e : "${e}.db"`.
  String get _normalizedDbName =>
      dbName.endsWith('.db') ? dbName : '$dbName.db';

  /// OPFS subdirectory the WASM lib creates inside
  /// `navigator.storage.getDirectory()` and where it puts every
  /// SQLite file. Mirrors the literal in `initialize()`:
  /// `r.getDirectoryHandle("dbas_data", {create: true})`.
  static const String _opfsDataDirName = 'dbas_data';

  @override
  bool isOpened(int dbPtr) => _pool != null && !_pool!.isClosed;

  @override
  Future<int> closeDb(int dbPtr, {bool checkpoint = false}) async {
    await _runExclusive(_teardownLivePool);
    return sqliteOk;
  }

  // ── File operations (via worker protocol) ─────────────────────────────

  @override
  Future attachDb(String fileName, List<int> content) async {
    // Destructive: replaces the OPFS file. Runs under [_runExclusive]
    // so the teardown + transient-pool attach are serialized against
    // in-flight queries and no fresh live pool is spawned for the same
    // OPFS file mid-attach. Tear down the live pool first so the worker
    // holding the writer connection releases the file, then perform the
    // attach against a transient pool. Leaves `_pool == null` so the
    // next `DbasSqlite.openDb()` re-creates against the freshly-attached
    // file.
    await _runExclusive(() async {
      await _teardownLivePool();
      await _withTempPool((pool) async {
        // Eager input: the caller already has the full buffer in memory,
        // so the chunked-attach protocol receives it as a single chunk.
        // Memory-friendly attach should use `attachStreamDb` with a real
        // source stream instead.
        await pool.attachStreamChunked(
          Stream.fromIterable([content]),
          totalSize: content.length,
        );
      });
    });
  }

  @override
  Future attachStreamDb(String fileName, Stream<List<int>> stream) async {
    await _runExclusive(() async {
      await _teardownLivePool();
      await _withTempPool((pool) => pool.attachStreamChunked(stream));
    });
  }

  @override
  Future<List<int>> getContent(String fileName) async {
    // Snapshot export: closing the live pool first lets the worker
    // checkpoint and release the OPFS file before the transient pool
    // reads it, and prevents a concurrent writer from racing the
    // export. The bytes are read against a transient pool; the live
    // pool stays torn down (caller re-opens via `DbasSqlite.openDb`
    // if it wants to keep using the database).
    return await _runExclusive(() async {
      await _teardownLivePool();
      return await _withTempPool((pool) => pool.exportContentStream());
    });
  }

  @override
  Future<void> streamCopyDb(String sourceFileName, String destFileName) async {
    String destName = destFileName;
    if (destFileName.contains('/')) destName = destFileName.split('/').last;
    // Whole-file copy needs exclusive access to a consistent on-disk DB.
    // Like attach / export / drop, tear the live pool down first (so its
    // writer flushes and releases the OPFS file), then copy against a
    // transient single-worker pool — the multi-worker live pool exposes
    // no streamCopy. The live pool is re-created lazily on the next
    // operation via [_ensurePool].
    await _runExclusive(() async {
      await _teardownLivePool();
      await _withTempPool((pool) => pool.streamCopy(destName));
    });
  }

  @override
  Future dropDb(String fileName) async {
    await _runExclusive(() async {
      await _teardownLivePool();
      await _withTempPool((pool) => pool.drop());
    });
  }

  // ── No-params SQL (BEGIN/COMMIT/ROLLBACK/VACUUM/PRAGMA) ──────────────
  // Used for system SQL with no bindings. Goes through `pool.exec` —
  // the worker's `exec` action wraps `sqlite3_exec`, so it accepts
  // multi-statement input and runs in a single worker round-trip.
  // Statement-level writes with bindings (`Statement.executeSql`) go
  // through the per-stmt prepare/bind/step/finalize chain instead, so
  // the same Dart code path runs on native and web.

  @override
  Future<int> executeSql(int dbPtr, String sql) async {
    await _enterGated();
    try {
      await _ensurePool();
      final result = await _pool!.exec(sql);
      _lastAffectedRows = toIntSafe(result['affectedRows']);
      _lastInsertedId = toIntSafe(result['lastInsertId']);
      _lastError = null;
      _lastErrorCode = null;
      _lastUniqueErrorCode = null;
      return sqliteOk;
    } catch (e) {
      // Return a non-OK rc and cache the codes rather than rethrowing.
      // Rethrowing would let a raw [DbasSqliteWebWorkerError] escape
      // the platform boundary and bypass the rc-based wrapping in
      // `DbasSqlite.beginTransaction` / `commit` / `rollback` /
      // `vacuum` — those wrappers fire on `rc != sqliteOk` and rely on
      // [getErrorCode] / [getUniqueErrorCode] to lift the codes onto
      // the public [DbasSqliteException].
      _captureError(e);
      return 1; // SQLITE_ERROR
    } finally {
      _exitGated();
    }
  }

  // ── State accessors (last-write outcome) ──────────────────────────────

  @override
  String? getLastDbError(int dbPtr) => _lastError;

  @override
  int? getErrorCode(int dbPtr) => _lastErrorCode;

  @override
  int? getUniqueErrorCode(int dbPtr) => _lastUniqueErrorCode;

  /// Updates [_lastError] + the two rc caches from a caught error. Use
  /// from every `catch` block that talks to the worker so the public
  /// exception surface can read [getErrorCode] / [getUniqueErrorCode]
  /// immediately afterwards.
  ///
  /// When [e] is a [DbasSqliteWebWorkerError] the rcs are updated from
  /// its `sqliteCode` / `sqliteUniqueCode`. For any other exception type
  /// (Dart-side `StateError`, plain `Exception`, etc.) the rc caches
  /// are LEFT UNCHANGED rather than nulled — clobbering them would
  /// erase legitimate codes captured by a concurrent worker error
  /// whose downstream consumer hasn't yet read them.
  void _captureError(Object e, [String? prefix]) {
    _lastError = prefix != null ? '$prefix: $e' : e.toString();
    if (e is DbasSqliteWebWorkerError) {
      _lastErrorCode = e.sqliteCode;
      _lastUniqueErrorCode = e.sqliteUniqueCode;
    }
    // else: non-worker error has no SQLite rc info — preserve any
    // previously-captured rcs so callers reading getErrorCode /
    // getUniqueErrorCode after the originating worker failure still
    // see them.
  }
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
      _captureError(e, 'enableWal');
      return 1; // SQLITE_ERROR
    }
  }

  // ── Prepared-statement lifecycle ──────────────────────────────────────

  @override
  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(int dbPtr, String sql) async {
    // Gate + count the prepare so a destructive op cannot tear the pool
    // down between this call and the statement's later bind/read/finalize
    // steps. The in-flight count covers the prepare round-trip itself;
    // once the statement is registered in [_stmts] its entry keeps the
    // pool "busy" until [finalizeStmt] removes it (so quiescence is not
    // reached until the whole statement lifecycle completes).
    await _enterGated();
    try {
      await _ensurePool();
      // Route the prepare to the connection role the statement layer
      // picked: the reader token → a reader connection; anything else
      // (the writer token, and the single-connection fallback pointer
      // from [openDb]) → the writer connection. The pool holds the
      // matching cross-handle fence for the cursor's lifetime — SHARED
      // for reads, EXCLUSIVE for writes (decided in the worker via
      // sqlite3_stmt_readonly).
      final prep = await _pool!.streamPrepare(dbPtr != _readerConn, sql);
      final handle = _nextStmtId++;
      _stmts[handle] = _WebStmtState(
        cursor: prep.cursor,
        columnCount: prep.columnCount,
        columnNames: prep.columnNames,
      );
      return (
        handle: handle,
        columnCount: prep.columnCount,
        columnNames: prep.columnNames,
      );
    } catch (e) {
      // Capture so the statement layer's `executeXxxPrepareFailed`
      // throw can surface the worker's rc / extendedRc via
      // [getErrorCode] / [getUniqueErrorCode] on this shim. Return
      // the invalid-handle sentinel to match native's "bad rc → null
      // handle" shape rather than letting the raw worker error
      // escape the platform boundary.
      _captureError(e);
      return (
        handle: sqliteInvalidStmtHandle,
        columnCount: 0,
        columnNames: const <String>[],
      );
    } finally {
      _exitGated();
    }
  }

  @override
  Future<int> finalizeStmt(int dbPtr, int handle) async {
    final state = _stmts.remove(handle);
    if (state == null) return sqliteOk; // already finalized / unknown
    try {
      await _pool!.streamFinalize(state.cursor);
      return sqliteOk;
    } catch (e, st) {
      developer.log(
        'DbasSqliteNativeWeb.finalizeStmt: pool.finalizeStmt failed',
        name: 'dbas_sqlite.DbasSqliteNativeWeb',
        error: e,
        stackTrace: st,
      );
      // Surface the failure rc so the reader's `onClose` 3-stage
      // cleanup captures it (statement.dart populates `firstErr` from
      // each non-OK finalize and rethrows after the release step).
      // Native FFI's `finalizeStmt` returns the C-level rc directly;
      // the previous "always sqliteOk" lie hid worker-side leaks the
      // caller could otherwise have surfaced through `getLastDbError`.
      _captureError(e, 'finalizeStmt failed');
      return 1; // SQLITE_ERROR
    } finally {
      // The statement was removed from [_stmts] above; if it was the
      // last open statement (and no gated call is in flight) the pool
      // is now quiescent — wake any destructive op waiting to tear
      // down. Posting the finalize message happens synchronously inside
      // `_pool!.finalizeStmt` before this finally's await-resumed
      // continuation runs, so a teardown that proceeds here still sees
      // the finalize FIFO-ordered ahead of its own `close` message.
      _signalIfQuiescent();
    }
  }

  @override
  Future<int> readRowAndCache(int dbPtr, int handle, RowData cache) async {
    final state = _stmts[handle];
    if (state == null) return sqliteMisuse;
    cache.columnCount = state.columnCount;
    cache.columnNames = state.columnNames;

    // Binds were applied eagerly by [_bindOne] (one worker round-trip
    // per `bind*` / `bindName*` call), and each call returned its own
    // rc to the statement layer — `DbasSqliteStatement._replayBinds`
    // is what enforces the per-rc contract on those returns. No
    // deferred flush is needed here; proceed straight to the row
    // machinery.

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
            await _pool!.streamReadRow(state.cursor, state.columnNames);
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
      final result = await _pool!.streamReadRows(
          state.cursor, state.columnNames, _readRowsChunkSize);
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
      _captureError(e);
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
          await _pool!.streamAffectedRows(state.cursor);
    } catch (e, st) {
      developer.log(
        'DbasSqliteNativeWeb: getStmtAffectedRows failed at SQLITE_DONE',
        name: 'dbas_sqlite.DbasSqliteNativeWeb',
        error: e,
        stackTrace: st,
      );
      // Populate lastError so the caller's `getLastStmtError` (read by
      // the reader's `onClose` block) can distinguish "counter probe
      // failed" from "stmt was never stepped" (both default values
      // are -1 otherwise).
      state.lastError ??= 'getStmtAffectedRows failed at SQLITE_DONE: $e';
    }
    try {
      state.lastInsertedId =
          await _pool!.streamLastInsertedId(state.cursor);
    } catch (e, st) {
      developer.log(
        'DbasSqliteNativeWeb: getStmtLastInsertedId failed at SQLITE_DONE',
        name: 'dbas_sqlite.DbasSqliteNativeWeb',
        error: e,
        stackTrace: st,
      );
      state.lastError ??=
          'getStmtLastInsertedId failed at SQLITE_DONE: $e';
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

  // ── Bindings ─────────────────────────────────────────────────────────
  // Every bind method makes ONE worker round-trip via [DbasSqliteWebPool.bindParam]
  // and returns the actual SQLite rc — matching native FFI's per-call
  // `sqlite3_bind_*` semantics 1:1. The statement layer's `_replayBinds`
  // then sees the same rc behaviour on both platforms, including the
  // `SQLITE_RANGE` skip on missing named parameters that the
  // `bindNameParameters` docstring promises ("silently skipped …
  // matching Microsoft.Data.Sqlite").
  //
  // The previous shim buffered Dart-side and flushed in one batched
  // `bindParams` postMessage. That broke the contract: the WASM
  // `bindParams` is all-or-nothing, so one missing named slot threw
  // `SQLITE_RANGE` for the whole batch and surfaced as
  // `executeSqlStepFailed` instead of being silently skipped.

  Future<int> _bindOne(int handle, Object param, Object? value) async {
    final state = _stmts[handle];
    if (state == null) return sqliteMisuse;
    await _ensurePool();
    try {
      await _pool!.streamBind(state.cursor, param, _jsifyBindValue(value));
      return sqliteOk;
    } on DbasSqliteWebWorkerError catch (e) {
      // Worker reported a non-OK rc. Surface it to the statement
      // layer's `_replayBinds`, which decides per-rc whether to skip
      // (default for `SQLITE_RANGE` on named binds) or throw.
      state.lastError = e.message;
      _captureError(e);
      return e.sqliteCode ?? 1;
    } catch (e) {
      // Worker / protocol-level failure (not a SQLite rc). Surface as
      // generic SQLITE_ERROR so the statement layer's error path picks
      // it up via [getLastStmtError] / [getErrorCode].
      state.lastError = e.toString();
      _captureError(e);
      // Clear cached worker rcs so `_replayBinds`'s
      // `getErrorCode() ?? rc` fallback (in the positional,
      // named-RANGE, and named-other branches of
      // `DbasSqliteStatement._replayBinds`) uses the local
      // SQLITE_ERROR rc returned below instead of reporting a stale
      // code captured by an earlier, unrelated worker error. This
      // differs from [_captureError]'s general "preserve rcs across
      // follow-up Dart exceptions" stance — here the returned rc is
      // the authoritative signal for this bind, so internal
      // consistency wins over preservation.
      _lastErrorCode = null;
      _lastUniqueErrorCode = null;
      return 1; // SQLITE_ERROR
    }
  }

  @override
  Future<int> bindNull(int dbPtr, int handle, int index) =>
      _bindOne(handle, index, null);
  @override
  Future<int> bindInt(int dbPtr, int handle, int index, int value) =>
      _bindOne(handle, index, value);
  @override
  Future<int> bindInt64(int dbPtr, int handle, int index, int value) =>
      _bindOne(handle, index, value);
  @override
  Future<int> bindFloat(int dbPtr, int handle, int index, double value) =>
      _bindOne(handle, index, value);
  @override
  Future<int> bindDouble(int dbPtr, int handle, int index, double value) =>
      _bindOne(handle, index, value);
  @override
  Future<int> bindText(int dbPtr, int handle, int index, String value) =>
      _bindOne(handle, index, value);
  @override
  Future<int> bindBlob(int dbPtr, int handle, int index, List<int> value) =>
      _bindOne(handle, index,
          value is Uint8List ? value : Uint8List.fromList(value));

  @override
  Future<int> bindNameNull(int dbPtr, int handle, String name) =>
      _bindOne(handle, name, null);
  @override
  Future<int> bindNameInt(int dbPtr, int handle, String name, int value) =>
      _bindOne(handle, name, value);
  @override
  Future<int> bindNameInt64(int dbPtr, int handle, String name, int value) =>
      _bindOne(handle, name, value);
  @override
  Future<int> bindNameFloat(int dbPtr, int handle, String name, double value) =>
      _bindOne(handle, name, value);
  @override
  Future<int> bindNameDouble(int dbPtr, int handle, String name, double value) =>
      _bindOne(handle, name, value);
  @override
  Future<int> bindNameText(int dbPtr, int handle, String name, String value) =>
      _bindOne(handle, name, value);
  @override
  Future<int> bindNameBlob(int dbPtr, int handle, String name, List<int> value) =>
      _bindOne(handle, name,
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
    _pool = await bootWebLivePool(dbName: dbName, readerCount: readerCount);
    await _ensureSqliteVersion();
    return 1;
  }

  // The web "pool pointer" is a fixed sentinel — there is exactly one
  // live pool per instance. The writer/reader tokens below are what the
  // statement layer threads back as `dbPtr`, and [prepareQuery] routes a
  // prepare to the writer or a reader connection based on which it sees.
  @override
  int poolGetWriter(int poolPtr) => _writerConn;
  @override
  int poolAcquireReader(int poolPtr) => _readerConn;
  @override
  Future<int> poolAcquireReaderBlocking(int poolPtr, int timeoutMs) async =>
      _readerConn;
  @override
  void poolReleaseReader(int poolPtr, int readerPtr) {}

  @override
  Future<void> closePool(int poolPtr) async {
    await _runExclusive(_teardownLivePool);
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<void> _ensurePool() async {
    final existing = _pool;
    if (existing != null && !existing.isClosed) return;
    // `existing` is either null or stale-closed. Stale-closed happens
    // when another `DbasSqliteNativeWeb` instance for the same dbName
    // closed the shared pool object that this instance's `_pool` field
    // still references — `_pools` is keyed by dbName and a sibling's
    // `_teardownLivePool` flips `_closed` on the object we hold. No
    // in-tree caller produces this from a single instance after the
    // probe-side teardown bug was fixed; the branch survives as a
    // defensive guard against multi-instance use of the same dbName.
    //
    // Clear `_stmts` symmetrically with [_teardownLivePool] so cached
    // raw JS BigInt handles bound to the dead worker's WASM heap don't
    // leak into the fresh worker (which would reject them with
    // UNKNOWN_HANDLE on next use).
    if (existing != null) _stmts.clear();
    _pool = await bootWebLivePool(
      dbName: dbName,
      readerCount: DbasSqliteNativeInterface.workerPoolSize,
    );
    await _ensureSqliteVersion();
  }

  /// Runs [action] with exclusive access to the pool. Raises
  /// [_exclusiveGate] so new gated work ([executeSql] / [prepareQuery] /
  /// [streamCopyDb]) queues behind it, waits for the pool to go
  /// quiescent (no in-flight gated call, no open statement) so an
  /// in-flight query is never severed mid-flight, then runs [action].
  /// The gate is held for the WHOLE action, so a destructive op that
  /// tears down and then works against a transient pool (attach / drop /
  /// export) cannot have a fresh live pool spawned underneath it for the
  /// same OPFS file.
  ///
  /// The quiescence drain is bounded by [_teardownDrainTimeout] so a
  /// leaked (never-finalized) statement cannot wedge a destructive op
  /// forever — after the timeout the op proceeds and the leaked
  /// statement's next call gets a clean "Pool is closed".
  ///
  /// Continuation calls on an already-open statement (`bind*` /
  /// [readRowAndCache] / [finalizeStmt]) are intentionally NOT gated, so
  /// they can drain the open statement while this method waits.
  Future<T> _runExclusive<T>(Future<T> Function() action) async {
    // Atomically wait-for-then-claim the gate: the `_exclusiveGate =
    // gate` assignment runs synchronously after the final null-check
    // with no `await` between, so two racing destructive ops cannot
    // both claim it.
    while (_exclusiveGate != null) {
      await _exclusiveGate!.future;
    }
    final gate = Completer<void>();
    _exclusiveGate = gate;
    try {
      if (!_poolQuiescent) {
        final idle = _quiescent ??= Completer<void>();
        try {
          await idle.future.timeout(_teardownDrainTimeout);
        } on TimeoutException {
          developer.log(
            'instance id=$_instanceId(dbName=$dbName) _runExclusive drain '
            'timed out with _stmts.length=${_stmts.length}, '
            '_inFlightCalls=$_inFlightCalls; proceeding',
            name: 'dbas_sqlite.DbasSqliteNativeWeb',
          );
          _quiescent = null;
        }
      }
      return await action();
    } finally {
      _exclusiveGate = null;
      gate.complete();
    }
  }

  /// Tears down the live pool and resets all state that depends on it.
  /// MUST be called inside [_runExclusive] (directly or as part of a
  /// destructive op's action) so the close is serialized against
  /// in-flight queries and other destructive ops.
  ///
  /// Safe to call when no pool is live — becomes a no-op so destructive
  /// callers do not have to guard.
  ///
  /// Ordering: close before nulling `_pool`. A concurrent [_ensurePool]
  /// caller then sees the still-set (but `isClosed == true`) pool,
  /// falls through to [DbasSqliteWebPool.create], and awaits the
  /// `_closing` barrier — which holds until the worker confirms its
  /// `closeOpfsHandles()` drain, so a fresh worker is never spawned
  /// against a file the previous worker still owns.
  Future<void> _teardownLivePool() async {
    final pool = _pool;
    developer.log(
      'instance id=$_instanceId(dbName=$dbName) _teardownLivePool entry; '
      'pool id=${pool?.poolId} closed=${pool?.isClosed} '
      '_stmts.length=${_stmts.length}',
      name: 'dbas_sqlite.lifecycle',
    );
    if (pool != null) await pool.close();
    _pool = null;
    _stmts.clear();
  }

  /// Runs [action] against a transient pool that is NOT shared with
  /// [_pool]. Used by destructive file operations and by
  /// [databaseExists] when no live pool exists. The transient pool is
  /// closed afterwards; `close()` registers the static `_closing`
  /// barrier and only drops the `_pools` entry after the worker
  /// confirms the OPFS drain, so a subsequent [_ensurePool] /
  /// [createPool] either reuses an entry that is genuinely live or
  /// waits for the drain before spawning a fresh worker.
  ///
  /// Pre-condition: caller has already torn down the live pool via
  /// [_teardownLivePool] if the action requires exclusive file access
  /// — mutation, full-file export, or any other operation incompatible
  /// with a concurrent live writer — since `DbasSqliteWebPool.create`
  /// is get-or-create and would otherwise hand back the live pool.
  ///
  /// If [action] throws, the original exception is preserved: a
  /// failure inside the finally-block `close()` is logged via
  /// `dart:developer` rather than rethrown, so callers see the real
  /// root cause instead of a downstream cleanup error.
  Future<T> _withTempPool<T>(
      Future<T> Function(DbasSqliteWebPool pool) action) async {
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    try {
      return await action(pool);
    } finally {
      try {
        await pool.close();
      } catch (e, st) {
        developer.log(
          'DbasSqliteNativeWeb._withTempPool: transient pool close '
          'failed for "$dbName"',
          name: 'dbas_sqlite.DbasSqliteNativeWeb',
          error: e,
          stackTrace: st,
        );
      }
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
  /// Opaque pool cursor token for this statement: a pool-level cursor id
  /// (multi-worker pool) or the worker's raw statement handle
  /// (single-worker fallback). Echoed back on every per-stmt call; never
  /// inspected here.
  final Object cursor;
  final int columnCount;
  final List<String> columnNames;

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
    required this.cursor,
    required this.columnCount,
    required this.columnNames,
  });
}

/// Adapts a Dart bind value into the JS shape the worker's
/// `bindParam` expects. The conversions mirror what the native FFI's
/// per-type `bind*` functions do implicitly:
///   - `bool` → 0/1 (native uses `bindInt` with `value ? 1 : 0`),
///   - `Enum` → `index` (native uses `bindInt(enum.index)`),
///   - `List<int>` → `Uint8List` so the postMessage layer routes the
///     bytes through `bindBlob` rather than stringifying them via
///     `bindText` (which would silently corrupt the payload).
Object? _jsifyBindValue(Object? value) {
  if (value == null) return null;
  if (value is bool) return value ? 1 : 0;
  if (value is Enum) return value.index;
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  return value;
}
