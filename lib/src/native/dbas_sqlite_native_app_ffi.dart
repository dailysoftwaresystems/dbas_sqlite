import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dbas_sqlite_native_interface.dart';
import '../dbas_sqlite_db.dart';

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
  Pointer<DbasSqliteDbStruct> openDb(Pointer<Utf8> path) => _openDb(path);

  @override
  bool isOpened(Pointer<DbasSqliteDbStruct> dbPtr) => _isOpened(dbPtr) == 1;

  @override
  int executeSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) => _executeSql(dbPtr, sql);

  @override
  int prepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) => _prepareQuery(dbPtr, sql);

  @override
  void bindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index) => _bindNull(dbPtr, index);

  @override
  void bindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value) => _bindInt(dbPtr, index, value);

  @override
  void bindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value) => _bindFloat(dbPtr, index, value);

  @override
  void bindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value) => _bindDouble(dbPtr, index, value);

  @override
  void bindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value) => _bindText(dbPtr, index, value);

  @override
  void bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Uint8> value) => _bindBlob(dbPtr, index, value);

  @override
  void bindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name) => _bindNameNull(dbPtr, name);

  @override
  void bindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value) => _bindNameInt(dbPtr, name, value);

  @override
  void bindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value) => _bindNameFloat(dbPtr, name, value);

  @override
  void bindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value) => _bindNameDouble(dbPtr, name, value);

  @override
  void bindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value) => _bindNameText(dbPtr, name, value);

  @override
  void bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Uint8> value) => _bindNameBlob(dbPtr, name, value);

  @override
  int readRow(Pointer<DbasSqliteDbStruct> dbPtr) => _readRow(dbPtr);

  @override
  int isNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _isNull(dbPtr, colIndex);

  @override
  Pointer<Utf8> getColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnText(dbPtr, colIndex);

  @override
  int getColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnInt(dbPtr, colIndex);

  @override
  double getColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnFloat(dbPtr, colIndex);

  @override
  double getColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnDouble(dbPtr, colIndex);

  @override
  Pointer<Uint8> getColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) => _getColumnBlob(dbPtr, columnIndex);

  @override
  int getColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex) => _getColumnBytes(dbPtr, columnIndex);

  @override
  int getColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex) => _getColumnType(dbPtr, colIndex);

  @override
  int getColumnCount(Pointer<DbasSqliteDbStruct> dbPtr) => _getColumnCount(dbPtr);

  @override
  Pointer<Utf8> getLastDbError(Pointer<DbasSqliteDbStruct> dbPtr) => _getLastDbError(dbPtr);

  @override
  int getAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr) => _getAffectedRows(dbPtr);

  @override
  int getLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr) => _getLastInsertedId(dbPtr);

  @override
  void closeReader(Pointer<DbasSqliteDbStruct> dbPtr) => _closeReader(dbPtr);

  @override
  void closeDb(Pointer<DbasSqliteDbStruct> dbPtr) => _closeDb(dbPtr);
}