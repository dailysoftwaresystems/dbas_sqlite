import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dbas_sqlite_native_interface.dart';
import '../dbas_sqlite_db.dart';

class DbasSqliteNativeApp extends DbasSqliteNativeInterface {
  @override
  Future<void> initialize() async {

  }

  @override
  @Native<Pointer<DbasSqliteDbStruct> Function(DbasSqliteNativeApp, Pointer<Utf8>)>(symbol: 'OpenDb')
  external Pointer<DbasSqliteDbStruct> openDb(Pointer<Utf8> path);

  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>)>(symbol: 'IsOpened')
  external int _isOpened(Pointer<DbasSqliteDbStruct> dbPtr);

  @override
  bool isOpened(Pointer<DbasSqliteDbStruct> dbPtr) => _isOpened(dbPtr) == 1;

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>(symbol: 'ExecuteSql')
  external int executeSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>(symbol: 'PrepareQuery')
  external int prepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'BindNull')
  external void bindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32, Int32)>(symbol: 'BindInt')
  external void bindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32, Float)>(symbol: 'BindFloat')
  external void bindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32, Double)>(symbol: 'BindDouble')
  external void bindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32, Pointer<Utf8>)>(symbol: 'BindText')
  external void bindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32, Pointer<Uint8>)>(symbol: 'BindBlob')
  external void bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Uint8List value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>(symbol: 'BindNameNull')
  external void bindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Int32)>(symbol: 'BindNameInt')
  external void bindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Float)>(symbol: 'BindNameFloat')
  external void bindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Double)>(symbol: 'BindNameDouble')
  external void bindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>)>(symbol: 'BindNameText')
  external void bindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>)>(symbol: 'BindNameBlob')
  external void bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Uint8List value);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>)>(symbol: 'ReadRow')
  external int readRow(Pointer<DbasSqliteDbStruct> dbPtr);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'IsNull')
  external int isNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @override
  @Native<Pointer<Utf8> Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnText')
  external Pointer<Utf8> getColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnInt')
  external int getColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @override
  @Native<Float Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnFloat')
  external double getColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @override
  @Native<Double Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnDouble')
  external double getColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @override
  @Native<Pointer<Uint8> Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnBlob')
  external Pointer<Uint8> getColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnBytes')
  external int getColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnType')
  external int getColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>)>(symbol: 'GetColumnCount')
  external int getColumnCount(Pointer<DbasSqliteDbStruct> dbPtr);

  @override
  @Native<Pointer<Utf8> Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>)>(symbol: 'GetLastDbError')
  external Pointer<Utf8> getLastDbError(Pointer<DbasSqliteDbStruct> dbPtr);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>)>(symbol: 'GetAffectedRows')
  external int getAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr);

  @override
  @Native<Int32 Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>)>(symbol: 'GetLastInsertedId')
  external int getLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>)>(symbol: 'CloseReader')
  external void closeReader(Pointer<DbasSqliteDbStruct> dbPtr);

  @override
  @Native<Void Function(DbasSqliteNativeApp, Pointer<DbasSqliteDbStruct>)>(symbol: 'CloseDb')
  external void closeDb(Pointer<DbasSqliteDbStruct> dbPtr);
}