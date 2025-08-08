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
  int openDb(String path) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  bool isOpened(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int executeSql(int dbPtr, String sql) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int prepareQuery(int dbPtr, String sql) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNull(int stmt, int index) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindInt(int stmt, int index, int value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindFloat(int stmt, int index, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindDouble(int stmt, int index, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindText(int stmt, int index, String value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindBlob(int stmt, int index, List<int> value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameNull(int stmt, String name) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameInt(int stmt, String name, int value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameFloat(int stmt, String name, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameDouble(int stmt, String name, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameText(int stmt, String name, String value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameBlob(int stmt, String name, List<int> value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int readRow(int stmt) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  bool isNull(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  String getColumnText(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnInt(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  double getColumnFloat(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  double getColumnDouble(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  List<int> getColumnBlob(int stmt, int columnIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnBytes(int stmt, int columnIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  String getColumnName(int stmt, int columnIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnType(int stmt, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnCount(int stmt) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  String getLastDbError(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getAffectedRows(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getLastInsertedId(int dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void closeReader(int stmt) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> closeDb(int dbPtr) async =>
      throw UnsupportedError('Not supported in native app.');
}