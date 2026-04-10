import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_interface.dart';

class DbasSqliteNativeApp extends DbasSqliteNativeInterface {
  DbasSqliteNativeApp(super.dbName);

  @override
  Future<void> initialize() async =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> prepareLibIfNeeded() async =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<String> getLibraryPath() async =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<int> openDb(String path) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  bool isOpened(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<bool> databaseExists(String fileName) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future attachDb(String fileName, List<int> content) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future attachStreamDb(String fileName, Stream<List<int>> stream) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<List<int>> getContent(String fileName) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> streamCopyDb(String sourceFileName, String destFileName) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> dropDb(String fileName) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<int> executeSql(int dbPtr, String sql) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<int> prepareQuery(int dbPtr, String sql) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindNull(int dbPtr, int index) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindInt(int dbPtr, int index, int value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindFloat(int dbPtr, int index, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindDouble(int dbPtr, int index, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindText(int dbPtr, int index, String value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindBlob(int dbPtr, int index, List<int> value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindNameNull(int dbPtr, String name) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindNameInt(int dbPtr, String name, int value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindNameFloat(int dbPtr, String name, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindNameDouble(int dbPtr, String name, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindNameText(int dbPtr, String name, String value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int bindNameBlob(int dbPtr, String name, List<int> value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<int> readRow(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  bool isNull(int dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  String getColumnText(int dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnInt(int dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  double getColumnFloat(int dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  double getColumnDouble(int dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnBytes(int dbPtr, int columnIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  String getColumnName(int dbPtr, int columnIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnType(int dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnCount(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  String? getLastDbError(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getAffectedRows(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getLastInsertedId(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> closeReader(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> closeDb(int dbPtr) async =>
      throw UnsupportedError('Not supported in native app.');

  // ── Connection Pool ──
  @override
  Future<int> createPool(String path, int readerCount) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int poolGetWriter(int poolPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int poolAcquireReader(int poolPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void poolReleaseReader(int poolPtr, int readerPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> closePool(int poolPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> beginTransactionLease() =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> endTransactionLease() =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void setWriteMode() =>
      throw UnsupportedError('Not supported in native app.');
}
