import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dbas_sqlite_native_interface.dart';
import '../dbas_sqlite_db.dart';

class DbasSqliteNativeApp extends DbasSqliteNativeInterface {
  DbasSqliteNativeApp(super.dbName);

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

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Pointer<Uint8>)>(symbol: 'BindBlob')
  external int _bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Uint8> value);

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

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>)>(symbol: 'BindNameBlob')
  external int _bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Uint8> value);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>)>(symbol: 'ReadRow')
  external int _readRow(Pointer<DbasSqliteDbStruct> dbPtr);

  @Native<Int32 Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'IsNull')
  external int _isNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

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

  Pointer<DbasSqliteDbStruct> _dbPtr(int address) =>
      Pointer<DbasSqliteDbStruct>.fromAddress(address);

  @override
  Future<void> initialize() async {}

  @override
  Future<int> openDb(String path) async {
    final ptr = _openDb(path.toNativeUtf8());
    return ptr.address;
  }

  @override
  Future<bool> databaseExists(String fileName) async {
    final dbFile = File(fileName);
    return await dbFile.exists();
  }

  @override
  Future attachDb(String fileName, List<int> content) async {
    await dropDb(fileName);
    final dbFile = File(fileName);
    await dbFile.writeAsBytes(content);
  }

  @override
  Future<List<int>> getContent(String fileName) async {
    final dbFile = File(fileName);
    return await dbFile.readAsBytes();
  }

  @override
  Future<void> dropDb(String fileName) async {
    final dbFile = File(fileName);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    final walFile = File('$fileName-wal');
    if (await walFile.exists()) {
      await walFile.delete();
    }
    final shmFile = File('$fileName-shm');
    if (await shmFile.exists()) {
      await shmFile.delete();
    }
  }

  @override
  bool isOpened(int dbPtr) => _isOpened(_dbPtr(dbPtr)) == 1;

  @override
  Future<int> executeSql(int dbPtr, String sql, {bool syncWebDb = false}) async =>
      _executeSql(_dbPtr(dbPtr), sql.toNativeUtf8());

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async =>
      _prepareQuery(_dbPtr(dbPtr), sql.toNativeUtf8());

  @override
  int bindNull(int dbPtr, int index) =>
      _bindNull(_dbPtr(dbPtr), index);

  @override
  int bindInt(int dbPtr, int index, int value) =>
      _bindInt(_dbPtr(dbPtr), index, value);

  @override
  int bindFloat(int dbPtr, int index, double value) =>
      _bindFloat(_dbPtr(dbPtr), index, value);

  @override
  int bindDouble(int dbPtr, int index, double value) =>
      _bindDouble(_dbPtr(dbPtr), index, value);

  @override
  int bindText(int dbPtr, int index, String value) =>
      _bindText(_dbPtr(dbPtr), index, value.toNativeUtf8());

  @override
  int bindBlob(int dbPtr, int index, List<int> value) {
    final ptr = calloc<Uint8>(value.length);
    for (var i = 0; i < value.length; i++) {
      ptr[i] = value[i];
    }
    final result = _bindBlob(_dbPtr(dbPtr), index, ptr);
    calloc.free(ptr);
    return result;
  }

  @override
  int bindNameNull(int dbPtr, String name) =>
      _bindNameNull(_dbPtr(dbPtr), name.toNativeUtf8());

  @override
  int bindNameInt(int dbPtr, String name, int value) =>
      _bindNameInt(_dbPtr(dbPtr), name.toNativeUtf8(), value);

  @override
  int bindNameFloat(int dbPtr, String name, double value) =>
      _bindNameFloat(_dbPtr(dbPtr), name.toNativeUtf8(), value);

  @override
  int bindNameDouble(int dbPtr, String name, double value) =>
      _bindNameDouble(_dbPtr(dbPtr), name.toNativeUtf8(), value);

  @override
  int bindNameText(int dbPtr, String name, String value) =>
      _bindNameText(_dbPtr(dbPtr), name.toNativeUtf8(), value.toNativeUtf8());

  @override
  int bindNameBlob(int dbPtr, String name, List<int> value) {
    final namePtr = name.toNativeUtf8();
    final ptr = calloc<Uint8>(value.length);
    for (var i = 0; i < value.length; i++) {
      ptr[i] = value[i];
    }
    final result = _bindNameBlob(_dbPtr(dbPtr), namePtr, ptr);
    calloc.free(ptr);
    calloc.free(namePtr);
    return result;
  }

  @override
  Future<int> readRow(int dbPtr, {bool syncWebDb = false}) async => _readRow(_dbPtr(dbPtr));

  @override
  bool isNull(int dbPtr, int colIndex) => _isNull(_dbPtr(dbPtr), colIndex) == 1;

  @override
  String getColumnText(int dbPtr, int colIndex) =>
      _getColumnText(_dbPtr(dbPtr), colIndex).toDartString();

  @override
  int getColumnInt(int dbPtr, int colIndex) =>
      _getColumnInt(_dbPtr(dbPtr), colIndex);

  @override
  double getColumnFloat(int dbPtr, int colIndex) =>
      _getColumnFloat(_dbPtr(dbPtr), colIndex);

  @override
  double getColumnDouble(int dbPtr, int colIndex) =>
      _getColumnDouble(_dbPtr(dbPtr), colIndex);

  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) {
    final ptr = _getColumnBlob(_dbPtr(dbPtr), columnIndex);
    final length = _getColumnBytes(_dbPtr(dbPtr), columnIndex);
    return ptr.asTypedList(length);
  }

  @override
  int getColumnBytes(int dbPtr, int columnIndex) =>
      _getColumnBytes(_dbPtr(dbPtr), columnIndex);

  @override
  String getColumnName(int dbPtr, int colIndex) =>
      _getColumnName(_dbPtr(dbPtr), colIndex).toDartString();

  @override
  int getColumnType(int dbPtr, int colIndex) =>
      _getColumnType(_dbPtr(dbPtr), colIndex);

  @override
  int getColumnCount(int dbPtr) => _getColumnCount(_dbPtr(dbPtr));

  @override
  String? getLastDbError(int dbPtr) {
    final errorPtr = _getLastDbError(_dbPtr(dbPtr));

    if (errorPtr == nullptr || errorPtr.address == 0) {
      return null;
    }

    return errorPtr.toDartString();
  }

  @override
  int getAffectedRows(int dbPtr) => _getAffectedRows(_dbPtr(dbPtr));

  @override
  int getLastInsertedId(int dbPtr) => _getLastInsertedId(_dbPtr(dbPtr));

  @override
  Future closeReader(int dbPtr) async => _closeReader(_dbPtr(dbPtr));

  @override
  Future closeDb(int dbPtr) async => _closeDb(_dbPtr(dbPtr));
}
