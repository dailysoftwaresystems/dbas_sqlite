@JS()
library;

import 'dart:ffi';
import 'dart:typed_data';
import 'dart:js_interop';
import 'dbas_sqlite_db.dart';

@JS('initDbasSqlite')
external Object _initDbasSqlite();

@JS('DbasSqlite')
external DbasSqliteNativeWeb get dbasSqliteNativeWeb;

@JS()
@staticInterop
class DbasSqliteNativeWeb {
  external factory DbasSqliteNativeWeb();

  Future<void> initialize() async {
    final result = _initDbasSqlite();
    if (result is Future) await result;
  }
}

extension DbasSqliteNativeWebExtension on DbasSqliteNativeWeb {
  external Pointer<DbasSqliteDb> openDb(String path);
  external int executeSql(int dbPtr, String sql);
  external int prepareQuery(int dbPtr, String sql);

  external void bindNull(int stmt, int index);
  external void bindInt(int stmt, int index, int value);
  external void bindFloat(int stmt, int index, double value);
  external void bindDouble(int stmt, int index, double value);
  external void bindText(int stmt, int index, String value);
  external void bindBlob(int stmt, int index, Uint8List value);

  external void bindNameNull(int stmt, String name);
  external void bindNameInt(int stmt, String name, int value);
  external void bindNameFloat(int stmt, String name, double value);
  external void bindNameDouble(int stmt, String name, double value);
  external void bindNameText(int stmt, String name, String value);
  external void bindNameBlob(int stmt, String name, Uint8List value);

  external int readRow(int stmt);
  external int isNull(int stmt, int colIndex);

  external String getColumnText(int stmt, int colIndex);
  external int getColumnInt(int stmt, int colIndex);
  external double getColumnFloat(int stmt, int colIndex);
  external double getColumnDouble(int stmt, int colIndex);
  external int getColumnCount(int stmt);

  external String getLastDbError(int dbPtr);
  external int getAffectedRows(int dbPtr);
  external int getLastInsertedId(int dbPtr);

  external void closeReader(int stmt);
  external void closeDb(int dbPtr);
}
