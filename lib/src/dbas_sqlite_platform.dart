import 'package:dbas_sqlite/src/native/dbas_sqlite_native_interface.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_db.dart'
    if (dart.library.js_interop) 'package:dbas_sqlite/src/stub/dbas_sqlite_db_stub.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';

/// Platform dispatcher — routes per-call work to the
/// per-`dbName` [DbasSqliteNativeInterface] delegate. Stateless: every
/// call unwraps the [DbasSqliteDb] handle to (name, ptr) and forwards.
final class DbasSqlitePlatform {
  static DbasSqlitePlatform? _instance;
  static final Map<String, DbasSqliteNativeInterface> _delegate = {};

  DbasSqlitePlatform._dbasSqlitePlatform();

  static Future<DbasSqlitePlatform> getInstance({String dbName = 'dbas.db'}) async {
    _getInterface(dbName: dbName);
    _instance ??= DbasSqlitePlatform._dbasSqlitePlatform();
    await _instance!.initialize(dbName);
    return _instance!;
  }

  static DbasSqliteNativeInterface _getInterface({String dbName = 'dbas.db'}) {
    if (!_delegate.containsKey(dbName)) {
      _delegate[dbName] = DbasSqliteNativeInterface.getInstance(dbName: dbName);
    }
    return _delegate[dbName]!;
  }

  Future<void> initialize(String name) async => await _delegate[name]!.initialize();

  /// Direct access to the underlying delegate (for the web statement
  /// path that needs to call `executeStatementWrite` /
  /// `executeStatementRead` — not on the abstract interface).
  DbasSqliteNativeInterface delegate(String dbName) => _delegate[dbName]!;

  // ── Library-scoped ───────────────────────────────────────────────────

  String getSqliteVersion(String dbName) =>
      _delegate[dbName]!.getSqliteVersion();
  int getAbiVersion(String dbName) => _delegate[dbName]!.getAbiVersion();

  // ── Connection lifecycle ─────────────────────────────────────────────

  Future<DbasSqliteDb> openDb(String fileName) async {
    final dbName = _getDbName(fileName);
    final dbPtr = await _getInterface(dbName: dbName).openDb(fileName);
    final isOpened = _delegate[dbName]!.isOpened(dbPtr);
    final lastError = isOpened ? null : _delegate[dbName]!.getLastDbError(dbPtr);
    if (dbPtr == 0 || !isOpened) {
      final msg = (lastError != null && lastError.isNotEmpty) ? lastError : 'Unknown error';
      throw Exception('Failed to open db in: $fileName. Reason: $msg');
    }
    return DbasSqliteDb(dbName, dbPtr);
  }

  bool isOpened(DbasSqliteDb db) => _delegate[db.name]!.isOpened(db.ptr);

  Future<int> closeDb(DbasSqliteDb db, {bool checkpoint = false}) async =>
      await _delegate[db.name]!.closeDb(db.ptr, checkpoint: checkpoint);

  // ── File operations ──────────────────────────────────────────────────

  Future<bool> databaseExists(String fileName) async {
    final dbName = _getDbName(fileName);
    return await _delegate[dbName]!.databaseExists(fileName);
  }

  Future attachDb(String fileName, List<int> content) async {
    final dbName = _getDbName(fileName);
    await _delegate[dbName]!.attachDb(fileName, content);
  }

  Future attachStreamDb(String fileName, Stream<List<int>> stream) async {
    final dbName = _getDbName(fileName);
    await _delegate[dbName]!.attachStreamDb(fileName, stream);
  }

  Future<List<int>> getContent(String fileName) async {
    final dbName = _getDbName(fileName);
    return await _delegate[dbName]!.getContent(fileName);
  }

  Future<void> streamCopyDb(String src, String dest) async {
    final dbName = _getDbName(src);
    await _delegate[dbName]!.streamCopyDb(src, dest);
  }

  Future dropDb(String fileName) async {
    final dbName = _getDbName(fileName);
    await _delegate[dbName]!.dropDb(fileName);
    _delegate.remove(dbName);
    DbasSqliteNativeInterface.removeInstance(dbName: dbName);
  }

  // ── One-shot SQL (DDL/DML, transaction primitives) ───────────────────

  Future<int> executeSql(DbasSqliteDb db, String sql) async =>
      await _delegate[db.name]!.executeSql(db.ptr, sql);

  // ── Statement (handle-aware) ─────────────────────────────────────────

  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(DbasSqliteDb db, String sql) async =>
          await _delegate[db.name]!.prepareQuery(db.ptr, sql);

  Future<int> finalizeStmt(DbasSqliteDb db, int handle) async =>
      await _delegate[db.name]!.finalizeStmt(db.ptr, handle);

  Future<int> readRowAndCache(DbasSqliteDb db, int handle, RowData cache) async =>
      await _delegate[db.name]!.readRowAndCache(db.ptr, handle, cache);

  String? getLastStmtError(DbasSqliteDb db, int handle) =>
      _delegate[db.name]!.getLastStmtError(db.ptr, handle);

  int getStmtAffectedRows(DbasSqliteDb db, int handle) =>
      _delegate[db.name]!.getStmtAffectedRows(db.ptr, handle);

  int getStmtLastInsertedId(DbasSqliteDb db, int handle) =>
      _delegate[db.name]!.getStmtLastInsertedId(db.ptr, handle);

  // ── Bindings (positional, async) ─────────────────────────────────────

  Future<int> bindNull(DbasSqliteDb db, int handle, int index) =>
      _delegate[db.name]!.bindNull(db.ptr, handle, index);
  Future<int> bindInt(DbasSqliteDb db, int handle, int index, int value) =>
      _delegate[db.name]!.bindInt(db.ptr, handle, index, value);
  Future<int> bindInt64(DbasSqliteDb db, int handle, int index, int value) =>
      _delegate[db.name]!.bindInt64(db.ptr, handle, index, value);
  Future<int> bindFloat(DbasSqliteDb db, int handle, int index, double value) =>
      _delegate[db.name]!.bindFloat(db.ptr, handle, index, value);
  Future<int> bindDouble(DbasSqliteDb db, int handle, int index, double value) =>
      _delegate[db.name]!.bindDouble(db.ptr, handle, index, value);
  Future<int> bindText(DbasSqliteDb db, int handle, int index, String value) =>
      _delegate[db.name]!.bindText(db.ptr, handle, index, value);
  Future<int> bindBlob(DbasSqliteDb db, int handle, int index, List<int> value) =>
      _delegate[db.name]!.bindBlob(db.ptr, handle, index, value);

  // ── Bindings (named, async) ──────────────────────────────────────────

  Future<int> bindNameNull(DbasSqliteDb db, int handle, String name) =>
      _delegate[db.name]!.bindNameNull(db.ptr, handle, name);
  Future<int> bindNameInt(DbasSqliteDb db, int handle, String name, int value) =>
      _delegate[db.name]!.bindNameInt(db.ptr, handle, name, value);
  Future<int> bindNameInt64(DbasSqliteDb db, int handle, String name, int value) =>
      _delegate[db.name]!.bindNameInt64(db.ptr, handle, name, value);
  Future<int> bindNameFloat(DbasSqliteDb db, int handle, String name, double value) =>
      _delegate[db.name]!.bindNameFloat(db.ptr, handle, name, value);
  Future<int> bindNameDouble(DbasSqliteDb db, int handle, String name, double value) =>
      _delegate[db.name]!.bindNameDouble(db.ptr, handle, name, value);
  Future<int> bindNameText(DbasSqliteDb db, int handle, String name, String value) =>
      _delegate[db.name]!.bindNameText(db.ptr, handle, name, value);
  Future<int> bindNameBlob(DbasSqliteDb db, int handle, String name, List<int> value) =>
      _delegate[db.name]!.bindNameBlob(db.ptr, handle, name, value);

  // ── Connection state accessors ───────────────────────────────────────

  String? getLastDbError(DbasSqliteDb db) =>
      _delegate[db.name]!.getLastDbError(db.ptr);

  int getAffectedRows(DbasSqliteDb db) =>
      _delegate[db.name]!.getAffectedRows(db.ptr);

  int getLastInsertedId(DbasSqliteDb db) =>
      _delegate[db.name]!.getLastInsertedId(db.ptr);

  int getTotalChanges(DbasSqliteDb db) =>
      _delegate[db.name]!.getTotalChanges(db.ptr);

  String? getDbFileName(DbasSqliteDb db) =>
      _delegate[db.name]!.getDbFileName(db.ptr);

  Future<int> setBusyTimeout(DbasSqliteDb db, int ms) async =>
      await _delegate[db.name]!.setBusyTimeout(db.ptr, ms);

  Future<int> enableWal(DbasSqliteDb db) async =>
      await _delegate[db.name]!.enableWal(db.ptr);

  // ── Connection Pool ──────────────────────────────────────────────────

  Future<int> createPool(String dbName, String fileName, int readerCount) async {
    final delegate = _getInterface(dbName: dbName);
    await delegate.initialize();
    return await delegate.createPool(fileName, readerCount);
  }

  int poolGetWriter(String dbName, int poolPtr) =>
      _delegate[dbName]!.poolGetWriter(poolPtr);

  int poolAcquireReader(String dbName, int poolPtr) =>
      _delegate[dbName]!.poolAcquireReader(poolPtr);

  Future<int> poolAcquireReaderBlocking(
          String dbName, int poolPtr, int timeoutMs) async =>
      await _delegate[dbName]!.poolAcquireReaderBlocking(poolPtr, timeoutMs);

  void poolReleaseReader(String dbName, int poolPtr, int readerPtr) =>
      _delegate[dbName]!.poolReleaseReader(poolPtr, readerPtr);

  Future<void> closePool(String dbName, int poolPtr) async {
    await _delegate[dbName]!.closePool(poolPtr);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  String _getDbName(String fileName) {
    String dbName = fileName;
    if (fileName.contains('/')) {
      dbName = fileName.split('/').last;
    } else if (fileName.contains('\\')) {
      dbName = fileName.split('\\').last;
    }
    return dbName;
  }
}
