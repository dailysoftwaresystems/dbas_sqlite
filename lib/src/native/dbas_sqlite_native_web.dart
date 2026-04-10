import 'dart:async';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'dbas_sqlite_native_interface.dart';
import 'dbas_sqlite_web_pool.dart';

class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  late DbasSqliteWebPool _pool;
  bool _initialized = false;
  bool _dbOpened = false;
  int? _cachedWriterPtr;

  /// The currently acquired slot lease (held during cursor sessions).
  SlotLease? _currentLease;

  /// Transaction lease — held from beginTransaction through commit/rollback.
  SlotLease? _transactionLease;

  /// Cached state from the last executeSql/readRow (survives lease release).
  int _lastAffectedRows = 0;
  int _lastInsertedId = 0;
  String? _lastError;

  /// When true, the next prepareQuery acquires SlotMode.write instead of read.
  bool _nextPrepareIsWrite = false;

  DbasSqliteNativeWeb(super.dbName);

  static void registerWith(Registrar registrar) {}

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _pool = DbasSqliteWebPool.getInstance(
      workerCount: DbasSqliteNativeInterface.workerPoolSize,
    );
    _initialized = true;
  }

  @override
  Future<int> openDb(String path) async {
    final lease = await _pool.acquire(dbName, SlotMode.write);
    try {
      final dbPtr = await lease.slot.ensureDbOpened(dbName);
      _dbOpened = dbPtr != 0;
      return dbPtr;
    } finally {
      _pool.release(lease);
    }
  }

  @override
  Future<bool> databaseExists(String fileName) async {
    return await _pool.sendToAny(dbName, 'databaseExists') == true;
  }

  @override
  bool isOpened(int dbPtr) => _dbOpened;

  @override
  Future<void> closeDb(int dbPtr) async {
    // Use the same cleanup path as closePool to properly handle
    // stale wrappers, affinity removal, and closedDbs tracking.
    await _pool.closeDbOnAllSlots(dbName);
    _dbOpened = false;
  }

  // ── File operations ───────────────────────────────────────────────────

  @override
  Future attachDb(String fileName, List<int> content) async {
    final lease = await _pool.acquire(dbName, SlotMode.write);
    try {
      await lease.slot.ensureDbInitialized(dbName);
      await lease.slot.send('attachDb', {'dbName': dbName, 'content': content});
    } finally {
      _pool.release(lease);
    }
  }

  @override
  Future attachStreamDb(String fileName, Stream<List<int>> stream) async {
    final lease = await _pool.acquire(dbName, SlotMode.write);
    try {
      await lease.slot.ensureDbInitialized(dbName);
      await lease.slot.send('beginStreamAttach', {'dbName': dbName});
      try {
        await for (final chunk in stream) {
          await lease.slot.send('streamAttachChunk', {'dbName': dbName, 'bytes': chunk});
        }
        await lease.slot.send('endStreamAttach', {'dbName': dbName});
      } catch (e) {
        try {
          await lease.slot.send('abortStreamAttach', {'dbName': dbName});
        } catch (abortError) {
          // ignore: avoid_print
          print('attachStreamDb: abortStreamAttach also failed: $abortError');
        }
        rethrow;
      }
    } finally {
      _pool.release(lease);
    }
  }

  @override
  Future<List<int>> getContent(String fileName) async {
    final lease = await _pool.acquire(dbName, SlotMode.read);
    try {
      await lease.slot.ensureDbInitialized(dbName);
      final result = await lease.slot.send('getContent', {'dbName': dbName});
      if (result is List) {
        return result.cast<num>().map((e) => e.toInt()).toList();
      }
      return [];
    } finally {
      _pool.release(lease);
    }
  }

  @override
  Future<void> streamCopyDb(String sourceFileName, String destFileName) async {
    String destName = destFileName;
    if (destFileName.contains('/')) destName = destFileName.split('/').last;
    final lease = await _pool.acquire(dbName, SlotMode.write);
    try {
      await lease.slot.ensureDbInitialized(dbName);
      await lease.slot.send('streamCopyDb', {'dbName': dbName, 'destName': destName});
    } finally {
      _pool.release(lease);
    }
  }

  @override
  Future dropDb(String fileName) async {
    final lease = await _pool.acquire(dbName, SlotMode.write);
    try {
      await lease.slot.ensureDbInitialized(dbName);
      await lease.slot.send('dropDb', {'dbName': dbName});
    } finally {
      _pool.release(lease);
    }
  }

  // ── SQL execution ─────────────────────────────────────────────────────

  @override
  Future<int> executeSql(int dbPtr, String sql) async {
    // If a transaction lease is held, reuse it
    final lease = _transactionLease ?? await _pool.acquire(dbName, SlotMode.write);
    final isTransactionScoped = _transactionLease != null;
    try {
      final slotDbPtr = await lease.slot.ensureDbOpened(dbName);
      final result = await lease.slot.send('executeSql', {
        'dbName': dbName, 'dbPtr': slotDbPtr, 'sql': sql,
      });
      if (result is Map) {
        lease.slot.row.updateFromExecuteSql(result);
        // Cache state before lease is released
        _cacheSlotState(lease.slot);
        return _toInt(result['rc']);
      }
      return _toInt(result);
    } finally {
      if (!isTransactionScoped) _pool.release(lease);
    }
  }

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async {
    // Determine acquire mode: write if setWriteMode was called, else read
    final mode = _nextPrepareIsWrite ? SlotMode.write : SlotMode.read;
    _nextPrepareIsWrite = false;

    // If a transaction lease is held, reuse it; otherwise acquire a new one
    if (_transactionLease != null) {
      _currentLease = _transactionLease;
    } else {
      _currentLease = await _pool.acquire(dbName, mode);
    }

    final isTransactionScoped = _transactionLease != null;
    try {
      final slot = _currentLease!.slot;
      final slotDbPtr = await slot.ensureDbOpened(dbName);
      final result = await slot.send('prepareQuery', {
        'dbName': dbName, 'dbPtr': slotDbPtr, 'sql': sql,
      });
      if (result is Map) {
        slot.row.updateFromPrepare(result);
        return _toInt(result['rc']);
      }
      return _toInt(result);
    } catch (e) {
      // Release lease on error (unless transaction-scoped)
      if (!isTransactionScoped && _currentLease != null) {
        _pool.release(_currentLease!);
        _currentLease = null;
      }
      rethrow;
    }
  }

  // ── Parameter binding (buffered into current slot) ────────────────────

  @override
  int bindNull(int dbPtr, int index) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindNull', 'index': index});
    return 0;
  }

  @override
  int bindInt(int dbPtr, int index, int value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindInt', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindFloat(int dbPtr, int index, double value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindFloat', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindDouble(int dbPtr, int index, double value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindDouble', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindText(int dbPtr, int index, String value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindText', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindBlob(int dbPtr, int index, List<int> value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindBlob', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindNameNull(int dbPtr, String name) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindNameNull', 'name': name});
    return 0;
  }

  @override
  int bindNameInt(int dbPtr, String name, int value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindNameInt', 'name': name, 'value': value});
    return 0;
  }

  @override
  int bindNameFloat(int dbPtr, String name, double value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindNameFloat', 'name': name, 'value': value});
    return 0;
  }

  @override
  int bindNameDouble(int dbPtr, String name, double value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindNameDouble', 'name': name, 'value': value});
    return 0;
  }

  @override
  int bindNameText(int dbPtr, String name, String value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindNameText', 'name': name, 'value': value});
    return 0;
  }

  @override
  int bindNameBlob(int dbPtr, String name, List<int> value) {
    _currentLease!.slot.pendingBinds.add({'method': 'bindNameBlob', 'name': name, 'value': value});
    return 0;
  }

  // ── Row reading (flushes buffered binds, caches row in slot) ──────────

  @override
  Future<int> readRow(int dbPtr) async {
    final slot = _currentLease!.slot;
    final slotDbPtr = slot.getDbPtr(dbName);
    final args = <String, dynamic>{'dbName': dbName, 'dbPtr': slotDbPtr};
    if (slot.pendingBinds.isNotEmpty) {
      args['binds'] = List<Map<String, dynamic>>.from(slot.pendingBinds);
      slot.pendingBinds.clear();
    }

    final result = await slot.send('readRow', args);
    if (result is Map) {
      slot.row.updateFromReadRow(result);
      // Cache state for post-release access
      _cacheSlotState(slot);
      return _toInt(result['status']);
    }
    return _toInt(result);
  }

  // ── Column accessors (from current slot's row cache) ──────────────────

  @override
  bool isNull(int dbPtr, int colIndex) =>
      _currentLease!.slot.row.columns?[colIndex].isNull ?? true;

  @override
  String getColumnText(int dbPtr, int colIndex) =>
      _currentLease!.slot.row.columns?[colIndex].value?.toString() ?? '';

  @override
  int getColumnInt(int dbPtr, int colIndex) =>
      _toInt(_currentLease!.slot.row.columns?[colIndex].value);

  @override
  double getColumnFloat(int dbPtr, int colIndex) =>
      _toDouble(_currentLease!.slot.row.columns?[colIndex].value);

  @override
  double getColumnDouble(int dbPtr, int colIndex) =>
      _toDouble(_currentLease!.slot.row.columns?[colIndex].value);

  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) {
    final value = _currentLease!.slot.row.columns?[columnIndex].value;
    if (value is List) return value.cast<num>().map((e) => e.toInt()).toList();
    return [];
  }

  @override
  int getColumnBytes(int dbPtr, int columnIndex) =>
      getColumnBlob(dbPtr, columnIndex).length;

  @override
  String getColumnName(int dbPtr, int colIndex) =>
      colIndex < _currentLease!.slot.row.columnNames.length
          ? _currentLease!.slot.row.columnNames[colIndex]
          : '';

  @override
  int getColumnType(int dbPtr, int colIndex) =>
      _currentLease!.slot.row.columns?[colIndex].type ?? 5;

  @override
  int getColumnCount(int dbPtr) => _currentLease!.slot.row.columnCount;

  // ── State accessors (from cached state or current slot) ───────────────

  @override
  String? getLastDbError(int dbPtr) {
    final slot = _currentLease?.slot ?? _transactionLease?.slot;
    return slot?.row.lastError ?? _lastError;
  }

  @override
  int getAffectedRows(int dbPtr) {
    final slot = _currentLease?.slot ?? _transactionLease?.slot;
    return slot?.row.affectedRows ?? _lastAffectedRows;
  }

  @override
  int getLastInsertedId(int dbPtr) {
    final slot = _currentLease?.slot ?? _transactionLease?.slot;
    return slot?.row.lastInsertedId ?? _lastInsertedId;
  }

  // ── Reader management ─────────────────────────────────────────────────

  @override
  Future closeReader(int dbPtr) async {
    if (_currentLease == null) return;

    final lease = _currentLease!;
    try {
      final slot = lease.slot;
      final slotDbPtr = slot.getDbPtr(dbName);
      await slot.send('closeReader', {'dbName': dbName, 'dbPtr': slotDbPtr});
      slot.row.columns = null;
    } finally {
      // Always release unless this is the transaction lease
      if (_currentLease != _transactionLease) {
        _pool.release(lease);
      }
      _currentLease = null;
    }
  }

  // ── Connection Pool (web pool handles this internally) ────────────────

  @override
  Future<int> createPool(String path, int readerCount) async {
    // On web, the worker pool IS the pool. Open the DB eagerly on one worker.
    final lease = await _pool.acquire(dbName, SlotMode.write);
    try {
      final dbPtr = await lease.slot.ensureDbOpened(dbName);
      _cachedWriterPtr = dbPtr;
      if (dbPtr != 0) _dbOpened = true;
      return dbPtr; // Use dbPtr as pseudo pool pointer
    } finally {
      _pool.release(lease);
    }
  }

  @override
  int poolGetWriter(int poolPtr) => _cachedWriterPtr ?? 0;

  @override
  int poolAcquireReader(int poolPtr) => 0;

  @override
  void poolReleaseReader(int poolPtr, int readerPtr) {}

  @override
  Future<void> closePool(int poolPtr) async {
    await _pool.closeDbOnAllSlots(dbName);
    _cachedWriterPtr = null;
    _dbOpened = false;
  }

  // ── Transaction lease management ──────────────────────────────────────

  @override
  Future<void> beginTransactionLease() async {
    _transactionLease = await _pool.acquire(dbName, SlotMode.write);
    try {
      await _transactionLease!.slot.ensureDbOpened(dbName);
    } catch (e) {
      _pool.release(_transactionLease!);
      _transactionLease = null;
      rethrow;
    }
  }

  @override
  Future<void> endTransactionLease() async {
    if (_transactionLease != null) {
      _pool.release(_transactionLease!);
      _transactionLease = null;
    }
  }

  // ── Write mode hint ───────────────────────────────────────────────────

  @override
  void setWriteMode() {
    _nextPrepareIsWrite = true;
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Cache slot state into instance fields so it survives lease release.
  void _cacheSlotState(WorkerSlot slot) {
    _lastAffectedRows = slot.row.affectedRows;
    _lastInsertedId = slot.row.lastInsertedId;
    _lastError = slot.row.lastError;
  }

  static int _toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
  static double _toDouble(dynamic v) => v is double ? v : (v is num ? v.toDouble() : 0.0);
}
