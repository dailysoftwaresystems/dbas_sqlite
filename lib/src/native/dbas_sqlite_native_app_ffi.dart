import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'dbas_sqlite_native_app_base.dart';
import 'dbas_sqlite_row_cache.dart';
import 'dbas_sqlite_isolate_worker.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';

class DbasSqliteNativeApp extends DbasSqliteNativeAppBase {
  late DynamicLibrary _lib;

  // ── Background isolate for heavy operations ────────────────────────────
  SendPort? _workerPort;
  int _nextCmdId = 0;
  final Map<int, Completer<dynamic>> _workerPending = {};
  String? _resolvedLibPath;

  late Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>) _openDb;
  late int Function(Pointer<DbasSqliteDbStruct>) _isOpened;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) _executeSql;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) _prepareQuery;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _bindNull;
  late int Function(Pointer<DbasSqliteDbStruct>, int, int) _bindInt;
  late int Function(Pointer<DbasSqliteDbStruct>, int, double) _bindFloat;
  late int Function(Pointer<DbasSqliteDbStruct>, int, double) _bindDouble;
  late int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>) _bindText;
  late int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Uint8>, int length) _bindBlob;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) _bindNameNull;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, int) _bindNameInt;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double) _bindNameFloat;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double) _bindNameDouble;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>) _bindNameText;
  late int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>, int length) _bindNameBlob;
  late int Function(Pointer<DbasSqliteDbStruct>) _readRow;
  late int Function(Pointer<DbasSqliteDbStruct>, int) _isNullNative;
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

  // ── Connection Pool ──
  late Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, int) _createPool;
  late Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>) _poolGetWriter;
  late Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>) _poolAcquireReader;
  late void Function(Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>) _poolReleaseReader;
  late void Function(Pointer<DbasSqlitePoolStruct>) _closePool;

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
        Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>)>('OpenDb');
    _isOpened = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('IsOpened');
    _executeSql = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>('ExecuteSql');
    _prepareQuery = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>('PrepareQuery');
    _bindNull = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('BindNull');
    _bindInt = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, int)>('BindInt');
    _bindFloat = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Float),
        int Function(Pointer<DbasSqliteDbStruct>, int, double)>('BindFloat');
    _bindDouble = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Double),
        int Function(Pointer<DbasSqliteDbStruct>, int, double)>('BindDouble');
    _bindText = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>)>('BindText');
    _bindBlob = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Pointer<Uint8>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Uint8>, int)>('BindBlob');
    _bindNameNull = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>('BindNameNull');
    _bindNameInt = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, int)>('BindNameInt');
    _bindNameFloat = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Float),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double)>('BindNameFloat');
    _bindNameDouble = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Double),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double)>('BindNameDouble');
    _bindNameText = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>)>('BindNameText');
    _bindNameBlob = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>, int)>('BindNameBlob');
    _readRow = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('ReadRow');
    _isNullNative = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('IsNull');
    _getColumnText = _lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Int32),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnText');
    _getColumnInt = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnInt');
    _getColumnFloat = _lib.lookupFunction<
        Float Function(Pointer<DbasSqliteDbStruct>, Int32),
        double Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnFloat');
    _getColumnDouble = _lib.lookupFunction<
        Double Function(Pointer<DbasSqliteDbStruct>, Int32),
        double Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnDouble');
    _getColumnBlob = _lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, Int32),
        Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnBlob');
    _getColumnBytes = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnBytes');
    _getColumnName = _lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Int32),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnName');
    _getColumnType = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnType');
    _getColumnCount = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('GetColumnCount');
    _getLastDbError = _lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>)>('GetLastDbError');
    _getAffectedRows = _lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('GetAffectedRows');
    _getLastInsertedId = _lib.lookupFunction<
        Int64 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('GetLastInsertedId');
    _closeReader = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>),
        void Function(Pointer<DbasSqliteDbStruct>)>('CloseReader');
    _closeDb = _lib.lookupFunction<
        Void Function(Pointer<DbasSqliteDbStruct>),
        void Function(Pointer<DbasSqliteDbStruct>)>('CloseDb');

    // ── Connection Pool ──
    _createPool = _lib.lookupFunction<
        Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, Int32),
        Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, int)>('CreatePool');
    _poolGetWriter = _lib.lookupFunction<
        Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>),
        Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>)>('PoolGetWriter');
    _poolAcquireReader = _lib.lookupFunction<
        Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>),
        Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>)>('PoolAcquireReader');
    _poolReleaseReader = _lib.lookupFunction<
        Void Function(Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>),
        void Function(Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>)>('PoolReleaseReader');
    _closePool = _lib.lookupFunction<
        Void Function(Pointer<DbasSqlitePoolStruct>),
        void Function(Pointer<DbasSqlitePoolStruct>)>('ClosePool');

    // Spawn background isolate for heavy FFI operations.
    // The worker loads the same DLL independently.
    _resolvedLibPath = (!isTest && (Platform.isIOS || Platform.isMacOS))
        ? '' // process() library — worker handles this internally
        : await getLibraryPath();
    await _spawnWorker(_resolvedLibPath!);
  }

  Future<void> _spawnWorker(String libPath) async {
    final receivePort = ReceivePort();
    final initMsg = WorkerInitMessage(receivePort.sendPort, libPath);

    await Isolate.spawn(isolateWorkerEntryPoint, initMsg);

    final portCompleter = Completer<SendPort>();
    void failAllPending(Object error) {
      for (final pending in _workerPending.values) {
        if (!pending.isCompleted) pending.completeError(error);
      }
      _workerPending.clear();
      _workerPort = null;
    }

    receivePort.listen(
      (message) {
        if (message is SendPort) {
          portCompleter.complete(message);
        } else if (message is IsolateResponse) {
          final pending = _workerPending.remove(message.id);
          if (pending != null) {
            if (message.error != null) {
              pending.completeError(Exception(message.error));
            } else {
              pending.complete(message.result);
            }
          }
        }
      },
      onDone: () {
        failAllPending(StateError('Worker isolate terminated unexpectedly'));
      },
      onError: (error) {
        failAllPending(StateError('Worker isolate stream error: $error'));
      },
    );

    _workerPort = await portCompleter.future;
  }

  Future<dynamic> _sendToWorker(String method, [Map<String, dynamic>? args]) {
    if (_workerPort == null) {
      throw StateError(
        'Cannot send command "$method": worker isolate is not running',
      );
    }
    final id = _nextCmdId++;
    final completer = Completer<dynamic>();
    _workerPending[id] = completer;
    _workerPort!.send(IsolateCommand(id, method, args ?? {}));
    return completer.future;
  }

  // ── Heavy operations offloaded to background isolate ───────────────────

  @override
  Future<int> executeSql(int dbPtr, String sql) async =>
      await _sendToWorker('executeSql', {'dbPtr': dbPtr, 'sql': sql}) as int;

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async {
    final result = await _sendToWorker('prepareQuery', {'dbPtr': dbPtr, 'sql': sql});
    if (result is Map) {
      rowCache.updateFromPrepare(result);
      return toIntSafe(result['rc']);
    }
    return toIntSafe(result);
  }

  @override
  Future<int> readRow(int dbPtr) async {
    final result = await _sendToWorker('readRow', {'dbPtr': dbPtr});
    if (result is Map) {
      rowCache.updateFromReadRow(result);
      return toIntSafe(result['status']);
    }
    return toIntSafe(result);
  }

  @override
  Future<int> openDb(String path) async =>
      await _sendToWorker('openDb', {'path': path}) as int;

  @override
  Future closeReader(int dbPtr) async {
    await _sendToWorker('closeReader', {'dbPtr': dbPtr});
    rowCache.columns = null;
  }

  @override
  Future closeDb(int dbPtr) async {
    await _sendToWorker('closeDb', {'dbPtr': dbPtr});
  }

  // Pool management: createPool/closePool go through the worker isolate
  // (they allocate/free the pool struct). The synchronous pool accessors
  // (poolGetWriter/poolAcquireReader/poolReleaseReader) use main-isolate FFI
  // directly. This is safe because:
  // - createPool is awaited before any acquire/release calls
  // - closePool is awaited after all acquire/release calls complete
  // - acquire/release only touch the readerBusy[] array, which is not
  //   accessed by the worker during SQL operations (executeSql/readRow)
  @override
  Future<int> createPool(String path, int readerCount) async =>
      await _sendToWorker('createPool', {'path': path, 'readerCount': readerCount}) as int;

  @override
  int poolGetWriter(int poolPtr) =>
      nativePoolGetWriter(resolvePoolPtr(poolPtr)).address;

  @override
  int poolAcquireReader(int poolPtr) {
    final reader = nativePoolAcquireReader(resolvePoolPtr(poolPtr));
    if (reader == nullptr || reader.address == 0) return 0;
    return reader.address;
  }

  @override
  void poolReleaseReader(int poolPtr, int readerPtr) =>
      nativePoolReleaseReader(resolvePoolPtr(poolPtr), resolveDbPtr(readerPtr));

  @override
  Future<void> closePool(int poolPtr) async =>
      await _sendToWorker('closePool', {'poolPtr': poolPtr});

  // ── Pointer validation ─────────────────────────────────────────────────
  @override
  Pointer<DbasSqliteDbStruct> resolveDbPtr(int address) {
    if (address <= 0) {
      throw ArgumentError('Invalid database pointer input: $address');
    }

    final result = Pointer<DbasSqliteDbStruct>.fromAddress(address);

    if (result == nullptr || result.address == 0) {
      throw ArgumentError('Invalid database pointer: $address');
    }

    return result;
  }

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
