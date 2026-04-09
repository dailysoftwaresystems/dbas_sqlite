import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dbas_sqlite_native_app_base.dart';
import '../dbas_sqlite_db.dart';

class DbasSqliteNativeApp extends DbasSqliteNativeAppBase {
  DbasSqliteNativeApp(super.dbName);

  // ── @Native declarations (AOT / compile-time linking) ──────────────────
  @Native<Pointer<DbasSqliteDbStruct> Function(Handle, Pointer<Utf8>)>(symbol: 'OpenDb')
  external Pointer<DbasSqliteDbStruct> _openDb(Pointer<Utf8> path);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'IsOpened')
  external int _isOpened(Pointer<DbasSqliteDbStruct> dbPtr);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>(symbol: 'ExecuteSql')
  external int _executeSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>(symbol: 'PrepareQuery')
  external int _prepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'BindNull')
  external int _bindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Int32)>(symbol: 'BindInt')
  external int _bindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Float)>(symbol: 'BindFloat')
  external int _bindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Double)>(symbol: 'BindDouble')
  external int _bindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Pointer<Utf8>)>(symbol: 'BindText')
  external int _bindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Pointer<Uint8>, Int32)>(symbol: 'BindBlob')
  external int _bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Uint8> value, int length);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>(symbol: 'BindNameNull')
  external int _bindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Int32)>(symbol: 'BindNameInt')
  external int _bindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Float)>(symbol: 'BindNameFloat')
  external int _bindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Double)>(symbol: 'BindNameDouble')
  external int _bindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>)>(symbol: 'BindNameText')
  external int _bindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>, Int32)>(symbol: 'BindNameBlob')
  external int _bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Uint8> value, int length);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'ReadRow')
  external int _readRow(Pointer<DbasSqliteDbStruct> dbPtr);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'IsNull')
  external int _isNullNative(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @Native<Pointer<Utf8> Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnText')
  external Pointer<Utf8> _getColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnInt')
  external int _getColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @Native<Float Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnFloat')
  external double _getColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @Native<Double Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnDouble')
  external double _getColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @Native<Pointer<Uint8> Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnBlob')
  external Pointer<Uint8> _getColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnBytes')
  external int _getColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);

  @Native<Pointer<Utf8> Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnName')
  external Pointer<Utf8> _getColumnName(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'GetColumnType')
  external int _getColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'GetColumnCount')
  external int _getColumnCount(Pointer<DbasSqliteDbStruct> dbPtr);

  @Native<Pointer<Utf8> Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'GetLastDbError')
  external Pointer<Utf8> _getLastDbError(Pointer<DbasSqliteDbStruct> dbPtr);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'GetAffectedRows')
  external int _getAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'GetLastInsertedId')
  external int _getLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'CloseReader')
  external void _closeReader(Pointer<DbasSqliteDbStruct> dbPtr);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'CloseDb')
  external void _closeDb(Pointer<DbasSqliteDbStruct> dbPtr);

  // ── Connection Pool ────────────────────────────────────────────────────
  @Native<Pointer<DbasSqlitePoolStruct> Function(Handle, Pointer<Utf8>, Int32)>(symbol: 'CreatePool')
  external Pointer<DbasSqlitePoolStruct> _createPool(Pointer<Utf8> path, int readerCount);

  @Native<Pointer<DbasSqliteDbStruct> Function(Handle, Pointer<DbasSqlitePoolStruct>)>(symbol: 'PoolGetWriter')
  external Pointer<DbasSqliteDbStruct> _poolGetWriter(Pointer<DbasSqlitePoolStruct> poolPtr);

  @Native<Pointer<DbasSqliteDbStruct> Function(Handle, Pointer<DbasSqlitePoolStruct>)>(symbol: 'PoolAcquireReader')
  external Pointer<DbasSqliteDbStruct> _poolAcquireReader(Pointer<DbasSqlitePoolStruct> poolPtr);

  @Native<Void Function(Handle, Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>)>(symbol: 'PoolReleaseReader')
  external void _poolReleaseReader(Pointer<DbasSqlitePoolStruct> poolPtr, Pointer<DbasSqliteDbStruct> readerPtr);

  @Native<Void Function(Handle, Pointer<DbasSqlitePoolStruct>)>(symbol: 'ClosePool')
  external void _closePool(Pointer<DbasSqlitePoolStruct> poolPtr);

  // ── Initialize (no-op for AOT) ─────────────────────────────────────────
  @override
  Future<void> initialize() async {}

  // ── Native delegates ───────────────────────────────────────────────────
  @override
  Pointer<DbasSqliteDbStruct> nativeOpenDb(Pointer<Utf8> path) => _openDb(path);
  @override
  int nativeIsOpened(Pointer<DbasSqliteDbStruct> dbPtr) => _isOpened(dbPtr);
  @override
  int nativeExecuteSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) => _executeSql(dbPtr, sql);
  @override
  int nativePrepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) => _prepareQuery(dbPtr, sql);

  @override
  int nativeBindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index) => _bindNull(dbPtr, index);
  @override
  int nativeBindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value) => _bindInt(dbPtr, index, value);
  @override
  int nativeBindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value) => _bindFloat(dbPtr, index, value);
  @override
  int nativeBindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value) => _bindDouble(dbPtr, index, value);
  @override
  int nativeBindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value) => _bindText(dbPtr, index, value);
  @override
  int nativeBindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Uint8> value, int length) => _bindBlob(dbPtr, index, value, length);

  @override
  int nativeBindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name) => _bindNameNull(dbPtr, name);
  @override
  int nativeBindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value) => _bindNameInt(dbPtr, name, value);
  @override
  int nativeBindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value) => _bindNameFloat(dbPtr, name, value);
  @override
  int nativeBindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value) => _bindNameDouble(dbPtr, name, value);
  @override
  int nativeBindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value) => _bindNameText(dbPtr, name, value);
  @override
  int nativeBindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Uint8> value, int length) => _bindNameBlob(dbPtr, name, value, length);

  @override
  int nativeReadRow(Pointer<DbasSqliteDbStruct> dbPtr) => _readRow(dbPtr);
  @override
  int nativeIsNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _isNullNative(dbPtr, colIndex);

  @override
  Pointer<Utf8> nativeGetColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnText(dbPtr, colIndex);
  @override
  int nativeGetColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnInt(dbPtr, colIndex);
  @override
  double nativeGetColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnFloat(dbPtr, colIndex);
  @override
  double nativeGetColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnDouble(dbPtr, colIndex);
  @override
  Pointer<Uint8> nativeGetColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) => _getColumnBlob(dbPtr, columnIndex);
  @override
  int nativeGetColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) => _getColumnBytes(dbPtr, columnIndex);
  @override
  Pointer<Utf8> nativeGetColumnName(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) => _getColumnName(dbPtr, columnIndex);
  @override
  int nativeGetColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnType(dbPtr, colIndex);
  @override
  int nativeGetColumnCount(Pointer<DbasSqliteDbStruct> dbPtr) => _getColumnCount(dbPtr);

  @override
  Pointer<Utf8> nativeGetLastDbError(Pointer<DbasSqliteDbStruct> dbPtr) => _getLastDbError(dbPtr);
  @override
  int nativeGetAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr) => _getAffectedRows(dbPtr);
  @override
  int nativeGetLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr) => _getLastInsertedId(dbPtr);

  @override
  void nativeCloseReader(Pointer<DbasSqliteDbStruct> dbPtr) => _closeReader(dbPtr);
  @override
  void nativeCloseDb(Pointer<DbasSqliteDbStruct> dbPtr) => _closeDb(dbPtr);

  // ── Connection Pool ───────────────────────────────────────────────────
  @override
  Pointer<DbasSqlitePoolStruct> nativeCreatePool(Pointer<Utf8> path, int readerCount) => _createPool(path, readerCount);
  @override
  Pointer<DbasSqliteDbStruct> nativePoolGetWriter(Pointer<DbasSqlitePoolStruct> poolPtr) => _poolGetWriter(poolPtr);
  @override
  Pointer<DbasSqliteDbStruct> nativePoolAcquireReader(Pointer<DbasSqlitePoolStruct> poolPtr) => _poolAcquireReader(poolPtr);
  @override
  void nativePoolReleaseReader(Pointer<DbasSqlitePoolStruct> poolPtr, Pointer<DbasSqliteDbStruct> readerPtr) => _poolReleaseReader(poolPtr, readerPtr);
  @override
  void nativeClosePool(Pointer<DbasSqlitePoolStruct> poolPtr) => _closePool(poolPtr);
}
