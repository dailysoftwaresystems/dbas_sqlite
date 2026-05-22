import 'package:dbas_sqlite/src/native/dbas_sqlite_native_interface.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';

/// Stub used on non-web platforms — the conditional import in
/// `dbas_sqlite_native_interface.dart` swaps the real
/// `DbasSqliteNativeWeb` in when `dart.library.js_interop` is
/// available. The class name MUST stay identical for the conditional
/// import to type-check on the IO side.
class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  DbasSqliteNativeWeb(super.dbName);

  static const _msg = 'Not supported on web stub.';

  @override
  Future<void> initialize() => throw UnsupportedError(_msg);

  @override
  String getSqliteVersion() => throw UnsupportedError(_msg);
  @override
  int getAbiVersion() => throw UnsupportedError(_msg);

  @override
  Future<int> openDb(String path) => throw UnsupportedError(_msg);
  @override
  bool isOpened(int dbPtr) => throw UnsupportedError(_msg);
  @override
  Future<bool> databaseExists(String fileName) => throw UnsupportedError(_msg);
  @override
  Future attachDb(String fileName, List<int> content) =>
      throw UnsupportedError(_msg);
  @override
  Future attachStreamDb(String fileName, Stream<List<int>> stream) =>
      throw UnsupportedError(_msg);
  @override
  Future<List<int>> getContent(String fileName) =>
      throw UnsupportedError(_msg);
  @override
  Future<void> streamCopyDb(String src, String dest) =>
      throw UnsupportedError(_msg);
  @override
  Future<void> dropDb(String fileName) => throw UnsupportedError(_msg);

  @override
  Future<int> executeSql(int dbPtr, String sql) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> closeDb(int dbPtr, {bool checkpoint = false}) =>
      throw UnsupportedError(_msg);

  @override
  String? getLastDbError(int dbPtr) => throw UnsupportedError(_msg);
  @override
  int? getErrorCode(int dbPtr) => throw UnsupportedError(_msg);
  @override
  int? getUniqueErrorCode(int dbPtr) => throw UnsupportedError(_msg);
  @override
  int getAffectedRows(int dbPtr) => throw UnsupportedError(_msg);
  @override
  int getLastInsertedId(int dbPtr) => throw UnsupportedError(_msg);
  @override
  int getTotalChanges(int dbPtr) => throw UnsupportedError(_msg);
  @override
  String? getDbFileName(int dbPtr) => throw UnsupportedError(_msg);
  @override
  Future<int> setBusyTimeout(int dbPtr, int ms) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> enableWal(int dbPtr) => throw UnsupportedError(_msg);

  @override
  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(int dbPtr, String sql) =>
          throw UnsupportedError(_msg);
  @override
  Future<int> finalizeStmt(int dbPtr, int handle) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> readRowAndCache(int dbPtr, int handle, RowData cache) =>
      throw UnsupportedError(_msg);
  @override
  String? getLastStmtError(int dbPtr, int handle) =>
      throw UnsupportedError(_msg);
  @override
  int getStmtAffectedRows(int dbPtr, int handle) =>
      throw UnsupportedError(_msg);
  @override
  int getStmtLastInsertedId(int dbPtr, int handle) =>
      throw UnsupportedError(_msg);

  @override
  Future<int> bindNull(int dbPtr, int handle, int index) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindInt(int dbPtr, int handle, int index, int value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindInt64(int dbPtr, int handle, int index, int value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindFloat(int dbPtr, int handle, int index, double value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindDouble(int dbPtr, int handle, int index, double value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindText(int dbPtr, int handle, int index, String value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindBlob(int dbPtr, int handle, int index, List<int> value) =>
      throw UnsupportedError(_msg);

  @override
  Future<int> bindNameNull(int dbPtr, int handle, String name) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindNameInt(int dbPtr, int handle, String name, int value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindNameInt64(int dbPtr, int handle, String name, int value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindNameFloat(int dbPtr, int handle, String name, double value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindNameDouble(int dbPtr, int handle, String name, double value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindNameText(int dbPtr, int handle, String name, String value) =>
      throw UnsupportedError(_msg);
  @override
  Future<int> bindNameBlob(int dbPtr, int handle, String name, List<int> value) =>
      throw UnsupportedError(_msg);

  @override
  bool isNull(int dbPtr, int handle, int colIndex) =>
      throw UnsupportedError(_msg);
  @override
  String getColumnText(int dbPtr, int handle, int colIndex) =>
      throw UnsupportedError(_msg);
  @override
  int getColumnInt(int dbPtr, int handle, int colIndex) =>
      throw UnsupportedError(_msg);
  @override
  int getColumnInt64(int dbPtr, int handle, int colIndex) =>
      throw UnsupportedError(_msg);
  @override
  double getColumnFloat(int dbPtr, int handle, int colIndex) =>
      throw UnsupportedError(_msg);
  @override
  double getColumnDouble(int dbPtr, int handle, int colIndex) =>
      throw UnsupportedError(_msg);
  @override
  List<int> getColumnBlob(int dbPtr, int handle, int columnIndex) =>
      throw UnsupportedError(_msg);
  @override
  int getColumnBytes(int dbPtr, int handle, int columnIndex) =>
      throw UnsupportedError(_msg);
  @override
  String getColumnName(int dbPtr, int handle, int columnIndex) =>
      throw UnsupportedError(_msg);
  @override
  int getColumnType(int dbPtr, int handle, int colIndex) =>
      throw UnsupportedError(_msg);
  @override
  int getColumnCount(int dbPtr, int handle) => throw UnsupportedError(_msg);

  @override
  Future<int> createPool(String path, int readerCount) =>
      throw UnsupportedError(_msg);
  @override
  int poolGetWriter(int poolPtr) => throw UnsupportedError(_msg);
  @override
  int poolAcquireReader(int poolPtr) => throw UnsupportedError(_msg);
  @override
  Future<int> poolAcquireReaderBlocking(int poolPtr, int timeoutMs) =>
      throw UnsupportedError(_msg);
  @override
  void poolReleaseReader(int poolPtr, int readerPtr) =>
      throw UnsupportedError(_msg);
  @override
  Future<void> closePool(int poolPtr) => throw UnsupportedError(_msg);
}
