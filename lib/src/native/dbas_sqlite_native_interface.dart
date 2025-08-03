import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_app.dart';
import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_web.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../dbas_sqlite_db.dart';

abstract class DbasSqliteNativeInterface {
  static final DbasSqliteNativeInterface instance = _getPlatform();

  static DbasSqliteNativeInterface _getPlatform() {
    if (kIsWeb) {
      return DbasSqliteNativeWeb();
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return DbasSqliteNativeApp();
    }
    throw UnsupportedError("Platform not supported: ${Platform.operatingSystem}");
  }

  Future<void> initialize();

  external Pointer<DbasSqliteDbStruct> openDb(Pointer<Utf8> path);
  external bool isOpened(Pointer<DbasSqliteDbStruct> dbPtr);

  external int executeSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);
  external int prepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);

  external void bindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index);
  external void bindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value);
  external void bindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);
  external void bindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);
  external void bindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value);
  external void bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Uint8List value);

  external void bindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name);
  external void bindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value);
  external void bindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);
  external void bindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);
  external void bindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value);
  external void bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Uint8List value);

  external int readRow(Pointer<DbasSqliteDbStruct> dbPtr);
  external int isNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  external Pointer<Utf8> getColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  external int getColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  external double getColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  external double getColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  external Pointer<Uint8> getColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);
  external int getColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);
  external int getColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  external int getColumnCount(Pointer<DbasSqliteDbStruct> dbPtr);

  external Pointer<Utf8> getLastDbError(Pointer<DbasSqliteDbStruct> dbPtr);
  external int getAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr);
  external int getLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr);

  external void closeReader(Pointer<DbasSqliteDbStruct> dbPtr);
  external void closeDb(Pointer<DbasSqliteDbStruct> dbPtr);
}