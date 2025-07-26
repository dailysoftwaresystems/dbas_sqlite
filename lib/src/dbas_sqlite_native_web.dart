@JS()
library;

import 'dart:js/js_wasm.dart';

@JS('initDbasSqlite')
external Object _initDbasSqlite();

@JS('openDb')
external int _openDb(String path);

@JS('executeSql')
external int _executeSql(int dbPtr, String sql);

@JS('prepareQuery')
external int _prepareQuery(int dbPtr, String sql);

@JS('bindNull')
external void _bindNull(stmt, index);

@JS('bindInt')
external void _bindInt(stmt, index);

@JS('bindDouble')
external void _bindDouble(stmt, index);

@JS('bindText')
external void _bindText(stmt, index);

@JS('bindBlob')
external void _bindBlob(stmt, index);

@JS('readRow')
external Future<int> _readRow();

class DbasSqliteNativeWeb {
  Future<void> initialize() async {
    final result = _initDbasSqlite();
    if (result is Future) await result;
  }

  int openDatabase(String filePath) => _openDb(filePath);

  int executeSql(int dbPtr, String sql) => _executeSql(dbPtr, sql);

  int prepareQuery(int dbPtr, String sql) => _prepareQuery(dbPtr, sql);


}
