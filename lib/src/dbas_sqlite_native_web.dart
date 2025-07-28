@JS()
library;

import 'dart:ffi';
import 'dart:js/js_wasm.dart';
import 'dart:typed_data';

import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';

@JS('initDbasSqlite')
external Object _initDbasSqlite();

@JS('openDb')
external Pointer<DbasSqliteDb> _openDb(String path);

@JS('executeSql')
external int _executeSql(int dbPtr, String sql);

@JS('prepareQuery')
external int _prepareQuery(int dbPtr, String sql);

@JS('bindNull')
external void _bindNull(int stmt, int index);

@JS('bindInt')
external void _bindInt(int stmt, int index, int value);

@JS('bindDouble')
external void _bindDouble(int stmt, int index, double value);

@JS('bindFloat')
external void _bindFloat(int stmt, int index, double value);

@JS('bindText')
external void _bindText(int stmt, int index, String value);

@JS('bindBlob')
external void _bindBlob(int stmt, int index, Uint8List value);

@JS('bindNameNull')
external void _bindNameNull(int stmt, String name);

@JS('bindNameInt')
external void _bindNameInt(int stmt, String name, int value);

@JS('bindNameFloat')
external void _bindNameFloat(int stmt, String name, double value);

@JS('bindNameDouble')
external void _bindNameDouble(int stmt, String name, double value);

@JS('bindNameText')
external void _bindNameText(int stmt, String name, String value);

@JS('bindNameBlob')
external void _bindNameBlob(int stmt, String name, Uint8List value);

@JS('readRow')
external int _readRow(int stmt);

@JS('isNull')
external int _isNull(int stmt, int colIndex);

@JS('getColumnText')
external String _getColumnText(int stmt, int colIndex);

@JS('getColumnInt')
external int _getColumnInt(int stmt, int colIndex);

@JS('getColumnFloat')
external double _getColumnFloat(int stmt, int colIndex);

@JS('getColumnDouble')
external double _getColumnDouble(int stmt, int colIndex);

@JS('getColumnCount')
external int _getColumnCount(int stmt);

@JS('getLastDbError')
external String _getLastDbError(int dbPtr);

@JS('getAffectedRows')
external int _getAffectedRows(int dbPtr);

@JS('getLastInsertedId')
external int _getLastInsertedId(int dbPtr);

@JS('closeReader')
external void _closeReader(int stmt);

@JS('closeDb')
external void _closeDb(int dbPtr);

class DbasSqliteNativeWeb {
  Future<void> initialize() async {
    final result = _initDbasSqlite();
    if (result is Future) await result;
  }

  Pointer<DbasSqliteDb> openDb(String filePath) => _openDb(filePath);

  int executeSql(int dbPtr, String sql) => _executeSql(dbPtr, sql);

  int prepareQuery(int dbPtr, String sql) => _prepareQuery(dbPtr, sql);

  void bindNull(int stmt, int index) => _bindNull(stmt, index);

  void bindInt(int stmt, int index, int value) => _bindInt(stmt, index, value);

  void bindFloat(int stmt, int index, double value) => _bindFloat(stmt, index, value);

  void bindDouble(int stmt, int index, double value) => _bindDouble(stmt, index, value);

  void bindText(int stmt, int index, String value) => _bindText(stmt, index, value);

  void bindBlob(int stmt, int index, Uint8List value) => _bindBlob(stmt, index, value);

  void bindNameNull(int stmt, String name) => _bindNameNull(stmt, name);

  void bindNameInt(int stmt, String name, int value) => _bindNameInt(stmt, name, value);

  void bindNameFloat(int stmt, String name, double value) => _bindNameFloat(stmt, name, value);

  void bindNameDouble(int stmt, String name, double value) => _bindNameDouble(stmt, name, value);

  void bindNameText(int stmt, String name, String value) => _bindNameText(stmt, name, value);

  void bindNameBlob(int stmt, String name, Uint8List value) => _bindNameBlob(stmt, name, value);

  int readRow(int stmt) => _readRow(stmt);

  int isNull(int stmt, int colIndex) => isNull(stmt, colIndex);

  String getColumnText(int stmt, int colIndex) => _getColumnText(stmt, colIndex);

  int getColumnInt(int stmt, int colIndex) => _getColumnInt(stmt, colIndex);

  double getColumnFloat(int stmt, int colIndex) => _getColumnFloat(stmt, colIndex);

  double getColumnDouble(int stmt, int colIndex) => _getColumnDouble(stmt, colIndex);

  int getColumnCount(int stmt) => _getColumnCount(stmt);

  String getLastDbError(int dbPtr) => _getLastDbError(dbPtr);

  int getAffectedRows(int dbPtr) => _getAffectedRows(dbPtr);

  int getLastInsertedId(int dbPtr) => _getLastInsertedId(dbPtr);

  void closeReader(int stmt) => _closeReader(stmt);

  void closeDb(int dbPtr) => _closeDb(dbPtr);
}
