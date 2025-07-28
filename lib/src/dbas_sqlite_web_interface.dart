import 'dart:ffi';
import 'dart:typed_data';

import 'dbas_sqlite_db.dart';
import 'dbas_sqlite_native_web.dart';
import 'dbas_sqlite_platform_interface.dart';
import 'package:decimal/decimal.dart';

class DbasSqliteWeb extends DbasSqlitePlatform {
  static DbasSqliteNativeWeb? _sqlite;

  @override
  Future<void> initialize() async {
    if (DbasSqliteWeb._sqlite == null) {
      DbasSqliteWeb._sqlite = DbasSqliteNativeWeb();
      await DbasSqliteWeb._sqlite!.initialize();
    }
  }

  @override
  Future<Pointer<DbasSqliteDb>> openDb(String filePath) async {
    return _sqlite!.openDb(filePath);
  }

  @override
  Future<int> executeSql(Pointer<DbasSqliteDb> dbPtr, String sql) async {
    return _sqlite!.executeSql(dbPtr.address, sql);
  }

  @override
  Future<int> prepareQuery(Pointer<DbasSqliteDb> dbPtr, String sql) async {
    return _sqlite!.prepareQuery(dbPtr.address, sql);
  }

  @override
  void bindNull(Pointer<DbasSqliteDb> dbPtr, int index) {
    _sqlite!.bindNull(dbPtr.address, index);
  }

  @override
  void bindInt(Pointer<DbasSqliteDb> dbPtr, int index, int value) {
    _sqlite!.bindInt(dbPtr.address, index, value);
  }

  @override
  void bindDecimal(Pointer<DbasSqliteDb> dbPtr, int index, Decimal value) {
    bindDouble(dbPtr, index, double.parse(value.toString()));
  }

  @override
  void bindDouble(Pointer<DbasSqliteDb> dbPtr, int index, double value) {
    _sqlite!.bindDouble(dbPtr.address, index, value);
  }

  @override
  void bindText(Pointer<DbasSqliteDb> dbPtr, int index, String value) {
    _sqlite!.bindText(dbPtr.address, index, value);
  }

  @override
  void bindBlob(Pointer<DbasSqliteDb> dbPtr, int index, Uint8List value) {
    _sqlite!.bindBlob(dbPtr.address, index, value);
  }

  @override
  void bindNameNull(Pointer<DbasSqliteDb> dbPtr, String name) {
    _sqlite!.bindNameNull(dbPtr.address, name);
  }

  @override
  void bindNameInt(Pointer<DbasSqliteDb> dbPtr, String name, int value) {
    _sqlite!.bindNameInt(dbPtr.address, name, value);
  }

  @override
  void bindNameDecimal(Pointer<DbasSqliteDb> dbPtr, String name, Decimal value) {
    bindNameDouble(dbPtr, name, double.parse(value.toString()));
  }

  @override
  void bindNameDouble(Pointer<DbasSqliteDb> dbPtr, String name, double value) {
    _sqlite!.bindNameDouble(dbPtr.address, name, value);
  }

  @override
  void bindNameText(Pointer<DbasSqliteDb> dbPtr, String name, String value) {
    _sqlite!.bindNameText(dbPtr.address, name, value);
  }

  @override
  void bindNameBlob(Pointer<DbasSqliteDb> dbPtr, String name, Uint8List value) {
    _sqlite!.bindNameBlob(dbPtr.address, name, value);
  }

  @override
  int readRow(Pointer<DbasSqliteDb> dbPtr) {
    return _sqlite!.readRow(dbPtr.address);
  }

  @override
  int isNull(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    return _sqlite!.isNull(dbPtr.address, colIndex);
  }

  @override
  String getColumnText(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    return _sqlite!.getColumnText(dbPtr.address, colIndex);
  }

  @override
  int getColumnInt(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    return _sqlite!.getColumnInt(dbPtr.address, colIndex);
  }

  @override
  Decimal getColumnDecimal(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    return Decimal.parse(getColumnDouble(dbPtr, colIndex).toString());
  }

  @override
  double getColumnDouble(Pointer<DbasSqliteDb> dbPtr, int colIndex) {
    return _sqlite!.getColumnDouble(dbPtr.address, colIndex);
  }

  @override
  int getColumnCount(Pointer<DbasSqliteDb> dbPtr) {
    return _sqlite!.getColumnCount(dbPtr.address);
  }

  @override
  String getLastDbError(Pointer<DbasSqliteDb> dbPtr) {
    return _sqlite!.getLastDbError(dbPtr.address);
  }

  @override
  int getAffectedRows(Pointer<DbasSqliteDb> dbPtr) {
    return _sqlite!.getAffectedRows(dbPtr.address);
  }

  @override
  int getLastInsertedId(Pointer<DbasSqliteDb> dbPtr) {
    return _sqlite!.getLastInsertedId(dbPtr.address);
  }

  @override
  void closeReader(Pointer<DbasSqliteDb> dbPtr) {
    _sqlite!.closeReader(dbPtr.address);
  }

  @override
  Future<void> closeDb(Pointer<DbasSqliteDb> dbPtr) async {
    _sqlite!.closeDb(dbPtr.address);
  }
}
