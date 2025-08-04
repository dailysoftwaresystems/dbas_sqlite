import 'dart:js_interop';
import 'dbas_sqlite_native_interface.dart';

@JS('initDbasSqlite')
external Object _initDbasSqlite();

@JS('DbasSqlite')
external DbasSqliteNativeWebJS get _dbasSqliteNativeWebJS;

@JS()
@staticInterop
class DbasSqliteNativeWebJS {
  external factory DbasSqliteNativeWebJS();
}

extension DbasSqliteNativeWebJSExtension on DbasSqliteNativeWebJS {
  external int openDb(String path);
  external bool isOpened(int dbPtr);
  external int executeSql(int dbPtr, String sql);
  external int prepareQuery(int dbPtr, String sql);

  external void bindNull(int stmt, int index);
  external void bindInt(int stmt, int index, int value);
  external void bindFloat(int stmt, int index, double value);
  external void bindDouble(int stmt, int index, double value);
  external void bindText(int stmt, int index, String value);
  external void bindBlob(int stmt, int index, List<int> value);

  external void bindNameNull(int stmt, String name);
  external void bindNameInt(int stmt, String name, int value);
  external void bindNameFloat(int stmt, String name, double value);
  external void bindNameDouble(int stmt, String name, double value);
  external void bindNameText(int stmt, String name, String value);
  external void bindNameBlob(int stmt, String name, List<int> value);

  external int readRow(int stmt);
  external int isNull(int stmt, int colIndex);

  external String getColumnText(int stmt, int colIndex);
  external int getColumnInt(int stmt, int colIndex);
  external double getColumnFloat(int stmt, int colIndex);
  external double getColumnDouble(int stmt, int colIndex);
  external List<int> getColumnBlob(int stmt, int columnIndex);
  external int getColumnBytes(int stmt, int columnIndex);
  external int getColumnType(int stmt, int colIndex);
  external int getColumnCount(int stmt);

  external String getLastDbError(int dbPtr);
  external int getAffectedRows(int dbPtr);
  external int getLastInsertedId(int dbPtr);

  external void closeReader(int stmt);
  external void closeDb(int dbPtr);
}

class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  late final DbasSqliteNativeWebJS _js;

  @override
  Future<void> initialize() async {
    final result = _initDbasSqlite();
    if (result is Future) await result;
    _js = _dbasSqliteNativeWebJS;
  }

  @override
  int openDb(String path) => _js.openDb(path);

  @override
  bool isOpened(int dbPtr) => _js.isOpened(dbPtr);

  @override
  int executeSql(int dbPtr, String sql) => _js.executeSql(dbPtr, sql);

  @override
  int prepareQuery(int dbPtr, String sql) => _js.prepareQuery(dbPtr, sql);

  @override
  void bindNull(int stmt, int index) => _js.bindNull(stmt, index);

  @override
  void bindInt(int stmt, int index, int value) => _js.bindInt(stmt, index, value);

  @override
  void bindFloat(int stmt, int index, double value) => _js.bindFloat(stmt, index, value);

  @override
  void bindDouble(int stmt, int index, double value) => _js.bindDouble(stmt, index, value);

  @override
  void bindText(int stmt, int index, String value) => _js.bindText(stmt, index, value);

  @override
  void bindBlob(int stmt, int index, List<int> value) {
    _js.bindBlob(stmt, index, value);
  }

  @override
  void bindNameNull(int stmt, String name) => _js.bindNameNull(stmt, name);

  @override
  void bindNameInt(int stmt, String name, int value) => _js.bindNameInt(stmt, name, value);

  @override
  void bindNameFloat(int stmt, String name, double value) => _js.bindNameFloat(stmt, name, value);

  @override
  void bindNameDouble(int stmt, String name, double value) => _js.bindNameDouble(stmt, name, value);

  @override
  void bindNameText(int stmt, String name, String value) => _js.bindNameText(stmt, name, value);

  @override
  void bindNameBlob(int stmt, String name, List<int> value) {
    _js.bindNameBlob(stmt, name, value);
  }

  @override
  int readRow(int stmt) => _js.readRow(stmt);

  @override
  bool isNull(int stmt, int colIndex) => _js.isNull(stmt, colIndex) == 1;

  @override
  String getColumnText(int stmt, int colIndex) => _js.getColumnText(stmt, colIndex);

  @override
  int getColumnInt(int stmt, int colIndex) => _js.getColumnInt(stmt, colIndex);

  @override
  double getColumnFloat(int stmt, int colIndex) => _js.getColumnFloat(stmt, colIndex);

  @override
  double getColumnDouble(int stmt, int colIndex) => _js.getColumnDouble(stmt, colIndex);

  @override
  List<int> getColumnBlob(int stmt, int columnIndex) {
    return _js.getColumnBlob(stmt, columnIndex);
  }

  @override
  int getColumnBytes(int stmt, int columnIndex) => _js.getColumnBytes(stmt, columnIndex);

  @override
  int getColumnType(int stmt, int colIndex) => _js.getColumnType(stmt, colIndex);

  @override
  int getColumnCount(int stmt) => _js.getColumnCount(stmt);

  @override
  String getLastDbError(int dbPtr) => _js.getLastDbError(dbPtr);

  @override
  int getAffectedRows(int dbPtr) => _js.getAffectedRows(dbPtr);

  @override
  int getLastInsertedId(int dbPtr) => _js.getLastInsertedId(dbPtr);

  @override
  void closeReader(int stmt) => _js.closeReader(stmt);

  @override
  Future<void> closeDb(int dbPtr) async => _js.closeDb(dbPtr);
}
