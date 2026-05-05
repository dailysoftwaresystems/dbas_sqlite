import 'dart:async';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'dbas_sqlite_native_interface.dart';
import 'dbas_sqlite_web_pool.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_row_cache.dart';

/// Web implementation backed by the JS pool wrapper
/// (`web/libs/dbas_sqlite.js` + `dbas_sqlite_worker.js`). The Dart side
/// dispatches `pool.exec` for writes and `pool.query` for reads via the
/// new `executeStatementWrite` / `executeStatementRead` entry points
/// (called from `DbasSqliteStatement`). Per-stmt ABI calls (prepare /
/// bind / readRow / finalize) are not used on the pool path — the JS
/// pool runs SQL atomically per `pool.exec` / `pool.query` round-trip.
///
/// The single-connection fallback path (when the JS pool fails to
/// initialise) is not implemented in v2.4.0; consumers requiring it
/// will get an `UnsupportedError` from the per-stmt entry points.
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
    } catch (e) {
      // Best-effort — keep the empty string if the query fails.
      _lastError = 'getSqliteVersion via pool.query failed: $e';
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
  /// Outside a transaction: routes through `pool.query` (reader
  /// worker pool, SHARED MRSW fence) — works for any SELECT.
  ///
  /// Inside a transaction: tries `pool.exec` (writer worker,
  /// EXCLUSIVE MRSW fence) — necessary for read-your-own-writes
  /// because reader workers run on separate connections that don't
  /// see the writer's BEGIN-bracketed state. The current bundled JS
  /// (`dbas_sqlite_worker.js` v4.3.6) does NOT return rows for SELECT
  /// through `pool.exec`. When the rows aren't returned this path
  /// throws [UnsupportedError] with a clear migration message — never
  /// returns silently-empty.
  Future<WebQueryBuffer> executeStatementRead(
      String sql, dynamic params, {required bool inTransaction}) async {
    await _ensurePool();
    try {
      if (inTransaction) {
        final result = await _pool!.exec(sql, params);
        final rows = result['rows'];
        if (rows is List) {
          // Future-compatible path: when the JS wrapper supports
          // SELECT-via-exec, the rows arrive here in flat-dict form.
          return WebQueryBuffer(
              rows.map((r) => Map<String, dynamic>.from(r as Map)).toList());
        }
        // Current behaviour: no rows came back. Don't pretend the
        // result set is empty — surface the limitation loudly.
        _lastAffectedRows = toIntSafe(result['affectedRows']);
        _lastInsertedId = toIntSafe(result['lastInsertId']);
        throw UnsupportedError(
          'executeReader inside a transaction is not supported on web '
          '(the bundled JS worker v4.3.6 cannot return SELECT rows '
          'through pool.exec, which is the only path that observes '
          'in-flight transactional state). Run the SELECT outside the '
          'transaction, or restructure the code to read first.',
        );
      } else {
        final rows = await _pool!.query(sql, params);
        return WebQueryBuffer(rows);
      }
    } catch (e) {
      // Don't capture UnsupportedError into _lastError — it's a
      // structural limitation, not a SQL error.
      if (e is! UnsupportedError) {
        _lastError = e.toString();
      }
      rethrow;
    }
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

  @override
  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(int dbPtr, String sql) => throw UnsupportedError(
          'Web pool path does not use per-stmt prepareQuery — use executeStatementWrite/Read');
  @override
  Future<int> finalizeStmt(int dbPtr, int handle) async => sqliteOk;
  @override
  Future<int> readRowAndCache(int dbPtr, int handle, RowData cache) =>
      throw UnsupportedError('Web pool path does not use per-stmt readRowAndCache');
  @override
  String? getLastStmtError(int dbPtr, int handle) => _lastError;
  @override
  int getStmtAffectedRows(int dbPtr, int handle) => _lastAffectedRows;
  @override
  int getStmtLastInsertedId(int dbPtr, int handle) => _lastInsertedId;

  // The web pool path doesn't use per-stmt binds — params are sent
  // as a list/map with the full SQL via pool.exec / pool.query.
  // These methods are unreachable on the pool path and exist only to
  // satisfy the abstract interface.
  @override
  Future<int> bindNull(int dbPtr, int handle, int index) async => sqliteOk;
  @override
  Future<int> bindInt(int dbPtr, int handle, int index, int value) async => sqliteOk;
  @override
  Future<int> bindInt64(int dbPtr, int handle, int index, int value) async => sqliteOk;
  @override
  Future<int> bindFloat(int dbPtr, int handle, int index, double value) async => sqliteOk;
  @override
  Future<int> bindDouble(int dbPtr, int handle, int index, double value) async => sqliteOk;
  @override
  Future<int> bindText(int dbPtr, int handle, int index, String value) async => sqliteOk;
  @override
  Future<int> bindBlob(int dbPtr, int handle, int index, List<int> value) async => sqliteOk;
  @override
  Future<int> bindNameNull(int dbPtr, int handle, String name) async => sqliteOk;
  @override
  Future<int> bindNameInt(int dbPtr, int handle, String name, int value) async => sqliteOk;
  @override
  Future<int> bindNameInt64(int dbPtr, int handle, String name, int value) async => sqliteOk;
  @override
  Future<int> bindNameFloat(int dbPtr, int handle, String name, double value) async => sqliteOk;
  @override
  Future<int> bindNameDouble(int dbPtr, int handle, String name, double value) async => sqliteOk;
  @override
  Future<int> bindNameText(int dbPtr, int handle, String name, String value) async => sqliteOk;
  @override
  Future<int> bindNameBlob(int dbPtr, int handle, String name, List<int> value) async => sqliteOk;

  @override
  bool isNull(int dbPtr, int handle, int colIndex) => false;
  @override
  String getColumnText(int dbPtr, int handle, int colIndex) => '';
  @override
  int getColumnInt(int dbPtr, int handle, int colIndex) => 0;
  @override
  int getColumnInt64(int dbPtr, int handle, int colIndex) => 0;
  @override
  double getColumnFloat(int dbPtr, int handle, int colIndex) => 0;
  @override
  double getColumnDouble(int dbPtr, int handle, int colIndex) => 0;
  @override
  List<int> getColumnBlob(int dbPtr, int handle, int columnIndex) => const [];
  @override
  int getColumnBytes(int dbPtr, int handle, int columnIndex) => 0;
  @override
  String getColumnName(int dbPtr, int handle, int columnIndex) => '';
  @override
  int getColumnType(int dbPtr, int handle, int colIndex) => 5;
  @override
  int getColumnCount(int dbPtr, int handle) => 0;

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
