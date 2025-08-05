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
  late void Function(Pointer<DbasSqliteDbStruct>, int) _bindNull;
  late void Function(Pointer<DbasSqliteDbStruct>, int, int) _bindInt;
  late void Function(Pointer<DbasSqliteDbStruct>, int, double) _bindFloat;
  late void Function(Pointer<DbasSqliteDbStruct>, int, double) _bindDouble;
  late void Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>) _bindText;
  late void Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Uint8>) _bindBlob;
  late void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) _bindNameNull;
  late void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, int) _bindNameInt;
  late void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double) _bindNameFloat;
  late void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double) _bindNameDouble;
  late void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>) _bindNameText;
  late void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>) _bindNameBlob;
  late int Function(Pointer<DbasSqliteDbStruct>) _readRow;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _isNull;
  late Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int) _getColumnText;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _getColumnInt;
  late double Function(Pointer<DbasSqliteDbStruct>, int) _getColumnFloat;
  late double Function(Pointer<DbasSqliteDbStruct>, int) _getColumnDouble;
  late Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int) _getColumnBlob;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _getColumnBytes;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _getColumnType;
  late int Function(Pointer<DbasSqliteDbStruct>) _getColumnCount;
  late Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>) _getLastDbError;
  late int Function(Pointer<DbasSqliteDbStruct>) _getAffectedRows;
  late int Function(Pointer<DbasSqliteDbStruct>) _getLastInsertedId;
  late void Function(Pointer<DbasSqliteDbStruct>) _closeReader;
  late void Function(Pointer<DbasSqliteDbStruct>) _closeDb;

  @override
  Future<void> initialize() async {
    if (Platform.isIOS || Platform.isMacOS) {
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
        Void Function(Pointer<DbasSqliteDbStruct>, Int32),
        void Function(Pointer<DbasSqliteDbStruct>, int)
    >('BindNull');
    _bindInt = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Int32, Int32),
        void Function(Pointer<DbasSqliteDbStruct>, int, int)
    >('BindInt');
    _bindFloat = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Int32, Float),
        void Function(Pointer<DbasSqliteDbStruct>, int, double)
    >('BindFloat');
    _bindDouble = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Int32, Double),
        void Function(Pointer<DbasSqliteDbStruct>, int, double)
    >('BindDouble');
    _bindText = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Int32, Pointer<Utf8>),
        void Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>)
    >('BindText');
    _bindBlob = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Int32, Pointer<Uint8>),
        void Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Uint8>)
    >('BindBlob');
    _bindNameNull = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)
    >('BindNameNull');
    _bindNameInt = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Int32),
        void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, int)
    >('BindNameInt');
    _bindNameFloat = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Float),
        void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double)
    >('BindNameFloat');
    _bindNameDouble = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Double),
        void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double)
    >('BindNameDouble');
    _bindNameText = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>),
        void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>)
    >('BindNameText');
    _bindNameBlob = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>),
        void Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>)
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
  int openDb(String path) {
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

  Pointer<DbasSqliteDbStruct> _dbPtr(int address) {
    if (address <= 0) {
      throw ArgumentError('Invalid database pointer input: $address');
    }

    final result = Pointer<DbasSqliteDbStruct>.fromAddress(address);

    if (result == nullptr || result.address == 0) {
      throw ArgumentError('Invalid database pointer: $address');
    }

    if (_isOpened(result) != 1) {
      throw ArgumentError('Database $address is not opened');
    }

    return result;
  }

  @override
  bool isOpened(int dbPtr) => _isOpened(_dbPtr(dbPtr)) == 1;

  @override
  int executeSql(int dbPtr, String sql) {
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
  int prepareQuery(int dbPtr, String sql) {
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
  void bindText(int stmt, int index, String value) {
    Pointer<Utf8> valuePtr = nullptr;
    try {
      valuePtr = value.toNativeUtf8();
      _bindText(_dbPtr(stmt), index, valuePtr);
    } finally {
      if (valuePtr != nullptr) {
        calloc.free(valuePtr);
      }
    }
  }

  @override
  void bindBlob(int stmt, int index, List<int> value) {
    Pointer<Uint8> ptr = nullptr;
    try {
      ptr = calloc<Uint8>(value.length);
      for (var i = 0; i < value.length; i++) {
        ptr[i] = value[i];
      }
      _bindBlob(_dbPtr(stmt), index, ptr);
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
    }
  }

  @override
  void bindNameNull(int stmt, String name) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      _bindNameNull(_dbPtr(stmt), namePtr);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  void bindNameInt(int stmt, String name, int value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      _bindNameInt(_dbPtr(stmt), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  void bindNameFloat(int stmt, String name, double value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      _bindNameFloat(_dbPtr(stmt), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  void bindNameDouble(int stmt, String name, double value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      _bindNameDouble(_dbPtr(stmt), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  void bindNameText(int stmt, String name, String value) {
    Pointer<Utf8> namePtr = nullptr;
    Pointer<Utf8> valuePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      valuePtr = value.toNativeUtf8();
      _bindNameText(_dbPtr(stmt), namePtr, valuePtr);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
      if (valuePtr != nullptr) calloc.free(valuePtr);
    }
  }

  @override
  void bindNameBlob(int stmt, String name, List<int> value) {
    Pointer<Utf8> namePtr = nullptr;
    Pointer<Uint8> ptr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      ptr = calloc<Uint8>(value.length);
      for (var i = 0; i < value.length; i++) {
        ptr[i] = value[i];
      }
      _bindNameBlob(_dbPtr(stmt), namePtr, ptr);
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int readRow(int stmt) => _readRow(_dbPtr(stmt));

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
  int getColumnType(int stmt, int colIndex) =>
    _getColumnType(_dbPtr(stmt), colIndex);

  @override
  int getColumnCount(int stmt) => _getColumnCount(_dbPtr(stmt));

  @override
  String getLastDbError(int dbPtr) {
    final errorPtr = _getLastDbError(_dbPtr(dbPtr));

    if (errorPtr == nullptr || errorPtr.address == 0) {
      return 'No SQLite error found.';
    }

    return errorPtr.toDartString();
  }

  @override
  int getAffectedRows(int dbPtr) => _getAffectedRows(_dbPtr(dbPtr));

  @override
  int getLastInsertedId(int dbPtr) => _getLastInsertedId(_dbPtr(dbPtr));

  @override
  void closeReader(int stmt) => _closeReader(_dbPtr(stmt));

  @override
  void closeDb(int dbPtr) => _closeDb(_dbPtr(dbPtr));
}