import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'dbas_sqlite_native_interface.dart';
import 'dbas_sqlite_web_pool.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';

/// Web implementation backed by the JS pool wrapper
/// (`web/libs/dbas_sqlite.js` + `dbas_sqlite_worker.js`).
///
/// Writes go through `pool.exec` via [executeStatementWrite] (one
/// round-trip per statement, atomic on the worker side).
///
/// Reads go through the worker's per-statement streaming RPC
/// (`prepareQuery` / `bindParams` / `readRow` / `finalizeStmt`,
/// available since worker bundle v4.4.1) via [executeStatementRead].
/// Each `readRow()` call streams exactly one row across the worker
/// boundary — matching the native FFI behaviour. The wrapper-level
/// per-stmt ABI methods on [DbasSqliteNativeInterface] (`prepareQuery`,
/// `bindNull`, `getColumnText`, etc.) are **not** used on web; the
/// pool's [DbasSqliteWebPool.prepareQueryStream] / `bindParams` /
/// `readRow` / `finalizeStmt` primitives drive the streaming reader
/// directly.
///
/// The single-connection fallback path (when the JS pool fails to
/// initialise) is not implemented; consumers requiring it will get
/// an `UnsupportedError` from the per-stmt ABI stubs below.
class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  DbasSqliteWebPool? _pool;
  bool _initialized = false;
  bool _dbOpened = false;
  String _sqliteVersion = '';
  final int _abiVersion = 0;
  int _lastAffectedRows = 0;
  int _lastInsertedId = 0;
  String? _lastError;

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
      // Best-effort — keep the empty string if the query fails. But log
      // loudly so a genuine pool-side failure (worker crashed, OPFS
      // detached, etc.) doesn't disappear into _lastError where most
      // callers will never see it.
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
    final result = await pool.send('exists');
    return result == true;
  }

  @override
  bool isOpened(int dbPtr) => _dbOpened;

  @override
  Future<int> closeDb(int dbPtr, {bool checkpoint = false}) async {
    await _pool?.close();
    _pool = null;
    DbasSqliteWebPool.removePool(dbName);
    _dbOpened = false;
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

  // ── SQL execution (one-shot, used by transaction primitives) ──────────

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

  // ── New statement-mediation entry points ─────────────────────────────

  /// Used by `DbasSqliteStatement.executeSql` on web.
  /// Always routes through the writer worker via `pool.exec`.
  Future<({int affectedRows, int lastInsertedId})> executeStatementWrite(
      String sql, dynamic params) async {
    await _ensurePool();
    try {
      final result = await _pool!.exec(sql, params);
      final ar = toIntSafe(result['affectedRows']);
      final lid = toIntSafe(result['lastInsertId']);
      _lastAffectedRows = ar;
      _lastInsertedId = lid;
      _lastError = null;
      return (affectedRows: ar, lastInsertedId: lid);
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    }
  }

  /// Used by `DbasSqliteStatement.executeReader` on web.
  ///
  /// Routes through the worker's per-statement streaming RPC
  /// (`prepareQuery` / `bindParams` / `readRow` / `finalizeStmt`) so
  /// the result set is consumed one row at a time — matching the
  /// native FFI `executeReader` behaviour. No materialisation: a
  /// 10k-row SELECT issues 10k `readRow` round-trips, and a
  /// `LIMIT 1` SELECT (driven by `executeScalar`) issues exactly one.
  ///
  /// The web pool spawns a single writer worker that owns the only
  /// SQLite connection, so a SELECT issued mid-transaction observes
  /// the in-flight uncommitted writes — read-your-writes works
  /// automatically with no routing flag from the caller.
  ///
  /// On bind failure the orphan handle is finalised here; the caller
  /// never sees a [WebRowStream] in that path.
  Future<WebRowStream> executeStatementRead(
      String sql, dynamic params) async {
    await _ensurePool();
    final ({WebStmtHandle handle, int columnCount, List<String> columnNames})
        prep;
    try {
      prep = await _pool!.prepareQueryStream(sql);
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    }

    if (params != null) {
      try {
        await _pool!.bindParams(prep.handle, params);
      } catch (e) {
        // Bind failure: caller never gets the handle, so we own the
        // cleanup. The worker's `finalizeStmt` is idempotent and
        // tolerant of unknown handles — safe to call unconditionally.
        try {
          await _pool!.finalizeStmt(prep.handle);
        } catch (e2, st2) {
          developer.log(
            'executeStatementRead: cleanup finalize after bind failure failed',
            name: 'dbas_sqlite.DbasSqliteNativeWeb',
            error: e2,
            stackTrace: st2,
          );
        }
        _lastError = e.toString();
        rethrow;
      }
    }

    return WebRowStream(
      pool: _pool!,
      handle: prep.handle,
      columnCount: prep.columnCount,
      columnNames: prep.columnNames,
    );
  }

  // ── State accessors (last-write outcome from executeSql/Statement) ────

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

  // ── Per-stmt ABI (single-connection fallback path — not used) ─────────
  // The pool path uses executeStatementWrite/Read above. These exist
  // for ABI completeness but throw on call.

  // Helper for the unreachable per-stmt fallbacks below. Throwing
  // UnsupportedError surfaces a misuse loudly instead of returning a
  // success sentinel that masks the bug.
  Never _webStubUnreachable(String method) => throw UnsupportedError(
      'Web pool path does not use per-stmt $method — use '
      'executeStatementWrite/Read instead.');

  @override
  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(int dbPtr, String sql) => _webStubUnreachable('prepareQuery');
  @override
  Future<int> finalizeStmt(int dbPtr, int handle) =>
      _webStubUnreachable('finalizeStmt');
  @override
  Future<int> readRowAndCache(int dbPtr, int handle, RowData cache) =>
      _webStubUnreachable('readRowAndCache');

  // These three return cached "last-write outcome" state populated by
  // executeStatementWrite / executeSql — they are intentionally non-
  // throwing because callers may inspect them through the public stmt
  // API after a successful write.
  @override
  String? getLastStmtError(int dbPtr, int handle) => _lastError;
  @override
  int getStmtAffectedRows(int dbPtr, int handle) => _lastAffectedRows;
  @override
  int getStmtLastInsertedId(int dbPtr, int handle) => _lastInsertedId;

  // The web pool path doesn't use per-stmt binds — params are sent
  // as a list/map with the full SQL via pool.exec / pool.query.
  // Reaching any of these means a code path mistakenly routed a
  // prepared-statement bind through the platform interface on web;
  // surface that loudly rather than returning sqliteOk silently.
  @override
  Future<int> bindNull(int dbPtr, int handle, int index) =>
      _webStubUnreachable('bindNull');
  @override
  Future<int> bindInt(int dbPtr, int handle, int index, int value) =>
      _webStubUnreachable('bindInt');
  @override
  Future<int> bindInt64(int dbPtr, int handle, int index, int value) =>
      _webStubUnreachable('bindInt64');
  @override
  Future<int> bindFloat(int dbPtr, int handle, int index, double value) =>
      _webStubUnreachable('bindFloat');
  @override
  Future<int> bindDouble(int dbPtr, int handle, int index, double value) =>
      _webStubUnreachable('bindDouble');
  @override
  Future<int> bindText(int dbPtr, int handle, int index, String value) =>
      _webStubUnreachable('bindText');
  @override
  Future<int> bindBlob(int dbPtr, int handle, int index, List<int> value) =>
      _webStubUnreachable('bindBlob');
  @override
  Future<int> bindNameNull(int dbPtr, int handle, String name) =>
      _webStubUnreachable('bindNameNull');
  @override
  Future<int> bindNameInt(int dbPtr, int handle, String name, int value) =>
      _webStubUnreachable('bindNameInt');
  @override
  Future<int> bindNameInt64(int dbPtr, int handle, String name, int value) =>
      _webStubUnreachable('bindNameInt64');
  @override
  Future<int> bindNameFloat(int dbPtr, int handle, String name, double value) =>
      _webStubUnreachable('bindNameFloat');
  @override
  Future<int> bindNameDouble(int dbPtr, int handle, String name, double value) =>
      _webStubUnreachable('bindNameDouble');
  @override
  Future<int> bindNameText(int dbPtr, int handle, String name, String value) =>
      _webStubUnreachable('bindNameText');
  @override
  Future<int> bindNameBlob(int dbPtr, int handle, String name, List<int> value) =>
      _webStubUnreachable('bindNameBlob');

  // Per-handle column accessors — only reachable via the per-stmt path
  // which web does not use. Web reads stream through `WebRowStream`
  // (one `readRow` worker round-trip per row), and `DbasSqliteReader`
  // reads `ColumnData` from the stream's per-row cache directly
  // without going through the platform interface.
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

  // ── Connection Pool ───────────────────────────────────────────────────

  @override
  Future<int> createPool(String path, int readerCount) async {
    _pool = await DbasSqliteWebPool.create(dbName: dbName, readerCount: readerCount);
    _dbOpened = true;
    await _ensureSqliteVersion();
    return 1;
  }

  @override
  int poolGetWriter(int poolPtr) => 1;
  @override
  int poolAcquireReader(int poolPtr) => 0;
  @override
  Future<int> poolAcquireReaderBlocking(int poolPtr, int timeoutMs) async => 0;
  @override
  void poolReleaseReader(int poolPtr, int readerPtr) {}

  @override
  Future<void> closePool(int poolPtr) async {
    await _pool?.close();
    _pool = null;
    DbasSqliteWebPool.removePool(dbName);
    _dbOpened = false;
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

// ── SQLite return-code constants (re-exported from dbas_sqlite_db) ─────

const int sqliteOk = 0;
