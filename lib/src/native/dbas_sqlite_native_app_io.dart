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

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Int32)>(symbol: 'BindNull')
  external void _bindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Int32)>(symbol: 'BindInt')
  external void _bindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Float)>(symbol: 'BindFloat')
  external void _bindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Double)>(symbol: 'BindDouble')
  external void _bindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Pointer<Utf8>)>(symbol: 'BindText')
  external void _bindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Int32, Pointer<Uint8>)>(symbol: 'BindBlob')
  external void _bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Uint8> value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>(symbol: 'BindNameNull')
  external void _bindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Int32)>(symbol: 'BindNameInt')
  external void _bindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Float)>(symbol: 'BindNameFloat')
  external void _bindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Double)>(symbol: 'BindNameDouble')
  external void _bindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>)>(symbol: 'BindNameText')
  external void _bindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value);

  @Native<Void Function(Handle, Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>)>(symbol: 'BindNameBlob')
  external void _bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Uint8> value);

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
  Future<int> executeSql(int dbPtr, String sql) async =>
      _executeSql(_dbPtr(dbPtr), sql.toNativeUtf8());

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async =>
      _prepareQuery(_dbPtr(dbPtr), sql.toNativeUtf8());

  @override
  void bindNull(int stmt, int index) =>
      _bindNull(_dbPtr(stmt), index);

  @override
  void bindInt(int stmt, int index, int value) =>
      _bindInt(_dbPtr(stmt), index, value);

  @override
  void bindFloat(int stmt, int index, double value) =>
      _bindFloat(_dbPtr(stmt), index, value);

  @override
  void bindDouble(int stmt, int index, double value) =>
      _bindDouble(_dbPtr(stmt), index, value);

  @override
  void bindText(int stmt, int index, String value) =>
      _bindText(_dbPtr(stmt), index, value.toNativeUtf8());

  @override
  void bindBlob(int stmt, int index, List<int> value) {
    final ptr = calloc<Uint8>(value.length);
    for (var i = 0; i < value.length; i++) {
      ptr[i] = value[i];
    }
    _bindBlob(_dbPtr(stmt), index, ptr);
    calloc.free(ptr);
  }

  @override
  void bindNameNull(int stmt, String name) =>
      _bindNameNull(_dbPtr(stmt), name.toNativeUtf8());

  @override
  void bindNameInt(int stmt, String name, int value) =>
      _bindNameInt(_dbPtr(stmt), name.toNativeUtf8(), value);

  @override
  void bindNameFloat(int stmt, String name, double value) =>
      _bindNameFloat(_dbPtr(stmt), name.toNativeUtf8(), value);

  @override
  void bindNameDouble(int stmt, String name, double value) =>
      _bindNameDouble(_dbPtr(stmt), name.toNativeUtf8(), value);

  @override
  void bindNameText(int stmt, String name, String value) =>
      _bindNameText(_dbPtr(stmt), name.toNativeUtf8(), value.toNativeUtf8());

  @override
  void bindNameBlob(int stmt, String name, List<int> value) {
    final namePtr = name.toNativeUtf8();
    final ptr = calloc<Uint8>(value.length);
    for (var i = 0; i < value.length; i++) {
      ptr[i] = value[i];
    }
    _bindNameBlob(_dbPtr(stmt), namePtr, ptr);
    calloc.free(ptr);
    calloc.free(namePtr);
  }

  @override
  Future<int> readRow(int stmt) async => _readRow(_dbPtr(stmt));

  @override
  bool isNull(int stmt, int colIndex) => _isNull(_dbPtr(stmt), colIndex) == 1;

  @override
  String getColumnText(int stmt, int colIndex) =>
      _getColumnText(_dbPtr(stmt), colIndex).toDartString();

  @override
  int getColumnInt(int stmt, int colIndex) =>
      _getColumnInt(_dbPtr(stmt), colIndex);

  @override
  double getColumnFloat(int stmt, int colIndex) =>
      _getColumnFloat(_dbPtr(stmt), colIndex);

  @override
  double getColumnDouble(int stmt, int colIndex) =>
      _getColumnDouble(_dbPtr(stmt), colIndex);

  @override
  List<int> getColumnBlob(int stmt, int columnIndex) {
    final ptr = _getColumnBlob(_dbPtr(stmt), columnIndex);
    final length = _getColumnBytes(_dbPtr(stmt), columnIndex);
    return ptr.asTypedList(length);
  }

  @override
  int getColumnBytes(int stmt, int columnIndex) =>
      _getColumnBytes(_dbPtr(stmt), columnIndex);

  @override
  String getColumnName(int stmt, int colIndex) =>
      _getColumnName(_dbPtr(stmt), colIndex).toDartString();

  @override
  int getColumnType(int stmt, int colIndex) =>
      _getColumnType(_dbPtr(stmt), colIndex);

  @override
  int getColumnCount(int stmt) => _getColumnCount(_dbPtr(stmt));

  @override
  String getLastDbError(int dbPtr) =>
      _getLastDbError(_dbPtr(dbPtr)).toDartString();

  @override
  int getAffectedRows(int dbPtr) => _getAffectedRows(_dbPtr(dbPtr));

  @override
  int getLastInsertedId(int dbPtr) => _getLastInsertedId(_dbPtr(dbPtr));

  @override
  Future closeReader(int stmt) async => _closeReader(_dbPtr(stmt));

  @override
  Future closeDb(int dbPtr) async => _closeDb(_dbPtr(dbPtr));
}
