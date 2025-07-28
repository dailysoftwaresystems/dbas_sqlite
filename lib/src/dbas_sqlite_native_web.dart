import 'dart:ffi';
import 'dart:typed_data';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';
import 'package:decimal/decimal.dart';

class DbasSqliteNativeWeb {
  Future<void> initialize() async {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  Future<Pointer<DbasSqliteDb>> openDb(String filePath) async {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  Future<int> executeSql(Pointer<DbasSqliteDb> dbPtr, String sql) async {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  Future<int> prepareQuery(Pointer<DbasSqliteDb> dbPtr, String sql) async {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindNull(Pointer<DbasSqliteDb> dbPtr, int index) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindInt(Pointer<DbasSqliteDb> dbPtr, int index, int value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindDecimal(Pointer<DbasSqliteDb> dbPtr, int index, Decimal value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindDouble(Pointer<DbasSqliteDb> dbPtr, int index, double value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindText(Pointer<DbasSqliteDb> dbPtr, int index, String value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindBlob(Pointer<DbasSqliteDb> dbPtr, int index, Uint8List value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindNameNull(Pointer<DbasSqliteDb> dbPtr, String name) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindNameInt(Pointer<DbasSqliteDb> dbPtr, String name, int value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindNameDecimal(Pointer<DbasSqliteDb> dbPtr, String name, Decimal value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindNameDouble(Pointer<DbasSqliteDb> dbPtr, String name, double value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindNameText(Pointer<DbasSqliteDb> dbPtr, String name, String value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void bindNameBlob(Pointer<DbasSqliteDb> dbPtr, String name, Uint8List value) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  int readRow(Pointer<DbasSqliteDb> dbPtr) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  int isNull(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  String getColumnText(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  int getColumnInt(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  Decimal getColumnDecimal(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  double getColumnDouble(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  Pointer<Uint8> getColumnBlob(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  int getColumnBytes(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  int getColumnType(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  int getColumnCount(Pointer<DbasSqliteDb> dbPtr) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  String getLastDbError(Pointer<DbasSqliteDb> dbPtr) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  int getAffectedRows(Pointer<DbasSqliteDb> dbPtr) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  int getLastInsertedId(Pointer<DbasSqliteDb> dbPtr) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  void closeReader(Pointer<DbasSqliteDb> dbPtr) {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }

  Future<void> closeDb(Pointer<DbasSqliteDb> dbPtr) async {
    throw UnsupportedError('DbasSqliteNativeWeb is only supported on Web.');
  }
}