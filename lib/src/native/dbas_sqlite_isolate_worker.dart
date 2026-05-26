import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_db.dart';

/// Init message sent to a worker isolate at spawn time.
class WorkerInitMessage {
  final SendPort sendPort;
  final String libPath;
  WorkerInitMessage(this.sendPort, this.libPath);
}

/// Command sent from main → worker. Each command has a unique [id]
/// the main isolate uses to correlate the [IsolateResponse].
class IsolateCommand {
  final int id;
  final String method;
  final Map<String, dynamic> args;
  IsolateCommand(this.id, this.method, this.args);
}

/// Response sent worker → main. Either [result] or [error] is set.
class IsolateResponse {
  final int id;
  final dynamic result;
  final String? error;
  IsolateResponse(this.id, this.result, this.error);
}

/// Background isolate entry point — loads the native library, binds
/// every FFI function, and serves [IsolateCommand]s via [_dispatch].
void isolateWorkerEntryPoint(WorkerInitMessage init) {
  final DynamicLibrary lib;
  if (!_isTest() && (Platform.isIOS || Platform.isMacOS)) {
    lib = DynamicLibrary.process();
  } else {
    lib = DynamicLibrary.open(init.libPath);
  }

  final ffi = _WorkerFfi(lib);
  final receivePort = ReceivePort();
  init.sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is IsolateCommand) {
      try {
        final result = _dispatch(ffi, message);
        init.sendPort.send(IsolateResponse(message.id, result, null));
      } catch (e, st) {
        // Preserve the stack trace by appending it to the error
        // string. The main-isolate side reconstructs the message
        // verbatim into an Exception; without the stack the original
        // frames (which bind / step / column accessor failed) are
        // gone. Keeping it as a string avoids serialising a Dart
        // StackTrace object through the SendPort.
        init.sendPort.send(IsolateResponse(message.id, null, '$e\n$st'));
      }
    } else if (message == 'shutdown') {
      receivePort.close();
    }
  });
}

bool _isTest() =>
    Platform.environment.containsKey('FLUTTER_TEST') ||
    Platform.environment.containsKey('DART_TEST');

Pointer<DbasSqliteDbStruct> _resolveDb(int address) {
  if (address <= 0) throw ArgumentError('Invalid database pointer: $address');
  return Pointer<DbasSqliteDbStruct>.fromAddress(address);
}

Pointer<DbasSqlitePoolStruct> _resolvePool(int address) {
  if (address <= 0) throw ArgumentError('Invalid pool pointer: $address');
  return Pointer<DbasSqlitePoolStruct>.fromAddress(address);
}

dynamic _dispatch(_WorkerFfi ffi, IsolateCommand cmd) {
  final args = cmd.args;
  switch (cmd.method) {
    // ── Lifecycle ────────────────────────────────────────────────────
    case 'openDb':
      return _handleOpenDb(ffi, args['path'] as String);

    case 'isOpened':
      return ffi.isOpened(_resolveDb(args['dbPtr'] as int)) == 1;

    case 'executeSql':
      return _handleExecuteSql(ffi, args['dbPtr'] as int, args['sql'] as String);

    case 'closeDb':
      return ffi.closeDb(
          _resolveDb(args['dbPtr'] as int), args['checkpoint'] as int? ?? 0);

    case 'getLastDbError':
      final ptr = ffi.getLastDbError(_resolveDb(args['dbPtr'] as int));
      return (ptr == nullptr || ptr.address == 0) ? null : ptr.toDartString();

    case 'getExtendedErrorCode':
      return ffi.getExtendedErrorCode(_resolveDb(args['dbPtr'] as int));

    case 'getAffectedRows':
      return ffi.getAffectedRows(_resolveDb(args['dbPtr'] as int));
    case 'getLastInsertedId':
      return ffi.getLastInsertedId(_resolveDb(args['dbPtr'] as int));
    case 'getTotalChanges':
      return ffi.getTotalChanges(_resolveDb(args['dbPtr'] as int));
    case 'getDbFileName':
      final ptr = ffi.getDbFileName(_resolveDb(args['dbPtr'] as int));
      return (ptr == nullptr || ptr.address == 0) ? null : ptr.toDartString();

    case 'setBusyTimeout':
      return ffi.setBusyTimeout(
          _resolveDb(args['dbPtr'] as int), args['ms'] as int);
    case 'enableWal':
      return ffi.enableWal(_resolveDb(args['dbPtr'] as int));

    // ── Statement ────────────────────────────────────────────────────
    case 'prepareQuery':
      return _handlePrepareQuery(
          ffi, args['dbPtr'] as int, args['sql'] as String);

    case 'finalizeStmt':
      return ffi.finalizeStmt(
          _resolveDb(args['dbPtr'] as int), args['handle'] as int);

    case 'readRowAndCache':
      return _handleReadRow(
          ffi, args['dbPtr'] as int, args['handle'] as int);

    case 'getLastStmtError':
      final ptr = ffi.getLastStmtError(
          _resolveDb(args['dbPtr'] as int), args['handle'] as int);
      return (ptr == nullptr || ptr.address == 0) ? null : ptr.toDartString();

    case 'getStmtAffectedRows':
      return ffi.getStmtAffectedRows(
          _resolveDb(args['dbPtr'] as int), args['handle'] as int);
    case 'getStmtLastInsertedId':
      return ffi.getStmtLastInsertedId(
          _resolveDb(args['dbPtr'] as int), args['handle'] as int);

    // ── Bindings (positional) ────────────────────────────────────────
    case 'bindNull':
      return ffi.bindNull(_resolveDb(args['dbPtr'] as int),
          args['handle'] as int, args['index'] as int);
    case 'bindInt':
      return ffi.bindInt(_resolveDb(args['dbPtr'] as int),
          args['handle'] as int, args['index'] as int, args['value'] as int);
    case 'bindInt64':
      return ffi.bindInt64(_resolveDb(args['dbPtr'] as int),
          args['handle'] as int, args['index'] as int, args['value'] as int);
    case 'bindFloat':
      return ffi.bindFloat(
          _resolveDb(args['dbPtr'] as int),
          args['handle'] as int,
          args['index'] as int,
          (args['value'] as num).toDouble());
    case 'bindDouble':
      return ffi.bindDouble(
          _resolveDb(args['dbPtr'] as int),
          args['handle'] as int,
          args['index'] as int,
          (args['value'] as num).toDouble());
    case 'bindText':
      return _handleBindText(ffi, args['dbPtr'] as int, args['handle'] as int,
          args['index'] as int, args['value'] as String);
    case 'bindBlob':
      return _handleBindBlob(ffi, args['dbPtr'] as int, args['handle'] as int,
          args['index'] as int, args['value'] as List<int>);

    // ── Bindings (named) ─────────────────────────────────────────────
    case 'bindNameNull':
      return _handleBindNameNull(ffi, args['dbPtr'] as int,
          args['handle'] as int, args['name'] as String);
    case 'bindNameInt':
      return _handleBindNameInt(ffi, args['dbPtr'] as int,
          args['handle'] as int, args['name'] as String, args['value'] as int);
    case 'bindNameInt64':
      return _handleBindNameInt64(ffi, args['dbPtr'] as int,
          args['handle'] as int, args['name'] as String, args['value'] as int);
    case 'bindNameFloat':
      return _handleBindNameFloat(
          ffi,
          args['dbPtr'] as int,
          args['handle'] as int,
          args['name'] as String,
          (args['value'] as num).toDouble());
    case 'bindNameDouble':
      return _handleBindNameDouble(
          ffi,
          args['dbPtr'] as int,
          args['handle'] as int,
          args['name'] as String,
          (args['value'] as num).toDouble());
    case 'bindNameText':
      return _handleBindNameText(
          ffi,
          args['dbPtr'] as int,
          args['handle'] as int,
          args['name'] as String,
          args['value'] as String);
    case 'bindNameBlob':
      return _handleBindNameBlob(
          ffi,
          args['dbPtr'] as int,
          args['handle'] as int,
          args['name'] as String,
          args['value'] as List<int>);

    // ── Pool ─────────────────────────────────────────────────────────
    case 'createPool':
      return _handleCreatePool(
          ffi, args['path'] as String, args['readerCount'] as int);

    case 'poolGetWriter':
      return ffi.poolGetWriter(_resolvePool(args['poolPtr'] as int)).address;

    case 'poolAcquireReader':
      final reader = ffi.poolAcquireReader(_resolvePool(args['poolPtr'] as int));
      return (reader == nullptr || reader.address == 0) ? 0 : reader.address;

    case 'poolAcquireReaderBlocking':
      final reader = ffi.poolAcquireReaderBlocking(
          _resolvePool(args['poolPtr'] as int), args['timeoutMs'] as int);
      // Read the per-thread status BEFORE returning — it is only valid
      // on this worker thread immediately after the acquire, with no
      // intervening native call. The main isolate maps it to an enum.
      final status = ffi.poolLastAcquireStatus();
      return {
        'readerPtr': (reader == nullptr || reader.address == 0)
            ? 0
            : reader.address,
        'status': status,
      };

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

// ── Marshalling helpers ──────────────────────────────────────────────────

int _handleOpenDb(_WorkerFfi ffi, String path) {
  Pointer<Utf8> pathPtr = nullptr;
  try {
    pathPtr = path.toNativeUtf8();
    final ptr = ffi.openDb(pathPtr);
    if (ptr == nullptr || ptr.address == 0) {
      throw Exception('Failed to allocate database wrapper for: $path');
    }
    // Per the v4.3.6 native header, OpenDb returns non-NULL even
    // when sqlite3_open_v2 fails — the failure is encoded in
    // isOpened()/getLastDbError(). Reading the rich error here
    // surfaces messages like "unable to open database file:
    // permission denied" instead of a generic "failed to open".
    if (ffi.isOpened(ptr) != 1) {
      final errPtr = ffi.getLastDbError(ptr);
      final errMsg = (errPtr == nullptr || errPtr.address == 0)
          ? 'unknown sqlite open error'
          : errPtr.toDartString();
      // Free the wrapper before throwing so we don't leak. CloseDb
      // is idempotent on a never-fully-opened wrapper.
      ffi.closeDb(ptr, 0);
      throw Exception('Failed to open database "$path": $errMsg');
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

/// Returns the new stmt handle (uint64 → Dart int) plus the
/// statement's column metadata (count + names). Column metadata is
/// stable for the lifetime of the prepared statement, so capturing
/// it once at prepare time avoids requiring a step-then-query just
/// to find out how many columns the SELECT has — which is needed
/// when the caller (e.g. test-style `for col in 0..count`) reads
/// `getColumnCount()` BEFORE the first `readRow()`.
///
/// Map shape: `{handle: int, columnCount: int, columnNames: List<String>}`.
/// On prepare failure, returns `{handle: 0, columnCount: 0, columnNames: []}`.
Map<String, dynamic> _handlePrepareQuery(
    _WorkerFfi ffi, int dbPtr, String sql) {
  Pointer<Utf8> sqlPtr = nullptr;
  try {
    sqlPtr = sql.toNativeUtf8();
    final db = _resolveDb(dbPtr);
    final handle = ffi.prepareQuery(db, sqlPtr);
    if (handle == 0) {
      return {'handle': 0, 'columnCount': 0, 'columnNames': const <String>[]};
    }
    final count = ffi.getColumnCount(db, handle);
    final names = <String>[];
    for (int i = 0; i < count; i++) {
      final namePtr = ffi.getColumnName(db, handle, i);
      names.add((namePtr == nullptr || namePtr.address == 0)
          ? ''
          : namePtr.toDartString());
    }
    return {
      'handle': handle,
      'columnCount': count,
      'columnNames': names,
    };
  } finally {
    if (sqlPtr != nullptr) calloc.free(sqlPtr);
  }
}

/// Steps the statement once and returns a serialisable row snapshot.
/// Returns `{status, columnCount, columnNames, columns}`. The
/// per-stmt counters and last error are NOT in this payload — the
/// caller reads them via separate dispatches when needed (which is
/// the right time-of-call: counters are captured by the C lib at step
/// time and persist on the live handle).
Map<String, dynamic> _handleReadRow(_WorkerFfi ffi, int dbPtr, int handle) {
  final ptr = _resolveDb(dbPtr);
  final status = ffi.readRow(ptr, handle);

  const sqliteRow = 100;
  List<Map<String, dynamic>>? columns;
  List<String>? columnNames;

  if (status == sqliteRow) {
    final count = ffi.getColumnCount(ptr, handle);
    columnNames = <String>[];
    for (int i = 0; i < count; i++) {
      columnNames.add(ffi.getColumnName(ptr, handle, i).toDartString());
    }
    columns = [];
    for (int i = 0; i < count; i++) {
      final type = ffi.getColumnType(ptr, handle, i);
      final isNull = ffi.isNull(ptr, handle, i) == 1;
      dynamic value;
      if (!isNull) {
        switch (type) {
          case 1: // SQLITE_INTEGER
            value = ffi.getColumnInt64(ptr, handle, i);
          case 2: // SQLITE_FLOAT
            value = ffi.getColumnDouble(ptr, handle, i);
          case 3: // SQLITE_TEXT
            value = ffi.getColumnText(ptr, handle, i).toDartString();
          case 4: // SQLITE_BLOB
            final blobPtr = ffi.getColumnBlob(ptr, handle, i);
            final length = ffi.getColumnBytes(ptr, handle, i);
            value = blobPtr.asTypedList(length).toList();
          default:
            // Unknown SQLite type — fall back to text coercion to
            // preserve the bytes-as-string view.
            developer.log(
              'Unknown SQLite column type $type at index $i — '
              'falling back to text coercion',
              name: 'dbas_sqlite.isolate_worker',
            );
            final textPtr = ffi.getColumnText(ptr, handle, i);
            value = (textPtr == nullptr || textPtr.address == 0)
                ? null
                : textPtr.toDartString();
        }
      }
      columns.add({'type': type, 'isNull': isNull, 'value': value});
    }
  }

  final result = <String, dynamic>{
    'status': status,
    'columnNames': columnNames,
    'columns': columns,
  };

  // columnCount is a property of the prepared statement and is
  // captured at prepare time. We only refresh it from the live handle
  // on SQLITE_ROW (matching the non-worker FFI path's behaviour) — on
  // any other rc the handle may already be in an error state where
  // getColumnCount returns the stale-handle sentinel (-1) and would
  // poison the cache. On non-ROW statuses we omit the field so the
  // Dart-side cache preserves its prepare-time value.
  if (status == sqliteRow) {
    result['columnCount'] = ffi.getColumnCount(ptr, handle);
  }
  return result;
}

int _handleBindText(
    _WorkerFfi ffi, int dbPtr, int handle, int index, String value) {
  Pointer<Utf8> valuePtr = nullptr;
  try {
    valuePtr = value.toNativeUtf8();
    return ffi.bindText(_resolveDb(dbPtr), handle, index, valuePtr);
  } finally {
    if (valuePtr != nullptr) calloc.free(valuePtr);
  }
}

int _handleBindBlob(
    _WorkerFfi ffi, int dbPtr, int handle, int index, List<int> value) {
  Pointer<Uint8> ptr = nullptr;
  try {
    ptr = calloc<Uint8>(value.length);
    for (var i = 0; i < value.length; i++) {
      ptr[i] = value[i];
    }
    return ffi.bindBlob(_resolveDb(dbPtr), handle, index, ptr, value.length);
  } finally {
    if (ptr != nullptr) calloc.free(ptr);
  }
}

int _handleBindNameNull(_WorkerFfi ffi, int dbPtr, int handle, String name) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameNull(_resolveDb(dbPtr), handle, namePtr);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameInt(
    _WorkerFfi ffi, int dbPtr, int handle, String name, int value) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameInt(_resolveDb(dbPtr), handle, namePtr, value);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameInt64(
    _WorkerFfi ffi, int dbPtr, int handle, String name, int value) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameInt64(_resolveDb(dbPtr), handle, namePtr, value);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameFloat(
    _WorkerFfi ffi, int dbPtr, int handle, String name, double value) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameFloat(_resolveDb(dbPtr), handle, namePtr, value);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameDouble(
    _WorkerFfi ffi, int dbPtr, int handle, String name, double value) {
  Pointer<Utf8> namePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    return ffi.bindNameDouble(_resolveDb(dbPtr), handle, namePtr, value);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
  }
}

int _handleBindNameText(
    _WorkerFfi ffi, int dbPtr, int handle, String name, String value) {
  Pointer<Utf8> namePtr = nullptr;
  Pointer<Utf8> valuePtr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    valuePtr = value.toNativeUtf8();
    return ffi.bindNameText(_resolveDb(dbPtr), handle, namePtr, valuePtr);
  } finally {
    if (namePtr != nullptr) calloc.free(namePtr);
    if (valuePtr != nullptr) calloc.free(valuePtr);
  }
}

int _handleBindNameBlob(
    _WorkerFfi ffi, int dbPtr, int handle, String name, List<int> value) {
  Pointer<Utf8> namePtr = nullptr;
  Pointer<Uint8> ptr = nullptr;
  try {
    namePtr = name.toNativeUtf8();
    ptr = calloc<Uint8>(value.length);
    for (var i = 0; i < value.length; i++) {
      ptr[i] = value[i];
    }
    return ffi.bindNameBlob(_resolveDb(dbPtr), handle, namePtr, ptr, value.length);
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

// ── Worker-side FFI binding table ────────────────────────────────────────

class _WorkerFfi {
  late final Pointer<Utf8> Function() getSqliteVersion;
  late final int Function() getAbiVersion;

  late final Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>) openDb;
  late final int Function(Pointer<DbasSqliteDbStruct>) isOpened;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) executeSql;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) closeDb;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>) getLastDbError;
  late final int Function(Pointer<DbasSqliteDbStruct>) getExtendedErrorCode;
  late final int Function(Pointer<DbasSqliteDbStruct>) getAffectedRows;
  late final int Function(Pointer<DbasSqliteDbStruct>) getLastInsertedId;
  late final int Function(Pointer<DbasSqliteDbStruct>) getTotalChanges;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>) getDbFileName;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) setBusyTimeout;
  late final int Function(Pointer<DbasSqliteDbStruct>) enableWal;

  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) prepareQuery;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) finalizeStmt;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) readRow;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)
      getLastStmtError;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getStmtAffectedRows;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getStmtLastInsertedId;

  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) bindNull;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, int) bindInt;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, int) bindInt64;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, double) bindFloat;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, double) bindDouble;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, Pointer<Utf8>)
      bindText;
  late final int Function(
      Pointer<DbasSqliteDbStruct>, int, int, Pointer<Uint8>, int) bindBlob;

  late final int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>)
      bindNameNull;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>, int)
      bindNameInt;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>, int)
      bindNameInt64;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>, double)
      bindNameFloat;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>, double)
      bindNameDouble;
  late final int Function(
      Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>, Pointer<Utf8>) bindNameText;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>,
      Pointer<Uint8>, int) bindNameBlob;

  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) isNull;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int, int)
      getColumnText;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnInt;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnInt64;
  late final double Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnFloat;
  late final double Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnDouble;
  late final Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int, int)
      getColumnBlob;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnBytes;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int, int)
      getColumnName;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnType;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getColumnCount;

  late final Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, int) createPool;
  late final Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>)
      poolGetWriter;
  late final Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>)
      poolAcquireReader;
  late final Pointer<DbasSqliteDbStruct> Function(
      Pointer<DbasSqlitePoolStruct>, int) poolAcquireReaderBlocking;
  late final int Function() poolLastAcquireStatus;
  late final void Function(
      Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>) poolReleaseReader;
  late final void Function(Pointer<DbasSqlitePoolStruct>) closePool;

  _WorkerFfi(DynamicLibrary lib) {
    getSqliteVersion = lib.lookupFunction<Pointer<Utf8> Function(),
        Pointer<Utf8> Function()>('GetSqliteVersion');
    getAbiVersion = lib.lookupFunction<Uint32 Function(), int Function()>(
        'GetAbiVersion');

    openDb = lib.lookupFunction<
        Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>),
        Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>)>('OpenDb');
    isOpened = lib.lookupFunction<Uint8 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('IsOpened');
    executeSql = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>('ExecuteSql');
    closeDb = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('CloseDb');
    getLastDbError = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>)>('GetLastDbError');
    getExtendedErrorCode = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('GetExtendedErrorCode');
    getAffectedRows = lib.lookupFunction<
        Int64 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('GetAffectedRows');
    getLastInsertedId = lib.lookupFunction<
        Int64 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('GetLastInsertedId');
    getTotalChanges = lib.lookupFunction<
        Int64 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('GetTotalChanges');
    getDbFileName = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>)>('GetDbFileName');
    setBusyTimeout = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('SetBusyTimeout');
    enableWal = lib.lookupFunction<Int32 Function(Pointer<DbasSqliteDbStruct>),
        int Function(Pointer<DbasSqliteDbStruct>)>('EnableWal');

    prepareQuery = lib.lookupFunction<
        Uint64 Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>)>('PrepareQuery');
    finalizeStmt = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('FinalizeStmt');
    readRow = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('ReadRow');
    getLastStmtError = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Uint64),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)>('GetLastStmtError');
    getStmtAffectedRows = lib.lookupFunction<
        Int64 Function(Pointer<DbasSqliteDbStruct>, Uint64),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('GetStmtAffectedRows');
    getStmtLastInsertedId = lib.lookupFunction<
        Int64 Function(Pointer<DbasSqliteDbStruct>, Uint64),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('GetStmtLastInsertedId');

    bindNull = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, int)>('BindNull');
    bindInt = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, int, int)>('BindInt');
    bindInt64 = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32, Int64),
        int Function(Pointer<DbasSqliteDbStruct>, int, int, int)>('BindInt64');
    bindFloat = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32, Float),
        int Function(Pointer<DbasSqliteDbStruct>, int, int, double)>('BindFloat');
    bindDouble = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32, Double),
        int Function(Pointer<DbasSqliteDbStruct>, int, int, double)>('BindDouble');
    bindText = lib.lookupFunction<
        Int32 Function(
            Pointer<DbasSqliteDbStruct>, Uint64, Int32, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, int, int, Pointer<Utf8>)>('BindText');
    bindBlob = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32,
            Pointer<Uint8>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, int, Pointer<Uint8>,
            int)>('BindBlob');

    bindNameNull = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, int,
            Pointer<Utf8>)>('BindNameNull');
    bindNameInt = lib.lookupFunction<
        Int32 Function(
            Pointer<DbasSqliteDbStruct>, Uint64, Pointer<Utf8>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>,
            int)>('BindNameInt');
    bindNameInt64 = lib.lookupFunction<
        Int32 Function(
            Pointer<DbasSqliteDbStruct>, Uint64, Pointer<Utf8>, Int64),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>,
            int)>('BindNameInt64');
    bindNameFloat = lib.lookupFunction<
        Int32 Function(
            Pointer<DbasSqliteDbStruct>, Uint64, Pointer<Utf8>, Float),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>,
            double)>('BindNameFloat');
    bindNameDouble = lib.lookupFunction<
        Int32 Function(
            Pointer<DbasSqliteDbStruct>, Uint64, Pointer<Utf8>, Double),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>,
            double)>('BindNameDouble');
    bindNameText = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Pointer<Utf8>,
            Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>,
            Pointer<Utf8>)>('BindNameText');
    bindNameBlob = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Pointer<Utf8>,
            Pointer<Uint8>, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>,
            Pointer<Uint8>, int)>('BindNameBlob');

    isNull = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        int Function(Pointer<DbasSqliteDbStruct>, int, int)>('IsNull');
    getColumnText = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        Pointer<Utf8> Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnText');
    getColumnInt = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        int Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnInt');
    getColumnInt64 = lib.lookupFunction<
        Int64 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        int Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnInt64');
    getColumnFloat = lib.lookupFunction<
        Float Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        double Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnFloat');
    getColumnDouble = lib.lookupFunction<
        Double Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        double Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnDouble');
    getColumnBlob = lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        Pointer<Uint8> Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnBlob');
    getColumnBytes = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        int Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnBytes');
    getColumnName = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        Pointer<Utf8> Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnName');
    getColumnType = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        int Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnType');
    getColumnCount = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64),
        int Function(Pointer<DbasSqliteDbStruct>, int)>('GetColumnCount');

    createPool = lib.lookupFunction<
        Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, Int32),
        Pointer<DbasSqlitePoolStruct> Function(
            Pointer<Utf8>, int)>('CreatePool');
    poolGetWriter = lib.lookupFunction<
        Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>),
        Pointer<DbasSqliteDbStruct> Function(
            Pointer<DbasSqlitePoolStruct>)>('PoolGetWriter');
    poolAcquireReader = lib.lookupFunction<
        Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>),
        Pointer<DbasSqliteDbStruct> Function(
            Pointer<DbasSqlitePoolStruct>)>('PoolAcquireReader');
    poolAcquireReaderBlocking = lib.lookupFunction<
        Pointer<DbasSqliteDbStruct> Function(
            Pointer<DbasSqlitePoolStruct>, Int32),
        Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>,
            int)>('PoolAcquireReaderBlocking');
    poolLastAcquireStatus = lib.lookupFunction<Int32 Function(),
        int Function()>('PoolLastAcquireStatus');
    poolReleaseReader = lib.lookupFunction<
        Void Function(
            Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>),
        void Function(Pointer<DbasSqlitePoolStruct>,
            Pointer<DbasSqliteDbStruct>)>('PoolReleaseReader');
    closePool = lib.lookupFunction<
        Void Function(Pointer<DbasSqlitePoolStruct>),
        void Function(Pointer<DbasSqlitePoolStruct>)>('ClosePool');
  }
}
