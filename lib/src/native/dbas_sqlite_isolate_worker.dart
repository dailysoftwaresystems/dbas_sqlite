import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';

/// Message sent to initialize the worker isolate.
class WorkerInitMessage {
  final SendPort sendPort;
  final String libPath;

  WorkerInitMessage(this.sendPort, this.libPath);
}

/// Command sent from the proxy to the worker.
class IsolateCommand {
  final int id;
  final String method;
  final Map<String, dynamic> args;

  IsolateCommand(this.id, this.method, this.args);
}

/// Response sent from the worker back to the proxy.
class IsolateResponse {
  final int id;
  final dynamic result;
  final String? error;

  IsolateResponse(this.id, this.result, this.error);
}

/// The background isolate entry point.
///
/// Loads the native library, binds all FFI functions, and enters an event loop
/// processing [IsolateCommand] messages from the proxy.
void isolateWorkerEntryPoint(WorkerInitMessage init) {
  final DynamicLibrary lib;
  if (!_isTest() && (Platform.isIOS || Platform.isMacOS)) {
    lib = DynamicLibrary.process();
  } else {
    lib = DynamicLibrary.open(init.libPath);
  }

  // Bind all FFI functions
  final ffi = _WorkerFfi(lib);

  final receivePort = ReceivePort();
  init.sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is IsolateCommand) {
      try {
        final result = _dispatch(ffi, message);
        init.sendPort.send(IsolateResponse(message.id, result, null));
      } catch (e) {
        init.sendPort.send(IsolateResponse(message.id, null, e.toString()));
      }
    } else if (message == 'shutdown') {
      receivePort.close();
    }
  });
}

bool _isTest() {
  return Platform.environment.containsKey('FLUTTER_TEST') ||
      Platform.environment.containsKey('DART_TEST');
}

Pointer<DbasSqlitePoolStruct> _resolvePool(int address) {
  if (address <= 0) throw ArgumentError('Invalid pool pointer: $address');
  return Pointer<DbasSqlitePoolStruct>.fromAddress(address);
}

dynamic _dispatch(_WorkerFfi ffi, IsolateCommand cmd) {
  final args = cmd.args;

  switch (cmd.method) {
    case 'openDb':
      return _handleOpenDb(ffi, args['path'] as String);

    case 'isOpened':
      return ffi.isOpened(_resolveDb(args['dbPtr'] as int)) == 1;

    case 'executeSql':
      return _handleExecuteSql(ffi, args['dbPtr'] as int, args['sql'] as String);

    case 'prepareQuery':
      return _handlePrepareQuery(ffi, args['dbPtr'] as int, args['sql'] as String);

    case 'readRow':
      return _handleReadRow(ffi, args['dbPtr'] as int);

    case 'bindNull':
      return ffi.bindNull(_resolveDb(args['dbPtr'] as int), args['index'] as int);
    case 'bindInt':
      return ffi.bindInt(_resolveDb(args['dbPtr'] as int), args['index'] as int, args['value'] as int);
    case 'bindFloat':
      return ffi.bindFloat(_resolveDb(args['dbPtr'] as int), args['index'] as int, (args['value'] as num).toDouble());
    case 'bindDouble':
      return ffi.bindDouble(_resolveDb(args['dbPtr'] as int), args['index'] as int, (args['value'] as num).toDouble());
    case 'bindText':
      return _handleBindText(ffi, args['dbPtr'] as int, args['index'] as int, args['value'] as String);
    case 'bindBlob':
      return _handleBindBlob(ffi, args['dbPtr'] as int, args['index'] as int, args['value'] as List<int>);

    case 'bindNameNull':
      return _handleBindNameNull(ffi, args['dbPtr'] as int, args['name'] as String);
    case 'bindNameInt':
      return _handleBindNameInt(ffi, args['dbPtr'] as int, args['name'] as String, args['value'] as int);
    case 'bindNameFloat':
      return _handleBindNameFloat(ffi, args['dbPtr'] as int, args['name'] as String, (args['value'] as num).toDouble());
    case 'bindNameDouble':
      return _handleBindNameDouble(ffi, args['dbPtr'] as int, args['name'] as String, (args['value'] as num).toDouble());
    case 'bindNameText':
      return _handleBindNameText(ffi, args['dbPtr'] as int, args['name'] as String, args['value'] as String);
    case 'bindNameBlob':
      return _handleBindNameBlob(ffi, args['dbPtr'] as int, args['name'] as String, args['value'] as List<int>);

    case 'closeReader':
      ffi.closeReader(_resolveDb(args['dbPtr'] as int));
      return null;

    case 'closeDb':
      ffi.closeDb(_resolveDb(args['dbPtr'] as int));
      return null;

    case 'getLastDbError':
      final errorPtr = ffi.getLastDbError(_resolveDb(args['dbPtr'] as int));
      if (errorPtr == nullptr || errorPtr.address == 0) return null;
      return errorPtr.toDartString();

    case 'getAffectedRows':
      return ffi.getAffectedRows(_resolveDb(args['dbPtr'] as int));

    case 'getLastInsertedId':
      return ffi.getLastInsertedId(_resolveDb(args['dbPtr'] as int));

    // ── Connection Pool (C-managed) ──
    case 'createPool':
      return _handleCreatePool(ffi, args['path'] as String, args['readerCount'] as int);

    case 'poolGetWriter':
      return ffi.poolGetWriter(_resolvePool(args['poolPtr'] as int)).address;

    case 'poolAcquireReader':
      final reader = ffi.poolAcquireReader(_resolvePool(args['poolPtr'] as int));
      return (reader == nullptr || reader.address == 0) ? 0 : reader.address;

    case 'poolReleaseReader':
      ffi.poolReleaseReader(
        _resolvePool(args['poolPtr'] as int),
        _resolveDb(args['readerPtr'] as int),
      );
      return null;

    case 'closePool':
      ffi.closePool(_resolvePool(args['poolPtr'] as int));
      return null;

    default:
      throw StateError('Unknown worker command: ${cmd.method}');
  }
}

Pointer<DbasSqliteDbStruct> _resolveDb(int address) {
  if (address <= 0) throw ArgumentError('Invalid database pointer: $address');
  return Pointer<DbasSqliteDbStruct>.fromAddress(address);
}

int _handleOpenDb(_WorkerFfi ffi, String path) {
  Pointer<Utf8> pathPtr = nullptr;
  try {
    pathPtr = path.toNativeUtf8();
    final ptr = ffi.openDb(pathPtr);
    if (ptr == nullptr || ptr.address == 0) {
      throw Exception('Failed to open database: $path');
    }
    return ptr.address;
  } finally {
    if (pathPtr != nullptr) calloc.free(pathPtr);
  }
}

int _handleExecuteSql(_WorkerFfi ffi, int dbPtr, String sql) {
  Pointer<Utf8> sqlPtr = nullptr;
  try {
    sqlPtr = sql.toNativeUtf8();
    return ffi.executeSql(_resolveDb(dbPtr), sqlPtr);
  } finally {
    if (sqlPtr != nullptr) calloc.free(sqlPtr);
  }
}

Map<String, dynamic> _handlePrepareQuery(_WorkerFfi ffi, int dbPtr, String sql) {
  final ptr = _resolveDb(dbPtr);
  Pointer<Utf8> sqlPtr = nullptr;
  try {
    sqlPtr = sql.toNativeUtf8();
    final rc = ffi.prepareQuery(ptr, sqlPtr);
    final count = rc == 0 ? ffi.getColumnCount(ptr) : 0;
    final names = <String>[];
    for (int i = 0; i < count; i++) {
      names.add(ffi.getColumnName(ptr, i).toDartString());
    }
    final errorPtr = ffi.getLastDbError(ptr);
    final error = (errorPtr == nullptr || errorPtr.address == 0) ? null : errorPtr.toDartString();
    return {
      'rc': rc,
      'columnCount': count,
      'columnNames': names,
      'lastError': error,
    };
  } finally {
    if (sqlPtr != nullptr) calloc.free(sqlPtr);
  }
}

Map<String, dynamic> _handleReadRow(_WorkerFfi ffi, int dbPtr) {
  final ptr = _resolveDb(dbPtr);
  final status = ffi.readRow(ptr);

  const sqliteRow = 100;
  List<Map<String, dynamic>>? columns;

  if (status == sqliteRow) {
    final count = ffi.getColumnCount(ptr);
    columns = [];
    for (int i = 0; i < count; i++) {
      final type = ffi.getColumnType(ptr, i);
      final isNull = ffi.isNull(ptr, i) == 1;
      dynamic value;
      if (!isNull) {
        switch (type) {
          case 1: // SQLITE_INTEGER
            value = ffi.getColumnInt(ptr, i);
          case 2: // SQLITE_FLOAT
            value = ffi.getColumnDouble(ptr, i);
          case 3: // SQLITE_TEXT
            value = ffi.getColumnText(ptr, i).toDartString();
          case 4: // SQLITE_BLOB
            final blobPtr = ffi.getColumnBlob(ptr, i);
            final length = ffi.getColumnBytes(ptr, i);
            value = blobPtr.asTypedList(length).toList();
        }
      }
      columns.add({'type': type, 'isNull': isNull, 'value': value});
    }
  }

  final errorPtr = ffi.getLastDbError(ptr);
  return {
    'status': status,
    'columnCount': ffi.getColumnCount(ptr),
    'columns': columns,
    'affectedRows': ffi.getAffectedRows(ptr),
    'lastInsertedId': ffi.getLastInsertedId(ptr),
    'lastError': (errorPtr == nullptr || errorPtr.address == 0) ? null : errorPtr.toDartString(),
  };
}

int _handleBindText(_WorkerFfi ffi, int dbPtr, int index, String value) {
  Pointer<Utf8> valuePtr = nullptr;
  try {
    valuePtr = value.toNativeUtf8();
    return ffi.bindText(_resolveDb(dbPtr), index, valuePtr);
  } finally {
    if (valuePtr != nullptr) calloc.free(valuePtr);
  }
}

int _handleBindBlob(_WorkerFfi ffi, int dbPtr, int index, List<int> value) {
  Pointer<Uint8> ptr = nullptr;
  try {
    ptr = calloc<Uint8>(value.length);
    for (var i = 0; i < value.length; i++) {
      ptr[i] = value[i];
    }
    return ffi.bindBlob(_resolveDb(dbPtr), index, ptr, value.length);
  } finally {
    if (ptr != nullptr) calloc.free(ptr);
  }
}

int _handleBindNameNull(_WorkerFfi ffi, int dbPtr, String name) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameNull(_resolveDb(dbPtr), namePtr);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameInt(_WorkerFfi ffi, int dbPtr, String name, int value) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameInt(_resolveDb(dbPtr), namePtr, value);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameFloat(_WorkerFfi ffi, int dbPtr, String name, double value) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameFloat(_resolveDb(dbPtr), namePtr, value);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameDouble(_WorkerFfi ffi, int dbPtr, String name, double value) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameDouble(_resolveDb(dbPtr), namePtr, value);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameText(_WorkerFfi ffi, int dbPtr, String name, String value) {
  Pointer<Utf8> namePtr = nullptr;
  Pointer<Utf8> valuePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    valuePtr = value.toNativeUtf8();
    return ffi.bindNameText(_resolveDb(dbPtr), namePtr, valuePtr);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
    if (valuePtr != nullptr) calloc.free(valuePtr);
  }
}

int _handleBindNameBlob(_WorkerFfi ffi, int dbPtr, String name, List<int> value) {
  Pointer<Utf8> namePtr = nullptr;
  Pointer<Uint8> ptr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    ptr = calloc<Uint8>(value.length);
    for (var i = 0; i < value.length; i++) {
      ptr[i] = value[i];
    }
    return ffi.bindNameBlob(_resolveDb(dbPtr), namePtr, ptr, value.length);
  } finally {
    if (ptr != nullptr) calloc.free(ptr);
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleCreatePool(_WorkerFfi ffi, String path, int readerCount) {
  Pointer<Utf8> pathPtr = nullptr;
  try {
    pathPtr = path.toNativeUtf8();
    final poolPtr = ffi.createPool(pathPtr, readerCount);
    if (poolPtr == nullptr || poolPtr.address == 0) {
      throw Exception('Failed to create pool: $path');
    }
    return poolPtr.address;
  } finally {
    if (pathPtr != nullptr) calloc.free(pathPtr);
  }
}

/// All FFI function pointers loaded from the dynamic library.
class _WorkerFfi {
  late final Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>) openDb;
  late final int Function(Pointer<DbasSqliteDbStruct>) isOpened;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) executeSql;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) prepareQuery;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) bindNull;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) bindInt;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, double) bindFloat;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, double) bindDouble;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>) bindText;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Uint8>, int) bindBlob;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) bindNameNull;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, int) bindNameInt;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double) bindNameFloat;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double) bindNameDouble;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>) bindNameText;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>, int) bindNameBlob;
  late final int Function(Pointer<DbasSqliteDbStruct>) readRow;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) isNull;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int) getColumnText;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getColumnInt;
  late final double Function(Pointer<DbasSqliteDbStruct>, int) getColumnFloat;
  late final double Function(Pointer<DbasSqliteDbStruct>, int) getColumnDouble;
  late final Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int) getColumnBlob;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getColumnBytes;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int) getColumnName;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getColumnType;
  late final int Function(Pointer<DbasSqliteDbStruct>) getColumnCount;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>) getLastDbError;
  late final int Function(Pointer<DbasSqliteDbStruct>) getAffectedRows;
  late final int Function(Pointer<DbasSqliteDbStruct>) getLastInsertedId;
  late final void Function(Pointer<DbasSqliteDbStruct>) closeReader;
  late final void Function(Pointer<DbasSqliteDbStruct>) closeDb;

  // ── Connection Pool ──
  late final Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, int) createPool;
  late final Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>) poolGetWriter;
  late final Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>) poolAcquireReader;
  late final void Function(Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>) poolReleaseReader;
  late final void Function(Pointer<DbasSqlitePoolStruct>) closePool;

  _WorkerFfi(DynamicLibrary lib) {
    openDb = lib.lookupFunction<Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>), Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>)>('OpenDb');
    isOpened = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>), int Function(Pointer<DbasSqliteDbStruct>)>('IsOpened');
    executeSql = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>), int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>('ExecuteSql');
    prepareQuery = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>), int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>('PrepareQuery');
    bindNull = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32), int Function(Pointer<DbasSqliteDbStruct>, int)>('BindNull');
    bindInt = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Int32), int Function(Pointer<DbasSqliteDbStruct>, int, int)>('BindInt');
    bindFloat = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Float), int Function(Pointer<DbasSqliteDbStruct>, int, double)>('BindFloat');
    bindDouble = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Double), int Function(Pointer<DbasSqliteDbStruct>, int, double)>('BindDouble');
    bindText = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Pointer<Utf8>), int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>)>('BindText');
    bindBlob = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32, Pointer<Uint8>, Int32), int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Uint8>, int)>('BindBlob');
    bindNameNull = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>), int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>('BindNameNull');
    bindNameInt = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Int32), int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, int)>('BindNameInt');
    bindNameFloat = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Float), int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double)>('BindNameFloat');
    bindNameDouble = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Double), int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, double)>('BindNameDouble');
    bindNameText = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>), int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Utf8>)>('BindNameText');
    bindNameBlob = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>, Int32), int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>, Pointer<Uint8>, int)>('BindNameBlob');
    readRow = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>), int Function(Pointer<DbasSqliteDbStruct>)>('ReadRow');
    isNull = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32), int Function(Pointer<DbasSqliteDbStruct>, int)>('IsNull');
    getColumnText = lib.lookupFunction<Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Int32), Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnText');
    getColumnInt = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32), int Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnInt');
    getColumnFloat = lib.lookupFunction<Float Function(Pointer<DbasSqliteDbStruct>, Int32), double Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnFloat');
    getColumnDouble = lib.lookupFunction<Double Function(Pointer<DbasSqliteDbStruct>, Int32), double Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnDouble');
    getColumnBlob = lib.lookupFunction<Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, Int32), Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnBlob');
    getColumnBytes = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32), int Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnBytes');
    getColumnName = lib.lookupFunction<Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Int32), Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnName');
    getColumnType = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>, Int32), int Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnType');
    getColumnCount = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>), int Function(Pointer<DbasSqliteDbStruct>)>('GetColumnCount');
    getLastDbError = lib.lookupFunction<Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>), Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>)>('GetLastDbError');
    getAffectedRows = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>), int Function(Pointer<DbasSqliteDbStruct>)>('GetAffectedRows');
    getLastInsertedId = lib.lookupFunction<Int64 Function(Pointer<DbasSqliteDbStruct>), int Function(Pointer<DbasSqliteDbStruct>)>('GetLastInsertedId');
    closeReader = lib.lookupFunction<Void Function(Pointer<DbasSqliteDbStruct>), void Function(Pointer<DbasSqliteDbStruct>)>('CloseReader');
    closeDb = lib.lookupFunction<Void Function(Pointer<DbasSqliteDbStruct>), void Function(Pointer<DbasSqliteDbStruct>)>('CloseDb');

    // ── Connection Pool ──
    createPool = lib.lookupFunction<Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, Int32), Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, int)>('CreatePool');
    poolGetWriter = lib.lookupFunction<Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>), Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>)>('PoolGetWriter');
    poolAcquireReader = lib.lookupFunction<Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>), Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>)>('PoolAcquireReader');
    poolReleaseReader = lib.lookupFunction<Void Function(Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>), void Function(Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>)>('PoolReleaseReader');
    closePool = lib.lookupFunction<Void Function(Pointer<DbasSqlitePoolStruct>), void Function(Pointer<DbasSqlitePoolStruct>)>('ClosePool');
  }
}
