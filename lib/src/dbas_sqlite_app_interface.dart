import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:decimal/decimal.dart';

import 'dbas_sqlite_db.dart';
import 'dbas_sqlite_platform_interface.dart';

abstract class DbasSqliteApp extends DbasSqlitePlatform {
  static DynamicLibrary? _sqlite;

  @override
  Future<void> initialize() async {
    if (DbasSqliteApp._sqlite == null) {
      await internalInitialize();
    }
  }

  Future<void> internalInitialize();

  @override
  Future<Pointer<DbasSqliteDb>> openDb(String fileName) async {
    final functionPtr = _sqlite!.lookupFunction<
        Pointer<DbasSqliteDb> Function(Pointer<Utf8>),
        Pointer<DbasSqliteDb> Function(Pointer<Utf8>)
    >('OpenDb');

    final sqlC = fileName.toNativeUtf8();
    final resultPtr = functionPtr(sqlC);
    calloc.free(sqlC);

    if (resultPtr == nullptr) {
      throw Exception(['It was not possible to open database at: $fileName']);
    }

    return resultPtr;
  }

  @override
  Future<int> executeSql(Pointer<DbasSqliteDb> dbPtr, String sql) async {
    final functionPtr = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>)
    >('ExecuteSql');

    final sqlC = sql.toNativeUtf8();
    final result = functionPtr(dbPtr, sqlC);
    calloc.free(sqlC);

    return result;
  }

  @override
  Future<int> prepareQuery(Pointer<DbasSqliteDb> dbPtr, String sql) async {
    final functionPtr = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>)
    >('PrepareQuery');

    final sqlC = sql.toNativeUtf8();
    final result = functionPtr(dbPtr, sqlC);
    calloc.free(sqlC);

    return result;
  }

  @override
  int bindText(Pointer<DbasSqliteDb> dbPtr, int index, String value) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Int32, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDb>, int, Pointer<Utf8>)
    >('BindText');

    final valueC = value.toNativeUtf8();
    final result = func(dbPtr, index, valueC);
    calloc.free(valueC);

    return result;
  }

  @override
  int bindInt(Pointer<DbasSqliteDb> dbPtr, int index, int value) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Int32, Int32),
        int Function(Pointer<DbasSqliteDb>, int, int)
    >('BindInt');

    return func(dbPtr, index, value);
  }

  @override
  int bindDecimal(Pointer<DbasSqliteDb> dbPtr, int index, Decimal value) {
    return bindDouble(dbPtr, index, double.parse(value.toString()));
  }

  @override
  int bindDouble(Pointer<DbasSqliteDb> dbPtr, int index, double value) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Int32, Double),
        int Function(Pointer<DbasSqliteDb>, int, double)
    >('BindDouble');

    return func(dbPtr, index, value);
  }

  @override
  int bindNull(Pointer<DbasSqliteDb> dbPtr, int index) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Int32),
        int Function(Pointer<DbasSqliteDb>, int)
    >('BindNull');

    return func(dbPtr, index);
  }

  @override
  int bindBlob(Pointer<DbasSqliteDb> dbPtr, int index, Uint8List data) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Int32, Pointer<Void>, Int32),
        int Function(Pointer<DbasSqliteDb>, int, Pointer<Void>, int)
    >('BindBlob');

    final blob = calloc<Uint8>(data.length);
    final byteList = blob.asTypedList(data.length);
    byteList.setAll(0, data);

    final result = func(dbPtr, index, blob.cast<Void>(), data.length);
    calloc.free(blob);

    return result;
  }

  @override
  int bindNameText(Pointer<DbasSqliteDb> dbPtr, String name, String value) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>, Pointer<Utf8>)
    >('BindNameText');

    final nameC = name.toNativeUtf8();
    final valueC = value.toNativeUtf8();

    final result = func(dbPtr, nameC, valueC);
    calloc.free(nameC);
    calloc.free(valueC);

    return result;
  }

  @override
  int bindNameInt(Pointer<DbasSqliteDb> dbPtr, String name, int value) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>, Int32),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>, int)
    >('BindNameInt');

    final nameC = name.toNativeUtf8();
    final result = func(dbPtr, nameC, value);
    calloc.free(nameC);

    return result;
  }

  @override
  int bindNameDecimal(Pointer<DbasSqliteDb> dbPtr, String name, Decimal value) {
    return bindNameDouble(dbPtr, name, double.parse(value.toString()));
  }

  @override
  int bindNameDouble(Pointer<DbasSqliteDb> dbPtr, String name, double value) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>, Double),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>, double)
    >('BindNameDouble');

    final nameC = name.toNativeUtf8();
    final result = func(dbPtr, nameC, value);
    calloc.free(nameC);

    return result;
  }

  @override
  int bindNameNull(Pointer<DbasSqliteDb> dbPtr, String name) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>)
    >('BindNameNull');

    final nameC = name.toNativeUtf8();
    final result = func(dbPtr, nameC);
    calloc.free(nameC);

    return result;
  }

  @override
  int bindNameBlob(Pointer<DbasSqliteDb> dbPtr, String name, Uint8List data) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>, Pointer<Void>, Int32),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>, Pointer<Void>, int)
    >('BindNameBlob');

    final nameC = name.toNativeUtf8();
    final blob = calloc<Uint8>(data.length);
    final byteList = blob.asTypedList(data.length);
    byteList.setAll(0, data);

    final result = func(dbPtr, nameC, blob.cast<Void>(), data.length);
    calloc.free(nameC);
    calloc.free(blob);

    return result;
  }

  @override
  int readRow(Pointer<DbasSqliteDb> dbPtr) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>),
        int Function(Pointer<DbasSqliteDb>)
    >('ReadRow');

    return func(dbPtr);
  }

  @override
  int isNull(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>),
        int Function(Pointer<DbasSqliteDb>)
    >('IsNull');

    return func(dbPtr);
  }

  @override
  String getColumnText(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    final func = _sqlite!.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDb>, Int32),
        Pointer<Utf8> Function(Pointer<DbasSqliteDb>, int)
    >('GetColumnText');

    final ptr = func(dbPtr, columnIndex);
    return ptr.toDartString();
  }

  @override
  int getColumnInt(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Int32),
        int Function(Pointer<DbasSqliteDb>, int)
    >('GetColumnInt');

    return func(dbPtr, columnIndex);
  }

  @override
  Decimal getColumnDecimal(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    final result = getColumnDouble(dbPtr, columnIndex);
    return Decimal.parse(result.toString());
  }

  @override
  double getColumnDouble(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    final func = _sqlite!.lookupFunction<
        Double Function(Pointer<DbasSqliteDb>, Int32),
        double Function(Pointer<DbasSqliteDb>, int)
    >('GetColumnDouble');

    return func(dbPtr, columnIndex);
  }

  @override
  Pointer<Uint8> getColumnBlob(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    final func = _sqlite!.lookupFunction<
        Pointer<Uint8> Function(Pointer<DbasSqliteDb>, Int32),
        Pointer<Uint8> Function(Pointer<DbasSqliteDb>, int)
    >('GetColumnBlob');

    return func(dbPtr, columnIndex);
  }

  @override
  int getColumnBytes(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Int32),
        int Function(Pointer<DbasSqliteDb>, int)
    >('GetColumnBytes');

    return func(dbPtr, columnIndex);
  }

  @override
  int getColumnType(Pointer<DbasSqliteDb> dbPtr, int columnIndex) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Int32),
        int Function(Pointer<DbasSqliteDb>, int)
    >('GetColumnType');

    return func(dbPtr, columnIndex);
  }

  @override
  int getColumnCount(Pointer<DbasSqliteDb> dbPtr) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>),
        int Function(Pointer<DbasSqliteDb>)
    >('GetColumnCount');

    return func(dbPtr);
  }

  @override
  String getLastDbError(Pointer<DbasSqliteDb> dbPtr) {
    final func = _sqlite!.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDb>),
        Pointer<Utf8> Function(Pointer<DbasSqliteDb>)
    >('GetLastDbError');

    final ptr = func(dbPtr);
    return ptr.toDartString();
  }

  @override
  int getAffectedRows(Pointer<DbasSqliteDb> dbPtr) {
    final func = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>),
        int Function(Pointer<DbasSqliteDb>)
    >('GetAffectedRows');

    return func(dbPtr);
  }

  @override
  int getLastInsertedId(Pointer<DbasSqliteDb> dbPtr) {
    final func = _sqlite!.lookupFunction<
        Int64 Function(Pointer<DbasSqliteDb>),
        int Function(Pointer<DbasSqliteDb>)
    >('GetLastInsertedId');

    return func(dbPtr);
  }

  @override
  Future<void> closeReader(Pointer<DbasSqliteDb> dbPtr) async {
    final func = _sqlite!.lookupFunction<
        Void Function(Pointer<DbasSqliteDb>),
        void Function(Pointer<DbasSqliteDb>)
    >('CloseReader');

    func(dbPtr);
  }

  @override
  Future<void> closeDb(Pointer<DbasSqliteDb> dbPtr) async {
    final func = _sqlite!.lookupFunction<
        Void Function(Pointer<DbasSqliteDb>),
        void Function(Pointer<DbasSqliteDb>)
    >('CloseDb');

    func(dbPtr);
  }
}

class DbasSqliteAndroid extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.open('dbas_sqlite.so'));
  }
}

class DbasSqliteIOS extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.process());
  }
}

class DbasSqliteMacOS extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.process());
  }
}

class DbasSqliteLinux extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.open(path.join(DbasSqlitePlatform.basePath, 'linux', 'dbas_sqlite.so')));
  }
}

class DbasSqliteWindows extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.open(path.join(DbasSqlitePlatform.basePath, 'windows', 'dbas_sqlite.dll')));
  }
}