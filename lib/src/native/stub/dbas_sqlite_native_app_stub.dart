import 'dart:ffi';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';
import 'package:ffi/ffi.dart';
import '../dbas_sqlite_native_interface.dart';

class DbasSqliteNativeApp implements DbasSqliteNativeInterface {
  @override
  Future<void> initialize() async =>
      throw UnsupportedError('Not supported in native app.');

  @override
  String getLibraryPath() => throw UnsupportedError('Not supported in native app.');

  @override
  Pointer<DbasSqliteDbStruct> openDb(Pointer<Utf8> path) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  bool isOpened(Pointer<DbasSqliteDbStruct> dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int executeSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int prepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Uint8> value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Uint8> value) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int readRow(Pointer<DbasSqliteDbStruct> dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int isNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Pointer<Utf8> getColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  double getColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  double getColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Pointer<Uint8> getColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getColumnCount(Pointer<DbasSqliteDbStruct> dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Pointer<Utf8> getLastDbError(Pointer<DbasSqliteDbStruct> dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  int getLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  void closeReader(Pointer<DbasSqliteDbStruct> dbPtr) =>
      throw UnsupportedError('Not supported in native app.');

  @override
  Future<void> closeDb(Pointer<DbasSqliteDbStruct> dbPtr) async =>
      throw UnsupportedError('Not supported in native app.');
}