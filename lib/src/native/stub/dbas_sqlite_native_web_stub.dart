import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_interface.dart';

class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  DbasSqliteNativeWeb(super.dbName);

  @override
  Future<void> initialize() async =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> prepareLibIfNeeded() async =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<String> getLibraryPath() async =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<int> openDb(String path) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<bool> databaseExists(String fileName) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future attachDb(String fileName, List<int> content) =>
      throw UnsupportedError('Not supported in web.');

  @override
  bool isOpened(int dbPtr) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<int> executeSql(int dbPtr, String sql) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<int> prepareQuery(int dbPtr, String sql) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindNull(int stmt, int index) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindInt(int stmt, int index, int value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindFloat(int stmt, int index, double value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindDouble(int stmt, int index, double value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindText(int stmt, int index, String value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindBlob(int stmt, int index, List<int> value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindNameNull(int stmt, String name) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindNameInt(int stmt, String name, int value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindNameFloat(int stmt, String name, double value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindNameDouble(int stmt, String name, double value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindNameText(int stmt, String name, String value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  void bindNameBlob(int stmt, String name, List<int> value) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<int> readRow(int stmt) =>
      throw UnsupportedError('Not supported in web.');

  @override
  bool isNull(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  String getColumnText(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  int getColumnInt(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  double getColumnFloat(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  double getColumnDouble(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  List<int> getColumnBlob(int stmt, int columnIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  int getColumnBytes(int stmt, int columnIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  String getColumnName(int stmt, int columnIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  int getColumnType(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in web.');

  @override
  int getColumnCount(int stmt) =>
      throw UnsupportedError('Not supported in web.');

  @override
  String getLastDbError(int dbPtr) =>
      throw UnsupportedError('Not supported in web.');

  @override
  int getAffectedRows(int dbPtr) =>
      throw UnsupportedError('Not supported in web.');

  @override
  int getLastInsertedId(int dbPtr) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> closeReader(int stmt) =>
      throw UnsupportedError('Not supported in web.');

  @override
  Future<void> closeDb(int dbPtr) async =>
      throw UnsupportedError('Not supported in web.');
}
