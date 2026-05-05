import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

import 'dbas_sqlite_native_app_base.dart';
import 'dbas_sqlite_native_interface.dart';
import 'dbas_sqlite_isolate_worker.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_db.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';

/// Native FFI implementation for every Flutter platform except web.
///
/// Threads heavy operations through a multi-isolate worker pool so
/// blocking calls (notably [poolAcquireReaderBlocking]) cannot starve
/// concurrent releases. The worker pool size is auto-bumped at openDb
/// time to `max(workerPoolSize, readerPoolSize + 2)` — see §5.7 of the
/// v2.4.0 plan.
///
/// Sync operations (isOpened, non-blocking pool acquire/release,
/// cached version strings) run on the main isolate via direct FFI to
/// avoid the postMessage round-trip cost.
class DbasSqliteNativeApp extends DbasSqliteNativeAppBase {
  late DynamicLibrary _lib;
  late _MainIsolateFfi _ffi;

  // ── Multi-isolate worker pool ───────────────────────────────────────
  final List<_WorkerHandle> _workers = [];
  int _nextWorkerIdx = 0;
  String? _resolvedLibPath;

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

    _ffi = _MainIsolateFfi(_lib);
    cacheSqliteVersion();

    _resolvedLibPath = (!isTest && (Platform.isIOS || Platform.isMacOS))
        ? '' // process() — worker handles this internally
        : await getLibraryPath();

    // Initial pool size — bumped on createPool when readerPoolSize is known.
    final initialSize = DbasSqliteNativeInterface.workerPoolSize;
    await _resizeWorkerPool(initialSize);
  }

  Future<void> _resizeWorkerPool(int size) async {
    while (_workers.length < size) {
      final w = await _spawnWorker(_resolvedLibPath ?? '');
      _workers.add(w);
    }
  }

  Future<_WorkerHandle> _spawnWorker(String libPath) async {
    final receivePort = ReceivePort();
    final initMsg = WorkerInitMessage(receivePort.sendPort, libPath);
    await Isolate.spawn(isolateWorkerEntryPoint, initMsg);

    final portCompleter = Completer<SendPort>();
    final pending = <int, Completer<dynamic>>{};

    // The handle reference is filled in once we have the SendPort.
    // The receivePort.listen closure captures it by reference so
    // onDone / onError can mark the handle dead and remove it from
    // the active worker list.
    late _WorkerHandle handle;

    void retireWorker(Object error) {
      handle.alive = false;
      for (final c in pending.values) {
        if (!c.isCompleted) c.completeError(error);
      }
      pending.clear();
      _workers.remove(handle);
      developer.log(
        'FFI worker isolate retired: $error',
        name: 'dbas_sqlite.DbasSqliteNativeApp',
      );
    }

    receivePort.listen(
      (message) {
        if (message is SendPort) {
          portCompleter.complete(message);
        } else if (message is IsolateResponse) {
          final c = pending.remove(message.id);
          if (c != null) {
            if (message.error != null) {
              c.completeError(Exception(message.error));
            } else {
              c.complete(message.result);
            }
          }
        }
      },
      onDone: () => retireWorker(StateError('Worker terminated')),
      onError: (e) => retireWorker(StateError('Worker error: $e')),
    );

    final sendPort = await portCompleter.future;
    handle = _WorkerHandle(sendPort, pending);
    return handle;
  }

  /// Prefer-free dispatch: pick the worker with the fewest in-flight
  /// requests. A worker blocked inside `PoolAcquireReaderBlocking`
  /// (with one pending) is skipped over a free worker (with zero),
  /// avoiding the round-robin pile-up where unrelated calls queue
  /// behind a long blocking acquire. Falls back to round-robin
  /// among ties.
  Future<dynamic> _dispatch(String method, [Map<String, dynamic>? args]) {
    if (_workers.isEmpty) {
      throw StateError('Worker pool not initialised');
    }
    // Find the live worker with the smallest pending queue.
    _WorkerHandle? best;
    int bestLoad = -1;
    for (int i = 0; i < _workers.length; i++) {
      final candidate = _workers[(_nextWorkerIdx + i) % _workers.length];
      if (!candidate.alive) continue;
      final load = candidate.pending.length;
      if (best == null || load < bestLoad) {
        best = candidate;
        bestLoad = load;
        if (load == 0) break; // can't beat zero
      }
    }
    if (best == null) {
      throw StateError('No live FFI worker isolate available');
    }
    _nextWorkerIdx = (_nextWorkerIdx + 1) % _workers.length;
    return best.send(method, args ?? const {});
  }

  // ── Pointer-sync helpers (main isolate FFI) ─────────────────────────

  @override
  bool isOpened(int dbPtr) => _ffi.isOpened(resolveDbPtr(dbPtr)) == 1;

  // ── Lifecycle (worker-dispatched) ───────────────────────────────────

  @override
  Future<int> openDb(String path) async =>
      await _dispatch('openDb', {'path': path}) as int;

  @override
  Future<int> executeSql(int dbPtr, String sql) async =>
      await _dispatch('executeSql', {'dbPtr': dbPtr, 'sql': sql}) as int;

  @override
  Future<int> closeDb(int dbPtr, {bool checkpoint = false}) async {
    return await _dispatch('closeDb', {
      'dbPtr': dbPtr,
      'checkpoint': checkpoint ? 1 : 0,
    }) as int;
  }

  // ── Statement (worker-dispatched) ───────────────────────────────────

  @override
  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(int dbPtr, String sql) async {
    final result =
        await _dispatch('prepareQuery', {'dbPtr': dbPtr, 'sql': sql});
    if (result is Map) {
      return (
        handle: (result['handle'] as num).toInt(),
        columnCount: (result['columnCount'] as num).toInt(),
        columnNames: (result['columnNames'] as List).cast<String>(),
      );
    }
    // Backward-compat fallback (shouldn't happen with the new worker).
    final h = (result as num).toInt();
    return (handle: h, columnCount: 0, columnNames: const <String>[]);
  }

  @override
  Future<int> finalizeStmt(int dbPtr, int handle) async =>
      await _dispatch('finalizeStmt',
          {'dbPtr': dbPtr, 'handle': handle}) as int;

  @override
  Future<int> readRowAndCache(int dbPtr, int handle, RowData cache) async {
    final result = await _dispatch(
        'readRowAndCache', {'dbPtr': dbPtr, 'handle': handle});
    if (result is Map) {
      cache.updateFromReadRow(result);
      // Capture column names lazily; the worker also returns them.
      if (result['columnNames'] is List) {
        cache.columnNames = (result['columnNames'] as List).cast<String>();
      }
      return toIntSafe(result['status']);
    }
    return toIntSafe(result);
  }

  // ── Bindings (worker-dispatched, awaited) ───────────────────────────
  // Each bind awaits the dispatch so the C-side rc surfaces. Returning
  // a Future<int> instead of int lets DbasSqliteStatement's
  // _replayBindsNative observe SQLITE_RANGE / SQLITE_TOOBIG /
  // SQLITE_NOMEM / stale-handle errors and translate them into
  // exceptions tied to the offending parameter. Without the await,
  // every bind error would be silently dropped and only resurface as
  // an opaque step failure later.

  Future<int> _bindDispatch(String method, Map<String, dynamic> args) async {
    final result = await _dispatch(method, args);
    return (result as num).toInt();
  }

  @override
  Future<int> bindNull(int dbPtr, int handle, int index) =>
      _bindDispatch('bindNull',
          {'dbPtr': dbPtr, 'handle': handle, 'index': index});

  @override
  Future<int> bindInt(int dbPtr, int handle, int index, int value) =>
      _bindDispatch('bindInt', {
        'dbPtr': dbPtr,
        'handle': handle,
        'index': index,
        'value': value,
      });

  @override
  Future<int> bindInt64(int dbPtr, int handle, int index, int value) =>
      _bindDispatch('bindInt64', {
        'dbPtr': dbPtr,
        'handle': handle,
        'index': index,
        'value': value,
      });

  @override
  Future<int> bindFloat(int dbPtr, int handle, int index, double value) =>
      _bindDispatch('bindFloat', {
        'dbPtr': dbPtr,
        'handle': handle,
        'index': index,
        'value': value,
      });

  @override
  Future<int> bindDouble(int dbPtr, int handle, int index, double value) =>
      _bindDispatch('bindDouble', {
        'dbPtr': dbPtr,
        'handle': handle,
        'index': index,
        'value': value,
      });

  @override
  Future<int> bindText(int dbPtr, int handle, int index, String value) =>
      _bindDispatch('bindText', {
        'dbPtr': dbPtr,
        'handle': handle,
        'index': index,
        'value': value,
      });

  @override
  Future<int> bindBlob(int dbPtr, int handle, int index, List<int> value) =>
      _bindDispatch('bindBlob', {
        'dbPtr': dbPtr,
        'handle': handle,
        'index': index,
        'value': value,
      });

  @override
  Future<int> bindNameNull(int dbPtr, int handle, String name) =>
      _bindDispatch('bindNameNull',
          {'dbPtr': dbPtr, 'handle': handle, 'name': name});

  @override
  Future<int> bindNameInt(int dbPtr, int handle, String name, int value) =>
      _bindDispatch('bindNameInt', {
        'dbPtr': dbPtr,
        'handle': handle,
        'name': name,
        'value': value,
      });

  @override
  Future<int> bindNameInt64(int dbPtr, int handle, String name, int value) =>
      _bindDispatch('bindNameInt64', {
        'dbPtr': dbPtr,
        'handle': handle,
        'name': name,
        'value': value,
      });

  @override
  Future<int> bindNameFloat(int dbPtr, int handle, String name, double value) =>
      _bindDispatch('bindNameFloat', {
        'dbPtr': dbPtr,
        'handle': handle,
        'name': name,
        'value': value,
      });

  @override
  Future<int> bindNameDouble(int dbPtr, int handle, String name, double value) =>
      _bindDispatch('bindNameDouble', {
        'dbPtr': dbPtr,
        'handle': handle,
        'name': name,
        'value': value,
      });

  @override
  Future<int> bindNameText(int dbPtr, int handle, String name, String value) =>
      _bindDispatch('bindNameText', {
        'dbPtr': dbPtr,
        'handle': handle,
        'name': name,
        'value': value,
      });

  @override
  Future<int> bindNameBlob(int dbPtr, int handle, String name, List<int> value) =>
      _bindDispatch('bindNameBlob', {
        'dbPtr': dbPtr,
        'handle': handle,
        'name': name,
        'value': value,
      });

  // ── Pool (mixed: blocking goes through worker, non-blocking sync) ───

  @override
  Future<int> createPool(String path, int readerCount) async {
    // Bump worker pool floor before creating the C-side pool so we have
    // headroom for blocking acquires + concurrent releases.
    final wanted = readerCount + 2;
    if (_workers.length < wanted) {
      await _resizeWorkerPool(wanted);
    }
    return await _dispatch(
        'createPool', {'path': path, 'readerCount': readerCount}) as int;
  }

  @override
  int poolGetWriter(int poolPtr) =>
      _ffi.poolGetWriter(resolvePoolPtr(poolPtr)).address;

  @override
  int poolAcquireReader(int poolPtr) {
    final reader = _ffi.poolAcquireReader(resolvePoolPtr(poolPtr));
    if (reader == nullptr || reader.address == 0) return 0;
    return reader.address;
  }

  @override
  Future<int> poolAcquireReaderBlocking(int poolPtr, int timeoutMs) async {
    return await _dispatch('poolAcquireReaderBlocking', {
      'poolPtr': poolPtr,
      'timeoutMs': timeoutMs,
    }) as int;
  }

  @override
  void poolReleaseReader(int poolPtr, int readerPtr) {
    _ffi.poolReleaseReader(resolvePoolPtr(poolPtr), resolveDbPtr(readerPtr));
  }

  @override
  Future<void> closePool(int poolPtr) async {
    await _dispatch('closePool', {'poolPtr': poolPtr});
  }

  // ── nativeXxx delegates (main-isolate FFI for shared marshalling) ───
  // These run on the main isolate. The worker has its own copy of
  // these in `_WorkerFfi`. Keep both in sync.

  @override
  Pointer<Utf8> nativeGetSqliteVersion() => _ffi.getSqliteVersion();
  @override
  int nativeGetAbiVersion() => _ffi.getAbiVersion();

  @override
  Pointer<DbasSqliteDbStruct> nativeOpenDb(Pointer<Utf8> path) =>
      _ffi.openDb(path);
  @override
  int nativeIsOpened(Pointer<DbasSqliteDbStruct> dbPtr) => _ffi.isOpened(dbPtr);
  @override
  int nativeExecuteSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) =>
      _ffi.executeSql(dbPtr, sql);
  @override
  int nativeCloseDb(Pointer<DbasSqliteDbStruct> dbPtr, int checkpoint) =>
      _ffi.closeDb(dbPtr, checkpoint);
  @override
  Pointer<Utf8> nativeGetLastDbError(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _ffi.getLastDbError(dbPtr);
  @override
  int nativeGetAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _ffi.getAffectedRows(dbPtr);
  @override
  int nativeGetLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _ffi.getLastInsertedId(dbPtr);
  @override
  int nativeGetTotalChanges(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _ffi.getTotalChanges(dbPtr);
  @override
  Pointer<Utf8> nativeGetDbFileName(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _ffi.getDbFileName(dbPtr);
  @override
  int nativeSetBusyTimeout(Pointer<DbasSqliteDbStruct> dbPtr, int ms) =>
      _ffi.setBusyTimeout(dbPtr, ms);
  @override
  int nativeEnableWal(Pointer<DbasSqliteDbStruct> dbPtr) =>
      _ffi.enableWal(dbPtr);

  @override
  int nativePrepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql) =>
      _ffi.prepareQuery(dbPtr, sql);
  @override
  int nativeFinalizeStmt(Pointer<DbasSqliteDbStruct> dbPtr, int handle) =>
      _ffi.finalizeStmt(dbPtr, handle);
  @override
  int nativeReadRow(Pointer<DbasSqliteDbStruct> dbPtr, int handle) =>
      _ffi.readRow(dbPtr, handle);
  @override
  Pointer<Utf8> nativeGetLastStmtError(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle) =>
      _ffi.getLastStmtError(dbPtr, handle);
  @override
  int nativeGetStmtAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr, int handle) =>
      _ffi.getStmtAffectedRows(dbPtr, handle);
  @override
  int nativeGetStmtLastInsertedId(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle) =>
      _ffi.getStmtLastInsertedId(dbPtr, handle);

  @override
  int nativeBindNull(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index) =>
      _ffi.bindNull(dbPtr, handle, index);
  @override
  int nativeBindInt(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index,
          int value) =>
      _ffi.bindInt(dbPtr, handle, index, value);
  @override
  int nativeBindInt64(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index,
          int value) =>
      _ffi.bindInt64(dbPtr, handle, index, value);
  @override
  int nativeBindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index,
          double value) =>
      _ffi.bindFloat(dbPtr, handle, index, value);
  @override
  int nativeBindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index,
          double value) =>
      _ffi.bindDouble(dbPtr, handle, index, value);
  @override
  int nativeBindText(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index,
          Pointer<Utf8> value) =>
      _ffi.bindText(dbPtr, handle, index, value);
  @override
  int nativeBindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index,
          Pointer<Uint8> value, int length) =>
      _ffi.bindBlob(dbPtr, handle, index, value, length);

  @override
  int nativeBindNameNull(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, Pointer<Utf8> name) =>
      _ffi.bindNameNull(dbPtr, handle, name);
  @override
  int nativeBindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, int handle,
          Pointer<Utf8> name, int value) =>
      _ffi.bindNameInt(dbPtr, handle, name, value);
  @override
  int nativeBindNameInt64(Pointer<DbasSqliteDbStruct> dbPtr, int handle,
          Pointer<Utf8> name, int value) =>
      _ffi.bindNameInt64(dbPtr, handle, name, value);
  @override
  int nativeBindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, int handle,
          Pointer<Utf8> name, double value) =>
      _ffi.bindNameFloat(dbPtr, handle, name, value);
  @override
  int nativeBindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, int handle,
          Pointer<Utf8> name, double value) =>
      _ffi.bindNameDouble(dbPtr, handle, name, value);
  @override
  int nativeBindNameText(Pointer<DbasSqliteDbStruct> dbPtr, int handle,
          Pointer<Utf8> name, Pointer<Utf8> value) =>
      _ffi.bindNameText(dbPtr, handle, name, value);
  @override
  int nativeBindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, int handle,
          Pointer<Utf8> name, Pointer<Uint8> value, int length) =>
      _ffi.bindNameBlob(dbPtr, handle, name, value, length);

  @override
  int nativeIsNull(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex) =>
      _ffi.isNull(dbPtr, handle, colIndex);
  @override
  Pointer<Utf8> nativeGetColumnText(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex) =>
      _ffi.getColumnText(dbPtr, handle, colIndex);
  @override
  int nativeGetColumnInt(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex) =>
      _ffi.getColumnInt(dbPtr, handle, colIndex);
  @override
  int nativeGetColumnInt64(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex) =>
      _ffi.getColumnInt64(dbPtr, handle, colIndex);
  @override
  double nativeGetColumnFloat(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex) =>
      _ffi.getColumnFloat(dbPtr, handle, colIndex);
  @override
  double nativeGetColumnDouble(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex) =>
      _ffi.getColumnDouble(dbPtr, handle, colIndex);
  @override
  Pointer<Uint8> nativeGetColumnBlob(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int columnIndex) =>
      _ffi.getColumnBlob(dbPtr, handle, columnIndex);
  @override
  int nativeGetColumnBytes(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int columnIndex) =>
      _ffi.getColumnBytes(dbPtr, handle, columnIndex);
  @override
  Pointer<Utf8> nativeGetColumnName(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int columnIndex) =>
      _ffi.getColumnName(dbPtr, handle, columnIndex);
  @override
  int nativeGetColumnType(
          Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex) =>
      _ffi.getColumnType(dbPtr, handle, colIndex);
  @override
  int nativeGetColumnCount(Pointer<DbasSqliteDbStruct> dbPtr, int handle) =>
      _ffi.getColumnCount(dbPtr, handle);

  @override
  Pointer<DbasSqlitePoolStruct> nativeCreatePool(
          Pointer<Utf8> path, int readerCount) =>
      _ffi.createPool(path, readerCount);
  @override
  Pointer<DbasSqliteDbStruct> nativePoolGetWriter(
          Pointer<DbasSqlitePoolStruct> poolPtr) =>
      _ffi.poolGetWriter(poolPtr);
  @override
  Pointer<DbasSqliteDbStruct> nativePoolAcquireReader(
          Pointer<DbasSqlitePoolStruct> poolPtr) =>
      _ffi.poolAcquireReader(poolPtr);
  @override
  Pointer<DbasSqliteDbStruct> nativePoolAcquireReaderBlocking(
          Pointer<DbasSqlitePoolStruct> poolPtr, int timeoutMs) =>
      _ffi.poolAcquireReaderBlocking(poolPtr, timeoutMs);
  @override
  void nativePoolReleaseReader(Pointer<DbasSqlitePoolStruct> poolPtr,
          Pointer<DbasSqliteDbStruct> readerPtr) =>
      _ffi.poolReleaseReader(poolPtr, readerPtr);
  @override
  void nativeClosePool(Pointer<DbasSqlitePoolStruct> poolPtr) =>
      _ffi.closePool(poolPtr);
}

/// One worker isolate. Owns its own SendPort and pending-request map.
/// [alive] is flipped to false by the receivePort's onDone/onError
/// closure; the dispatcher uses it to skip dead workers instead of
/// silently sending into a closed receive port (which Dart drops).
class _WorkerHandle {
  final SendPort port;
  final Map<int, Completer<dynamic>> pending;
  bool alive = true;
  int _nextId = 0;

  _WorkerHandle(this.port, this.pending);

  Future<dynamic> send(String method, Map<String, dynamic> args) {
    if (!alive) {
      throw StateError('Cannot send to a retired worker isolate');
    }
    final id = _nextId++;
    final c = Completer<dynamic>();
    pending[id] = c;
    port.send(IsolateCommand(id, method, args));
    return c.future;
  }
}

/// Shared FFI binding table — used by both the main isolate and each
/// worker isolate. Each instance owns its own `lookupFunction` results
/// for the same `DynamicLibrary`.
class _MainIsolateFfi {
  // Library-scoped
  late final Pointer<Utf8> Function() getSqliteVersion;
  late final int Function() getAbiVersion;

  // Connection lifecycle
  late final Pointer<DbasSqliteDbStruct> Function(Pointer<Utf8>) openDb;
  late final int Function(Pointer<DbasSqliteDbStruct>) isOpened;
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) executeSql;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) closeDb;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>) getLastDbError;
  late final int Function(Pointer<DbasSqliteDbStruct>) getAffectedRows;
  late final int Function(Pointer<DbasSqliteDbStruct>) getLastInsertedId;
  late final int Function(Pointer<DbasSqliteDbStruct>) getTotalChanges;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>) getDbFileName;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) setBusyTimeout;
  late final int Function(Pointer<DbasSqliteDbStruct>) enableWal;

  // Statement lifecycle
  late final int Function(Pointer<DbasSqliteDbStruct>, Pointer<Utf8>) prepareQuery;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) finalizeStmt;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) readRow;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int)
      getLastStmtError;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getStmtAffectedRows;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getStmtLastInsertedId;

  // Bindings (positional)
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) bindNull;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, int) bindInt;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, int) bindInt64;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, double) bindFloat;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, double) bindDouble;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int, Pointer<Utf8>)
      bindText;
  late final int Function(
      Pointer<DbasSqliteDbStruct>, int, int, Pointer<Uint8>, int) bindBlob;

  // Bindings (named)
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

  // Column accessors
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) isNull;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int, int)
      getColumnText;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnInt;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnInt64;
  late final double Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnFloat;
  late final double Function(Pointer<DbasSqliteDbStruct>, int, int)
      getColumnDouble;
  late final Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int, int)
      getColumnBlob;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnBytes;
  late final Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int, int)
      getColumnName;
  late final int Function(Pointer<DbasSqliteDbStruct>, int, int) getColumnType;
  late final int Function(Pointer<DbasSqliteDbStruct>, int) getColumnCount;

  // Connection pool
  late final Pointer<DbasSqlitePoolStruct> Function(Pointer<Utf8>, int) createPool;
  late final Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>)
      poolGetWriter;
  late final Pointer<DbasSqliteDbStruct> Function(Pointer<DbasSqlitePoolStruct>)
      poolAcquireReader;
  late final Pointer<DbasSqliteDbStruct> Function(
      Pointer<DbasSqlitePoolStruct>, int) poolAcquireReaderBlocking;
  late final void Function(
      Pointer<DbasSqlitePoolStruct>, Pointer<DbasSqliteDbStruct>) poolReleaseReader;
  late final void Function(Pointer<DbasSqlitePoolStruct>) closePool;

  _MainIsolateFfi(DynamicLibrary lib) {
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
    enableWal = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>),
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
        int Function(Pointer<DbasSqliteDbStruct>, int, Pointer<Utf8>)>('BindNameNull');
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
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int,
            int)>('GetColumnText');
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
        Pointer<Uint8> Function(Pointer<DbasSqliteDbStruct>, int,
            int)>('GetColumnBlob');
    getColumnBytes = lib.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        int Function(
            Pointer<DbasSqliteDbStruct>, int, int)>('GetColumnBytes');
    getColumnName = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, Uint64, Int32),
        Pointer<Utf8> Function(Pointer<DbasSqliteDbStruct>, int,
            int)>('GetColumnName');
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
