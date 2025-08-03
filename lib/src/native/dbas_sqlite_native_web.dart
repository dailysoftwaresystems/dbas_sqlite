import 'dart:ffi';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';
import 'package:ffi/ffi.dart';
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
  external Uint8List getColumnBlob(int stmt, int columnIndex);
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
  Pointer<DbasSqliteDbStruct> openDb(Pointer<Utf8> path) {
    final dartPath = path.toDartString();
    final ptr = Pointer.fromAddress(_js.openDb(dartPath)).cast<DbasSqliteDbStruct>();
    calloc.free(path);
    return ptr;
  }

  @override
  bool isOpened(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _js.isOpened(dbPtr.address);

  @override
  int executeSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) {
    final dartSql = sql.toDartString();
    final result = _js.executeSql(dbPtr.address, dartSql);
    calloc.free(sql);
    return result;
  }

  @override
  int prepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) {
    final dartSql = sql.toDartString();
    final result = _js.prepareQuery(dbPtr.address, dartSql);
    calloc.free(sql);
    return result;
  }

  @override
  void bindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index) =>
      _js.bindNull(dbPtr.address, index);

  @override
  void bindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value) =>
      _js.bindInt(dbPtr.address, index, value);

  @override
  void bindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value) =>
      _js.bindFloat(dbPtr.address, index, value);

  @override
  void bindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value) =>
      _js.bindDouble(dbPtr.address, index, value);

  @override
  void bindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value) =>
      _js.bindText(dbPtr.address, index, value.toDartString());

  @override
  void bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Uint8List value) =>
      _js.bindBlob(dbPtr.address, index, value);

  @override
  void bindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name) =>
      _js.bindNameNull(dbPtr.address, name.toDartString());

  @override
  void bindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value) =>
      _js.bindNameInt(dbPtr.address, name.toDartString(), value);

  @override
  void bindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value) =>
      _js.bindNameFloat(dbPtr.address, name.toDartString(), value);

  @override
  void bindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value) =>
      _js.bindNameDouble(dbPtr.address, name.toDartString(), value);

  @override
  void bindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value) =>
      _js.bindNameText(dbPtr.address, name.toDartString(), value.toDartString());

  @override
  void bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Uint8List value) =>
      _js.bindNameBlob(dbPtr.address, name.toDartString(), value);

  @override
  int readRow(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _js.readRow(dbPtr.address);

  @override
  int isNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      _js.isNull(dbPtr.address, colIndex);

  @override
  Pointer<Utf8> getColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) {
    if (dbPtr.address == 0) {
      return nullptr;
    }
    final value = _js.getColumnText(dbPtr.address, colIndex);
    return value.toNativeUtf8();
  }

  @override
  int getColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      _js.getColumnInt(dbPtr.address, colIndex);

  @override
  double getColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      _js.getColumnFloat(dbPtr.address, colIndex);

  @override
  double getColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      _js.getColumnDouble(dbPtr.address, colIndex);

  @override
  Pointer<Uint8> getColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) {
    final blob = _js.getColumnBlob(dbPtr.address, columnIndex);
    if (blob.isEmpty) return nullptr;
    final ptr = calloc<Uint8>(blob.length);
    final nativeList = ptr.asTypedList(blob.length);
    nativeList.setAll(0, blob);
    return ptr;
  }

  @override
  int getColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) =>
      _js.getColumnBytes(dbPtr.address, columnIndex);

  @override
  int getColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) =>
      _js.getColumnType(dbPtr.address, colIndex);

  @override
  int getColumnCount(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _js.getColumnCount(dbPtr.address);

  @override
  Pointer<Utf8> getLastDbError(Pointer<DbasSqliteDbStruct> dbPtr) {
    final value = _js.getLastDbError(dbPtr.address);
    return value.toNativeUtf8();
  }

  @override
  int getAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _js.getAffectedRows(dbPtr.address);

  @override
  int getLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _js.getLastInsertedId(dbPtr.address);

  @override
  void closeReader(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _js.closeReader(dbPtr.address);

  @override
  void closeDb(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _js.closeDb(dbPtr.address);
}