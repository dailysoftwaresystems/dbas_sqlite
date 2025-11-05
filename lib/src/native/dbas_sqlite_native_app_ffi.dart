import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dbas_sqlite_native_interface.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';

class DbasSqliteNativeApp extends DbasSqliteNativeInterface {
  late DynamicLibrary _lib;

  late Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>) _openDb;
  late int Function(Pointer<DbasSqliteDbStruct>) _isOpened;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) _executeSql;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) _prepareQuery;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _bindNull;
  late int Function(Pointer<DbasSqliteDbStruct>, int, int) _bindInt;
  late int Function(Pointer<DbasSqliteDbStruct>, int, double) _bindFloat;
  late int Function(Pointer<DbasSqliteDbStruct>, int, double) _bindDouble;
  late int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>) _bindText;
  late int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Uint8>) _bindBlob;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) _bindNameNull;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, int) _bindNameInt;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double) _bindNameFloat;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double) _bindNameDouble;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>) _bindNameText;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>) _bindNameBlob;
  late int Function(Pointer<DbasSqliteDbStruct>) _readRow;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _isNull;
  late Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int) _getColumnText;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _getColumnInt;
  late double Function(Pointer<DbasSqliteDbStruct>, int) _getColumnFloat;
  late double Function(Pointer<DbasSqliteDbStruct>, int) _getColumnDouble;
  late Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int) _getColumnBlob;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _getColumnBytes;
  late Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int) _getColumnName;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _getColumnType;
  late int Function(Pointer<DbasSqliteDbStruct>) _getColumnCount;
  late Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>) _getLastDbError;
  late int Function(Pointer<DbasSqliteDbStruct>) _getAffectedRows;
  late int Function(Pointer<DbasSqliteDbStruct>) _getLastInsertedId;
  late void Function(Pointer<DbasSqliteDbStruct>) _closeReader;
  late void Function(Pointer<DbasSqliteDbStruct>) _closeDb;

  DbasSqliteNativeApp(super.dbName);

  @override
  Future<void> initialize() async {
    if (!isTest && (Platform.isIOS || Platform.isMacOS)) {
      _lib = DynamicLibrary.process();
    } else {
      await prepareLibIfNeeded();
      final libPath = await getLibraryPath();
      _lib = DynamicLibrary.open(libPath);
    }

    _openDb = _lib.lookupFunction<
        Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>),
        Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>)
    >('OpenDb');
    _isOpened = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)
    >('IsOpened');
    _executeSql = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)
    >('ExecuteSql');
    _prepareQuery = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)
    >('PrepareQuery');
    _bindNull = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)
    >('BindNull');
    _bindInt = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, int)
    >('BindInt');
    _bindFloat = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Float),
        int Function(Pointer<DbasSqliteDbStruct>, int, double)
    >('BindFloat');
    _bindDouble = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Double),
        int Function(Pointer<DbasSqliteDbStruct>, int, double)
    >('BindDouble');
    _bindText = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>)
    >('BindText');
    _bindBlob = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Pointer<Uint8>),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Uint8>)
    >('BindBlob');
    _bindNameNull = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)
    >('BindNameNull');
    _bindNameInt = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, int)
    >('BindNameInt');
    _bindNameFloat = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Float),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double)
    >('BindNameFloat');
    _bindNameDouble = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Double),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double)
    >('BindNameDouble');
    _bindNameText = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>)
    >('BindNameText');
    _bindNameBlob = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>)
    >('BindNameBlob');
    _readRow = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)
    >('ReadRow');
    _isNull = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)
    >('IsNull');
    _getColumnText = _lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Int32),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)
    >('GetColumnText');
    _getColumnInt = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)
    >('GetColumnInt');
    _getColumnFloat = _lib.lookupFunction<
        Float Function(Pointer<DbasSqliteDbStruct>, Int32),
        double Function(Pointer<DbasSqliteDbStruct>, int)
    >('GetColumnFloat');
    _getColumnDouble = _lib.lookupFunction<
        Double Function(Pointer<DbasSqliteDbStruct>, Int32),
        double Function(Pointer<DbasSqliteDbStruct>, int)
    >('GetColumnDouble');
    _getColumnBlob = _lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, Int32),
        Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int)
    >('GetColumnBlob');
    _getColumnBytes = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)
    >('GetColumnBytes');
    _getColumnName = _lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Int32),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)
    >('GetColumnName');
    _getColumnType = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)
    >('GetColumnType');
    _getColumnCount = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)
    >('GetColumnCount');
    _getLastDbError = _lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>)
    >('GetLastDbError');
    _getAffectedRows = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)
    >('GetAffectedRows');
    _getLastInsertedId = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)
    >('GetLastInsertedId');
    _closeReader = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>),
        void Function(Pointer<DbasSqliteDbStruct>)
    >('CloseReader');
    _closeDb = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>),
        void Function(Pointer<DbasSqliteDbStruct>)
    >('CloseDb');
  }

  @override
  Future<int> openDb(String path) async {
    Pointer<Utf8> pathPtr = nullptr;
    try {
      pathPtr = path.toNativeUtf8();
      final ptr = _openDb(pathPtr);
      return ptr.address;
    } finally {
      if (pathPtr != nullptr) {
        calloc.free(pathPtr);
      }
    }
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

  Pointer<DbasSqliteDbStruct> _dbPtr(int address, { bool checkOpened = true }) {
    if (address <= 0) {
      throw ArgumentError('Invalid database pointer input: $address');
    }

    final result = Pointer<DbasSqliteDbStruct>.fromAddress(address);

    if (result == nullptr || result.address == 0) {
      throw ArgumentError('Invalid database pointer: $address');
    }

    if (checkOpened && _isOpened(result) != 1) {
      throw ArgumentError('Database $address is not opened');
    }

    return result;
  }

  @override
  bool isOpened(int dbPtr) => _isOpened(_dbPtr(dbPtr, checkOpened: false)) == 1;

  @override
  Future<int> executeSql(int dbPtr, String sql) async {
    Pointer<Utf8> sqlPtr = nullptr;
    try {
      sqlPtr = sql.toNativeUtf8();
      final result = _executeSql(_dbPtr(dbPtr), sqlPtr);
      return result;
    } finally {
      if (sqlPtr != nullptr) {
        calloc.free(sqlPtr);
      }
    }
  }

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async {
    Pointer<Utf8> sqlPtr = nullptr;
    try {
      sqlPtr = sql.toNativeUtf8();
      final result = _prepareQuery(_dbPtr(dbPtr), sqlPtr);
      return result;
    } finally {
      if (sqlPtr != nullptr) {
        calloc.free(sqlPtr);
      }
    }
  }

  @override
  int bindNull(int dbPtr, int index) =>
    _bindNull(_dbPtr(dbPtr, checkOpened: false), index);

  @override
  int bindInt(int dbPtr, int index, int value) =>
    _bindInt(_dbPtr(dbPtr, checkOpened: false), index, value);

  @override
  int bindFloat(int dbPtr, int index, double value) =>
    _bindFloat(_dbPtr(dbPtr, checkOpened: false), index, value);

  @override
  int bindDouble(int dbPtr, int index, double value) =>
    _bindDouble(_dbPtr(dbPtr, checkOpened: false), index, value);

  @override
  int bindText(int dbPtr, int index, String value) {
    Pointer<Utf8> valuePtr = nullptr;
    try {
      valuePtr = value.toNativeUtf8();
      return _bindText(_dbPtr(dbPtr, checkOpened: false), index, valuePtr);
    } finally {
      if (valuePtr != nullptr) {
        calloc.free(valuePtr);
      }
    }
  }

  @override
  int bindBlob(int dbPtr, int index, List<int> value) {
    Pointer<Uint8> ptr = nullptr;
    try {
      ptr = calloc<Uint8>(value.length);
      for (var i = 0; i < value.length; i++) {
        ptr[i] = value[i];
      }
      return _bindBlob(_dbPtr(dbPtr, checkOpened: false), index, ptr);
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
    }
  }

  @override
  int bindNameNull(int dbPtr, String name) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return _bindNameNull(_dbPtr(dbPtr, checkOpened: false), namePtr);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int bindNameInt(int dbPtr, String name, int value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return _bindNameInt(_dbPtr(dbPtr, checkOpened: false), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int bindNameFloat(int dbPtr, String name, double value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return _bindNameFloat(_dbPtr(dbPtr, checkOpened: false), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int bindNameDouble(int dbPtr, String name, double value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return _bindNameDouble(_dbPtr(dbPtr, checkOpened: false), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int bindNameText(int dbPtr, String name, String value) {
    Pointer<Utf8> namePtr = nullptr;
    Pointer<Utf8> valuePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      valuePtr = value.toNativeUtf8();
      return _bindNameText(_dbPtr(dbPtr, checkOpened: false), namePtr, valuePtr);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
      if (valuePtr != nullptr) calloc.free(valuePtr);
    }
  }

  @override
  int bindNameBlob(int dbPtr, String name, List<int> value) {
    Pointer<Utf8> namePtr = nullptr;
    Pointer<Uint8> ptr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      ptr = calloc<Uint8>(value.length);
      for (var i = 0; i < value.length; i++) {
        ptr[i] = value[i];
      }
      return _bindNameBlob(_dbPtr(dbPtr, checkOpened: false), namePtr, ptr);
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  Future<int> readRow(int dbPtr) async => _readRow(_dbPtr(dbPtr, checkOpened: false));

  @override
  bool isNull(int dbPtr, int colIndex) => _isNull(_dbPtr(dbPtr, checkOpened: false), colIndex) == 1;

  @override
  String getColumnText(int dbPtr, int colIndex) =>
    _getColumnText(_dbPtr(dbPtr, checkOpened: false), colIndex).toDartString();

  @override
  int getColumnInt(int dbPtr, int colIndex) =>
    _getColumnInt(_dbPtr(dbPtr, checkOpened: false), colIndex);

  @override
  double getColumnFloat(int dbPtr, int colIndex) =>
    _getColumnFloat(_dbPtr(dbPtr, checkOpened: false), colIndex);

  @override
  double getColumnDouble(int dbPtr, int colIndex) =>
    _getColumnDouble(_dbPtr(dbPtr, checkOpened: false), colIndex);

  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) {
    final ptr = _getColumnBlob(_dbPtr(dbPtr, checkOpened: false), columnIndex);
    final length = _getColumnBytes(_dbPtr(dbPtr, checkOpened: false), columnIndex);
    return ptr.asTypedList(length);
  }

  @override
  int getColumnBytes(int dbPtr, int columnIndex) =>
    _getColumnBytes(_dbPtr(dbPtr, checkOpened: false), columnIndex);

  @override
  String getColumnName(int dbPtr, int colIndex) =>
      _getColumnName(_dbPtr(dbPtr, checkOpened: false), colIndex).toDartString();

  @override
  int getColumnType(int dbPtr, int colIndex) =>
    _getColumnType(_dbPtr(dbPtr, checkOpened: false), colIndex);

  @override
  int getColumnCount(int dbPtr) => _getColumnCount(_dbPtr(dbPtr, checkOpened: false));

  @override
  String getLastDbError(int dbPtr) {
    final errorPtr = _getLastDbError(_dbPtr(dbPtr, checkOpened: false));

    if (errorPtr == nullptr || errorPtr.address == 0) {
      return 'No SQLite error found.';
    }

    return errorPtr.toDartString();
  }

  @override
  int getAffectedRows(int dbPtr) => _getAffectedRows(_dbPtr(dbPtr, checkOpened: false));

  @override
  int getLastInsertedId(int dbPtr) => _getLastInsertedId(_dbPtr(dbPtr, checkOpened: false));

  @override
  Future closeReader(int dbPtr) async => _closeReader(_dbPtr(dbPtr, checkOpened: false));

  @override
  Future closeDb(int dbPtr) async => _closeDb(_dbPtr(dbPtr, checkOpened: false));
}
