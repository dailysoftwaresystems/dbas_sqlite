import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_interface.dart';
import 'dbas_sqlite_db.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:decimal/decimal.dart';

final class DbasSqlitePlatform {
  static DbasSqlitePlatform? _instance;
  static final DbasSqliteNativeInterface _delegate = DbasSqliteNativeInterface.instance;

  static Future<DbasSqlitePlatform> getInstance() async {
    if (_instance != null) {
      return _instance!;
    }

    _instance = DbasSqlitePlatform();
    await _instance!.initialize();
    return _instance!;
  }

  Future<void> initialize() => _delegate.initialize();

  Future<DbasSqliteDb> openDb(String path) async {
    final dbPathPtr = path.toNativeUtf8();
    final dbPtr = _delegate.openDb(dbPathPtr);
    malloc.free(dbPathPtr);

    final isOpened = _delegate.isOpened(dbPtr);
    Pointer<Utf8>? lastError = isOpened ? nullptr : _delegate.getLastDbError(dbPtr);

    if (dbPtr == nullptr || !isOpened) {
      String lastErrorMessage = (lastError != '' && lastError != nullptr)
          ? lastError.toDartString()
          : 'Unknown error';
      malloc.free(dbPtr);
      throw Exception('Failed to open db in: $path. Reason: $lastErrorMessage');
    }

    return DbasSqliteDb(dbPtr);
  }

  bool isOpened(DbasSqliteDb db) {
    return _delegate.isOpened(db.ptr);
  }

  Future<int> executeSql(DbasSqliteDb db, String sql) async =>
      _delegate.executeSql(db.ptr, sql.toNativeUtf8());

  Future<int> prepareQuery(DbasSqliteDb db, String sql) async =>
      _delegate.prepareQuery(db.ptr, sql.toNativeUtf8());

  void bindNull(DbasSqliteDb db, int index) => _delegate.bindNull(db.ptr, index);
  void bindInt(DbasSqliteDb db, int index, int value) => _delegate.bindInt(db.ptr, index, value);
  void bindFloat(DbasSqliteDb db, int index, double value) => _delegate.bindFloat(db.ptr, index, value);
  void bindDouble(DbasSqliteDb db, int index, double value) => _delegate.bindDouble(db.ptr, index, value);
  void bindDecimal(DbasSqliteDb db, int index, Decimal value) => _delegate.bindDouble(db.ptr, index, double.parse(value.toString()));
  void bindText(DbasSqliteDb db, int index, String value) =>
      _delegate.bindText(db.ptr, index, value.toNativeUtf8());
  void bindBlob(DbasSqliteDb db, int index, Uint8List value) {
    final ptr = malloc<Uint8>(value.length);
    ptr.asTypedList(value.length).setAll(0, value);
    _delegate.bindBlob(db.ptr, index, ptr);
    malloc.free(ptr);
  }

  void bindNameNull(DbasSqliteDb db, String name) =>
      _delegate.bindNameNull(db.ptr, name.toNativeUtf8());
  void bindNameInt(DbasSqliteDb db, String name, int value) =>
      _delegate.bindNameInt(db.ptr, name.toNativeUtf8(), value);
  void bindNameFloat(DbasSqliteDb db, String name, double value) =>
      _delegate.bindNameFloat(db.ptr, name.toNativeUtf8(), value);
  void bindNameDouble(DbasSqliteDb db, String name, double value) =>
      _delegate.bindNameDouble(db.ptr, name.toNativeUtf8(), value);
  void bindNameDecimal(DbasSqliteDb db, String name, Decimal value) =>
      _delegate.bindNameDouble(db.ptr, name.toNativeUtf8(), double.parse(value.toString()));
  void bindNameText(DbasSqliteDb db, String name, String value) =>
      _delegate.bindNameText(db.ptr, name.toNativeUtf8(), value.toNativeUtf8());
  void bindNameBlob(DbasSqliteDb db, String name, Uint8List value) {
    final ptr = malloc<Uint8>(value.length);
    ptr.asTypedList(value.length).setAll(0, value);
    _delegate.bindNameBlob(db.ptr, name.toNativeUtf8(), ptr);
    malloc.free(ptr);
  }

  int readRow(DbasSqliteDb db) => _delegate.readRow(db.ptr);
  bool isNull(DbasSqliteDb db, int colIndex) => _delegate.isNull(db.ptr, colIndex) == 1;

  String getColumnText(DbasSqliteDb db, int colIndex) =>
      _delegate.getColumnText(db.ptr, colIndex).toDartString();
  int getColumnInt(DbasSqliteDb db, int colIndex) =>
      _delegate.getColumnInt(db.ptr, colIndex);
  double getColumnFloat(DbasSqliteDb db, int colIndex) =>
      _delegate.getColumnFloat(db.ptr, colIndex);
  double getColumnDouble(DbasSqliteDb db, int colIndex) =>
      _delegate.getColumnDouble(db.ptr, colIndex);
  Uint8List getColumnBlob(DbasSqliteDb db, int columnIndex) {
    final ptr = _delegate.getColumnBlob(db.ptr, columnIndex);
    final length = _delegate.getColumnBytes(db.ptr, columnIndex);

    if (length == 0) {
      return Uint8List(0); // Empty blob
    }

    return ptr.asTypedList(length);
  }
  int getColumnBytes(DbasSqliteDb db, int columnIndex) =>
      _delegate.getColumnBytes(db.ptr, columnIndex);
  int getColumnType(DbasSqliteDb db, int colIndex) =>
      _delegate.getColumnType(db.ptr, colIndex);
  int getColumnCount(DbasSqliteDb db) => _delegate.getColumnCount(db.ptr);

  String getLastDbError(DbasSqliteDb db) {
    final errPtr = _delegate.getLastDbError(db.ptr);

    return errPtr != nullptr && errPtr.address != 0
        ? errPtr.toDartString()
        : 'OK';
  }
  int getAffectedRows(DbasSqliteDb db) => _delegate.getAffectedRows(db.ptr);
  int getLastInsertedId(DbasSqliteDb db) => _delegate.getLastInsertedId(db.ptr);

  void closeReader(DbasSqliteDb db) => _delegate.closeReader(db.ptr);
  Future<void> closeDb(DbasSqliteDb db) async => _delegate.closeDb(db.ptr);
}
