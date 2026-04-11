import 'dart:async';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'dbas_sqlite_native_interface.dart';
import 'dbas_sqlite_web_pool.dart';
import 'dbas_sqlite_row_cache.dart';

/// Web implementation backed by a single Web Worker running the DBAS.SQLite
/// WASM module with an in-process WAL connection pool.
///
/// The cursor-based Dart API is adapted by buffering SQL + params during
/// `prepareQuery`/`bindXxx`, then issuing a single `exec` or `query` on the
/// first `readRow` call and caching all results.
class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  DbasSqliteWebPool? _pool;
  bool _initialized = false;
  bool _dbOpened = false;

  String? _pendingSql;
  final List<dynamic> _pendingPositionalParams = [];
  final Map<String, dynamic> _pendingNamedParams = {};
  bool _isWriteQuery = false;
  bool _nextPrepareIsWrite = false;
  WebQueryBuffer? _queryBuffer;

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
  Future<int> openDb(String path) async {
    _dbOpened = true;
    return 1;
  }

  @override
  Future<bool> databaseExists(String fileName) async {
    // Initialize a pool worker to check — init opens the DB via OPFS.
    // Infrastructure failures (worker load, OPFS unavailable) propagate
    // to the caller rather than being masked as "database not found".
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    final result = await pool.send('exists');
    return result == true;
  }

  @override
  bool isOpened(int dbPtr) => _dbOpened;

  @override
  Future<void> closeDb(int dbPtr) async {
    await _pool?.close();
    _pool = null;
    DbasSqliteWebPool.removePool(dbName);
    _dbOpened = false;
  }

  // ── File operations (via worker protocol) ─────────────────────────────

  @override
  Future attachDb(String fileName, List<int> content) async {
    // Close existing pool — OPFS handles must be released first
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
      DbasSqliteWebPool.removePool(dbName);
    }
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    // Use the chunked protocol (begin/chunk/end) — the worker closes
    // the DB before writing and reopens after.
    await pool.attachStreamChunked(
      Stream.fromIterable([content]),
      totalSize: content.length,
    );
    // Close and re-create so the next openDb starts fresh
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
    // True streaming — chunks flow from the Dart stream to the worker
    // one at a time via attachStreamBegin/Chunk/End. The full database
    // is never buffered in Dart memory.
    await pool.attachStreamChunked(stream);
    await pool.close();
    DbasSqliteWebPool.removePool(dbName);
  }

  @override
  Future<List<int>> getContent(String fileName) async {
    // Close pool to release OPFS handles, export via worker
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
      DbasSqliteWebPool.removePool(dbName);
      _dbOpened = false;
    }
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    // Streaming export — handles both Transferable Streams (Chrome/Firefox)
    // and chunked postMessage fallback (Safari) automatically.
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
    // Create a temporary worker to drop the DB files
    final pool = await DbasSqliteWebPool.create(dbName: dbName);
    await pool.drop();
    await pool.close();
    DbasSqliteWebPool.removePool(dbName);
    _dbOpened = false;
  }

  // ── SQL execution (direct, for BEGIN/COMMIT/ROLLBACK/PRAGMA) ──────────

  @override
  Future<int> executeSql(int dbPtr, String sql) async {
    await _ensurePool();
    final result = await _pool!.exec(sql);
    _lastAffectedRows = toIntSafe(result['affectedRows']);
    _lastInsertedId = toIntSafe(result['lastInsertId'] ?? result['lastInsertedId']);
    _lastError = null;
    return 0;
  }

  // ── Cursor-based query ────────────────────────────────────────────────

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async {
    _isWriteQuery = _nextPrepareIsWrite;
    _nextPrepareIsWrite = false;
    _pendingSql = sql;
    _pendingPositionalParams.clear();
    _pendingNamedParams.clear();
    _queryBuffer = null;
    _lastError = null;
    return 0;
  }

  // ── Parameter binding (buffered until readRow) ────────────────────────

  @override
  int bindNull(int dbPtr, int index) { _ensureSlots(index); _pendingPositionalParams[index - 1] = null; return 0; }
  @override
  int bindInt(int dbPtr, int index, int value) { _ensureSlots(index); _pendingPositionalParams[index - 1] = value; return 0; }
  @override
  int bindFloat(int dbPtr, int index, double value) { _ensureSlots(index); _pendingPositionalParams[index - 1] = value; return 0; }
  @override
  int bindDouble(int dbPtr, int index, double value) { _ensureSlots(index); _pendingPositionalParams[index - 1] = value; return 0; }
  @override
  int bindText(int dbPtr, int index, String value) { _ensureSlots(index); _pendingPositionalParams[index - 1] = value; return 0; }
  @override
  int bindBlob(int dbPtr, int index, List<int> value) { _ensureSlots(index); _pendingPositionalParams[index - 1] = value; return 0; }

  @override
  int bindNameNull(int dbPtr, String name) { _pendingNamedParams[name] = null; return 0; }
  @override
  int bindNameInt(int dbPtr, String name, int value) { _pendingNamedParams[name] = value; return 0; }
  @override
  int bindNameFloat(int dbPtr, String name, double value) { _pendingNamedParams[name] = value; return 0; }
  @override
  int bindNameDouble(int dbPtr, String name, double value) { _pendingNamedParams[name] = value; return 0; }
  @override
  int bindNameText(int dbPtr, String name, String value) { _pendingNamedParams[name] = value; return 0; }
  @override
  int bindNameBlob(int dbPtr, String name, List<int> value) { _pendingNamedParams[name] = value; return 0; }

  void _ensureSlots(int index) {
    while (_pendingPositionalParams.length < index) {
      _pendingPositionalParams.add(null);
    }
  }

  // ── Row reading ───────────────────────────────────────────────────────

  @override
  Future<int> readRow(int dbPtr) async {
    await _ensurePool();
    const sqliteRow = 100;
    const sqliteDone = 101;

    if (_queryBuffer != null) {
      return _queryBuffer!.moveNext() ? sqliteRow : sqliteDone;
    }

    if (_pendingSql == null) return sqliteDone;
    final sql = _pendingSql!;
    final params = _buildParams();

    try {
      if (_isWriteQuery) {
        final result = await _pool!.exec(sql, params);
        _lastAffectedRows = toIntSafe(result['affectedRows']);
        _lastInsertedId = toIntSafe(result['lastInsertId'] ?? result['lastInsertedId']);
        _lastError = null;
        _queryBuffer = WebQueryBuffer([]);
        return sqliteDone;
      } else {
        final rows = await _pool!.query(sql, params);
        _queryBuffer = WebQueryBuffer(rows);
        return _queryBuffer!.moveNext() ? sqliteRow : sqliteDone;
      }
    } catch (e) {
      _lastError = e.toString();
      _queryBuffer = WebQueryBuffer([]);
      return -1;
    }
  }

  dynamic _buildParams() {
    if (_pendingPositionalParams.isNotEmpty) return _pendingPositionalParams;
    if (_pendingNamedParams.isNotEmpty) return _pendingNamedParams;
    return null;
  }

  // ── Column accessors ──────────────────────────────────────────────────

  @override
  bool isNull(int dbPtr, int colIndex) => _queryBuffer?.getColumnData(colIndex).isNull ?? true;
  @override
  String getColumnText(int dbPtr, int colIndex) => _queryBuffer?.getColumnData(colIndex).value?.toString() ?? '';
  @override
  int getColumnInt(int dbPtr, int colIndex) => toIntSafe(_queryBuffer?.getColumnData(colIndex).value);
  @override
  double getColumnFloat(int dbPtr, int colIndex) => toDoubleSafe(_queryBuffer?.getColumnData(colIndex).value);
  @override
  double getColumnDouble(int dbPtr, int colIndex) => toDoubleSafe(_queryBuffer?.getColumnData(colIndex).value);
  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) {
    final value = _queryBuffer?.getColumnData(columnIndex).value;
    if (value is List) return value.cast<num>().map((e) => e.toInt()).toList();
    return [];
  }
  @override
  int getColumnBytes(int dbPtr, int columnIndex) => getColumnBlob(dbPtr, columnIndex).length;
  @override
  String getColumnName(int dbPtr, int colIndex) {
    if (_queryBuffer == null || colIndex >= _queryBuffer!.columnNames.length) return '';
    return _queryBuffer!.columnNames[colIndex];
  }
  @override
  int getColumnType(int dbPtr, int colIndex) => _queryBuffer?.getColumnData(colIndex).type ?? 5;
  @override
  int getColumnCount(int dbPtr) => _queryBuffer?.columnCount ?? 0;

  // ── State accessors ───────────────────────────────────────────────────

  @override
  String? getLastDbError(int dbPtr) => _lastError;
  @override
  int getAffectedRows(int dbPtr) => _lastAffectedRows;
  @override
  int getLastInsertedId(int dbPtr) => _lastInsertedId;

  // ── Reader management ─────────────────────────────────────────────────

  @override
  Future closeReader(int dbPtr) async {
    _queryBuffer = null;
    _pendingSql = null;
    _pendingPositionalParams.clear();
    _pendingNamedParams.clear();
  }

  // ── Connection Pool ───────────────────────────────────────────────────

  @override
  Future<int> createPool(String path, int readerCount) async {
    _pool = await DbasSqliteWebPool.create(dbName: dbName, readerCount: readerCount);
    _dbOpened = true;
    return 1;
  }

  @override
  int poolGetWriter(int poolPtr) => 1;
  @override
  int poolAcquireReader(int poolPtr) => 0;
  @override
  void poolReleaseReader(int poolPtr, int readerPtr) {}

  @override
  Future<void> closePool(int poolPtr) async {
    await _pool?.close();
    _pool = null;
    DbasSqliteWebPool.removePool(dbName);
    _dbOpened = false;
  }

  // ── Transaction lease (no-op: single worker serializes naturally) ─────

  @override
  Future<void> beginTransactionLease() async {}
  @override
  Future<void> endTransactionLease() async {}
  @override
  void setWriteMode() { _nextPrepareIsWrite = true; }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<void> _ensurePool() async {
    _pool ??= await DbasSqliteWebPool.create(
      dbName: dbName,
      readerCount: DbasSqliteNativeInterface.workerPoolSize,
    );
  }
}
