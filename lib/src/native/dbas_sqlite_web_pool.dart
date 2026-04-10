import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Mode for acquiring a pool slot.
enum SlotMode { read, write }

int _toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

/// Cached column data for a single column in the current row.
class ColumnData {
  final int type;
  final bool isNull;
  final dynamic value;

  ColumnData({required this.type, required this.isNull, this.value});

  factory ColumnData.fromMap(Map<String, dynamic> map) {
    return ColumnData(
      type: _toInt(map['type']),
      isNull: map['isNull'] == true,
      value: map['value'],
    );
  }
}

/// Cached row data from the last readRow/prepareQuery/executeSql response.
class RowData {
  List<ColumnData>? columns;
  int columnCount = 0;
  List<String> columnNames = [];
  int affectedRows = 0;
  int lastInsertedId = 0;
  String? lastError;

  void updateFromPrepare(Map result) {
    columns = null;
    columnCount = _toInt(result['columnCount']);
    columnNames = (result['columnNames'] as List?)?.cast<String>() ?? [];
    lastError = _parseError(result['lastError']);
  }

  void updateFromReadRow(Map result) {
    columnCount = _toInt(result['columnCount']);
    affectedRows = _toInt(result['affectedRows']);
    lastInsertedId = _toInt(result['lastInsertedId']);
    lastError = _parseError(result['lastError']);

    if (result['columns'] is List) {
      columns = (result['columns'] as List)
          .map((c) => ColumnData.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList();
    } else {
      columns = null;
    }
  }

  void updateFromExecuteSql(Map result) {
    affectedRows = _toInt(result['affectedRows']);
    lastInsertedId = _toInt(result['lastInsertedId']);
    lastError = _parseError(result['lastError']);
  }

  void clear() {
    columns = null;
    columnCount = 0;
    columnNames = [];
    affectedRows = 0;
    lastInsertedId = 0;
    lastError = null;
  }

  static String? _parseError(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    if (str == 'null' || str.isEmpty) return null;
    return str;
  }
}

/// A single worker slot in the pool.
class WorkerSlot {
  final web.Worker worker;

  int _nextRequestId = 0;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  /// Per-slot session state (mirrors what the worker holds in JS).
  final RowData row = RowData();
  final List<Map<String, dynamic>> pendingBinds = [];

  /// DBs initialized on this worker (lazy).
  final Set<String> _initializedDbs = {};

  /// Per-DB dbPtr cache (each worker gets its own dbPtr when opening a DB).
  final Map<String, int> _dbPtrs = {};

  bool isBusy = false;

  WorkerSlot(this.worker) {
    worker.onmessage = ((web.MessageEvent e) => _onMessage(e)).toJS;
    worker.onerror = ((web.Event e) => _onError(e)).toJS;
  }

  void _onMessage(web.MessageEvent event) {
    final data = (event.data as JSObject).dartify();
    if (data is! Map) return;

    final id = data['id'];
    if (id == null) return;

    final completer = _pendingRequests.remove(id);
    if (completer == null) return;

    if (data.containsKey('error') && data['error'] != null) {
      completer.completeError(Exception(data['error'].toString()));
    } else {
      completer.complete(data['result']);
    }
  }

  void _onError(web.Event e) {
    final error = Exception('Web Worker error: ${e.type}');
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRequests.clear();
  }

  /// Send a message to this slot's worker and await the response.
  Future<dynamic> send(String method, [Map<String, dynamic>? args]) async {
    final id = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;
    worker.postMessage(<String, dynamic>{
      'id': id, 'method': method, 'args': args ?? {},
    }.jsify());
    return completer.future;
  }

  /// Ensure this worker has initialized the given DB.
  Future<void> ensureDbInitialized(String dbName) async {
    if (_initializedDbs.contains(dbName)) return;
    await send('initDb', {'dbName': dbName});
    _initializedDbs.add(dbName);
  }

  /// Open a DB on this worker if not already opened, return the dbPtr.
  Future<int> ensureDbOpened(String dbName) async {
    await ensureDbInitialized(dbName);
    if (_dbPtrs.containsKey(dbName)) return _dbPtrs[dbName]!;
    final ptr = _toInt(await send('openDb', {'dbName': dbName}));
    if (ptr == 0) {
      throw Exception('Failed to open database "$dbName" on worker slot');
    }
    _dbPtrs[dbName] = ptr;
    return ptr;
  }

  /// Get the cached dbPtr for a DB on this worker.
  int getDbPtr(String dbName) => _dbPtrs[dbName] ?? 0;

  /// Mark a DB as closed on this worker.
  void clearDbPtr(String dbName) {
    _dbPtrs.remove(dbName);
  }

  /// Forget all state for a DB.
  void forgetDb(String dbName) {
    _dbPtrs.remove(dbName);
    _initializedDbs.remove(dbName);
  }
}

/// A lease representing an acquired slot.
class SlotLease {
  final WorkerSlot slot;
  final String dbName;
  final SlotMode mode;

  SlotLease(this.slot, this.dbName, this.mode);
}

/// Global web worker pool. Manages N workers shared across all databases.
///
/// Uses **per-DB slot affinity**: each database is pinned to a single worker
/// because each Emscripten module has its own isolated virtual filesystem.
/// Cross-worker FS synchronization is not guaranteed, so all operations for
/// a given DB must go through the same worker.
///
/// Parallelism comes from different databases using different workers.
///
/// Thread safety rules:
/// - Write: only 1 writer per DB at a time (others queue)
/// - Read: allowed concurrently with other reads (but same slot, so serialized)
/// - Different DBs can operate in parallel on different slots
class DbasSqliteWebPool {
  static DbasSqliteWebPool? _instance;

  final List<WorkerSlot> _slots;

  /// Per-DB slot affinity: each DB is pinned to a specific worker.
  final Map<String, WorkerSlot> _dbAffinity = {};

  /// Tracks which DB currently has an active write lease.
  final Map<String, SlotLease> _activeWriters = {};

  /// Wait queue: callers waiting for a free slot or write access.
  final Queue<_WaitEntry> _waitQueue = Queue<_WaitEntry>();

  DbasSqliteWebPool._(this._slots);

  /// Get or create the global pool singleton.
  ///
  /// The [workerCount] is only effective on the first call. Subsequent calls
  /// return the existing pool.
  static DbasSqliteWebPool getInstance({int workerCount = 4}) {
    if (_instance != null) return _instance!;

    final slots = <WorkerSlot>[];
    for (int i = 0; i < workerCount; i++) {
      final worker = web.Worker(
        'assets/packages/dbas_sqlite_flutter/web/libs/dbas_sqlite_worker.js'.toJS,
      );
      slots.add(WorkerSlot(worker));
    }

    _instance = DbasSqliteWebPool._(slots);
    return _instance!;
  }

  /// Acquire a slot for the given DB and mode.
  ///
  /// If the DB already has an affinity slot, waits for that specific slot.
  /// Otherwise picks any free slot and establishes affinity.
  Future<SlotLease> acquire(String dbName, SlotMode mode) async {
    // Try immediate acquisition
    final lease = _tryAcquire(dbName, mode);
    if (lease != null) return lease;

    // Queue and wait
    final completer = Completer<SlotLease>();
    _waitQueue.add(_WaitEntry(dbName, mode, completer));
    return completer.future;
  }

  /// Release a previously acquired slot.
  void release(SlotLease lease) {
    lease.slot.isBusy = false;
    lease.slot.row.clear();
    lease.slot.pendingBinds.clear();

    if (lease.mode == SlotMode.write) {
      _activeWriters.remove(lease.dbName);
    }

    // Try to satisfy queued waiters
    _drainWaitQueue();
  }

  /// Close a DB on its affinity worker and release the affinity.
  ///
  /// Sends `closeDb` to close the SQLite connection. The Emscripten wrapper
  /// is left alive — the next `initDb` always creates a fresh wrapper
  /// (replacing the stale one) without destroying shared OPFS state that
  /// other DBs on the same worker might depend on.
  Future<void> closeDbOnAllSlots(String dbName) async {
    final affinitySlot = _dbAffinity[dbName];
    if (affinitySlot == null) return;

    // Wait for the affinity slot to be free (with timeout)
    int waitMs = 0;
    while (affinitySlot.isBusy) {
      await Future.delayed(const Duration(milliseconds: 1));
      if (++waitMs > 10000) {
        throw StateError(
          'closeDbOnAllSlots("$dbName"): timed out after 10s waiting for '
          'slot to become free. A pool lease may be leaked.',
        );
      }
    }
    affinitySlot.isBusy = true;
    try {
      final dbPtr = affinitySlot.getDbPtr(dbName);
      if (dbPtr != 0) {
        await affinitySlot.send('closeDb', {'dbName': dbName, 'dbPtr': dbPtr});
      }
      affinitySlot.forgetDb(dbName);
    } finally {
      affinitySlot.isBusy = false;
      _dbAffinity.remove(dbName);
      _drainWaitQueue();
    }
  }

  /// Send a one-shot message to the DB's affinity slot (or any available
  /// slot for stateless queries like databaseExists).
  Future<dynamic> sendToAny(String dbName, String method,
      [Map<String, dynamic>? args]) async {
    final lease = await acquire(dbName, SlotMode.read);
    try {
      await lease.slot.ensureDbInitialized(dbName);
      args ??= {};
      args['dbName'] = dbName;
      return await lease.slot.send(method, args);
    } finally {
      release(lease);
    }
  }

  SlotLease? _tryAcquire(String dbName, SlotMode mode) {
    if (mode == SlotMode.write && _activeWriters.containsKey(dbName)) {
      return null; // Another write is active for this DB
    }

    // If this DB has an affinity slot, use it
    final affinitySlot = _dbAffinity[dbName];
    if (affinitySlot != null) {
      if (!affinitySlot.isBusy) {
        affinitySlot.isBusy = true;
        final lease = SlotLease(affinitySlot, dbName, mode);
        if (mode == SlotMode.write) {
          _activeWriters[dbName] = lease;
        }
        return lease;
      }
      return null; // Affinity slot is busy, must wait
    }

    // No affinity yet — prefer a slot with no other DB affinity.
    // Each Emscripten module (initPersistentFS) uses OPFS state that can
    // conflict when two modules share a worker. Isolating each DB to its
    // own worker avoids WASM memory access errors.
    WorkerSlot? fallbackSlot;
    for (final slot in _slots) {
      if (!slot.isBusy) {
        if (!_dbAffinity.containsValue(slot)) {
          // Ideal: slot with no other DB affinity
          slot.isBusy = true;
          _dbAffinity[dbName] = slot;
          final lease = SlotLease(slot, dbName, mode);
          if (mode == SlotMode.write) {
            _activeWriters[dbName] = lease;
          }
          return lease;
        }
        fallbackSlot ??= slot;
      }
    }

    // Fallback: share a slot if all have existing affinities
    if (fallbackSlot != null) {
      fallbackSlot.isBusy = true;
      _dbAffinity[dbName] = fallbackSlot;
      final lease = SlotLease(fallbackSlot, dbName, mode);
      if (mode == SlotMode.write) {
        _activeWriters[dbName] = lease;
      }
      return lease;
    }

    return null; // No free slots
  }

  void _drainWaitQueue() {
    final pending = <_WaitEntry>[];

    while (_waitQueue.isNotEmpty) {
      final entry = _waitQueue.removeFirst();
      if (entry.completer.isCompleted) continue;

      final lease = _tryAcquire(entry.dbName, entry.mode);
      if (lease != null) {
        entry.completer.complete(lease);
      } else {
        pending.add(entry);
      }
    }

    // Re-add entries that couldn't be satisfied
    _waitQueue.addAll(pending);
  }
}

class _WaitEntry {
  final String dbName;
  final SlotMode mode;
  final Completer<SlotLease> completer;

  _WaitEntry(this.dbName, this.mode, this.completer);
}
