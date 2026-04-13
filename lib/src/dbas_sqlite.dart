import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart'
  if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/stub/dbas_sqlite_db_stub.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_platform.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_reader.dart';
import 'package:dbas_sqlite_flutter/src/helpers/dbas_sqlite_platform_util.dart';
import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_interface.dart';
import 'package:decimal/decimal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';


/// A cross-platform SQLite database wrapper for Flutter.
///
/// Provides a unified API to interact with SQLite databases on Android, iOS,
/// macOS, Linux, Windows and Web platforms.
///
/// Uses a singleton pattern per database name, so calling [getInstance] with
/// the same [dbName] always returns the same instance.
///
/// ```dart
/// final db = await DbasSqlite.getInstance(dbName: 'myapp.db');
/// await db.openDb();
///
/// await db.executeSql(
///   'INSERT INTO users (name, email) VALUES (?, ?)',
///   params: ['John', 'john@example.com'],
/// );
///
/// final reader = await db.executeReader('SELECT * FROM users WHERE id > ?', params: [0]);
/// while (await reader.readRow()) {
///   print(reader.getColumnText(0));
/// }
/// await reader.close();
///
/// await db.closeDb();
/// ```
class DbasSqlite {
  static final _sqliteOk = 0;
  static final _sqliteMisuse = 20;
  static final _sqliteRange = 25;
  static final _sqliteRow = 100;
  static final _sqliteDone = 101;
  static final _sqliteSuccessResults = [_sqliteOk, _sqliteRow, _sqliteDone];

  static final String _webDbDir = 'dbas_data';
  static final Map<String, DbasSqlite> _instance = {};
  final DbasSqlitePlatform _platform;
  final String dbName;
  DbasSqliteDb? _db;
  bool _isInTransaction = false;
  int? _poolPtr;
  final Set<DbasSqliteReader> _activeReaders = {};
  final Queue<Completer<void>> _writerWaitQueue = Queue<Completer<void>>();
  bool _writerLockHeld = false;
  final Queue<Completer<void>> _poolReaderReleasedQueue = Queue<Completer<void>>();

  /// When `true`, binding a named parameter that does not exist in the
  /// prepared statement throws an exception instead of silently skipping it.
  ///
  /// Defaults to `false` (C#/SQLite-compatible behavior).
  bool throwOnMissingNamedParams = false;

  DbasSqlite._dbasSqlite(this._platform, this.dbName, {this.throwOnMissingNamedParams = false});

  /// Returns a singleton instance of [DbasSqlite] for the given [dbName].
  ///
  /// If an instance for [dbName] already exists, it is returned immediately.
  /// Otherwise, a new instance is created and cached.
  ///
  /// Defaults to `'dbas.db'` if no name is provided.
  static Future<DbasSqlite> getInstance({String dbName = 'dbas.db', bool throwOnMissingNamedParams = false, int workerPoolSize = 4}) async {
    if (_instance.containsKey(dbName)) {
      assert(
        workerPoolSize == DbasSqliteNativeInterface.workerPoolSize,
        'DbasSqlite.getInstance: workerPoolSize=$workerPoolSize was passed for '
        'an already-initialized instance of "$dbName" (current pool size is '
        '${DbasSqliteNativeInterface.workerPoolSize}). workerPoolSize is only '
        'applied on the first call; subsequent values are ignored.',
      );
      _instance[dbName]!.throwOnMissingNamedParams = throwOnMissingNamedParams;
      return _instance[dbName]!;
    }

    // Configure global pool size before first platform initialization
    DbasSqliteNativeInterface.workerPoolSize = workerPoolSize;

    _instance[dbName] = DbasSqlite._dbasSqlite(await DbasSqlitePlatform.getInstance(dbName: dbName), dbName, throwOnMissingNamedParams: throwOnMissingNamedParams);
    return _instance[dbName]!;
  }

  static Future<String> _getDbPath() async {
    if (kIsWeb) {
      return '/$_webDbDir';
    }

    final directory = await getApplicationSupportDirectory();
    final dirPath = '${directory.path}/dbas_data'.replaceAll('\\', '/');
    final dir = Directory(dirPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dirPath;
  }

  /// Checks whether the database file exists on disk (or in IndexedDB on web).
  Future<bool> databaseExists() async {
    final fileName = await getAppDatabasePath(dbName: dbName);
    return await _platform.databaseExists(fileName);
  }

  /// Attaches a database from bytes and optionally opens it.
  ///
  /// If a database with the same name already exists and is opened, it will be
  /// closed and removed before attaching the new database.
  ///
  /// When [openDb] is `true` (the default), the database is automatically
  /// opened after being written to disk.
  ///
  /// Returns the [DbasSqlite] instance for the attached database.
  Future<DbasSqlite> attachDb(List<int> bytes, {bool openDb = true}) async {
    if (_instance.containsKey(dbName)) {
      if (_instance[dbName]!.isOpened()) {
        await _instance[dbName]!.closeDb();
      }

      _instance.remove(dbName);
    }

    String fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.attachDb(fileName, bytes);
    final instance = await getInstance(dbName: dbName);

    if (openDb) {
      await instance.openDb();
    }

    return instance;
  }

  /// Attaches a database from a byte stream and optionally opens it.
  ///
  /// Similar to [attachDb], but accepts a [Stream<List<int>>] instead of
  /// a complete byte list, allowing the database to be written incrementally
  /// (e.g. from an HTTP download or file read stream) without buffering
  /// the entire content in memory.
  ///
  /// On native platforms the bytes are streamed directly to disk.
  /// On web each chunk is sent to the Web Worker via postMessage and written
  /// through the Emscripten filesystem backed by OPFS, so the complete file
  /// does not need to be buffered in Dart memory.
  ///
  /// If a database with the same name already exists and is opened, it will be
  /// closed and removed before attaching the new database.
  ///
  /// When [openDb] is `true` (the default), the database is automatically
  /// opened after being written.
  ///
  /// Returns the [DbasSqlite] instance for the attached database.
  Future<DbasSqlite> attachStreamDb(Stream<List<int>> stream, {bool openDb = true}) async {
    if (_instance.containsKey(dbName)) {
      if (_instance[dbName]!.isOpened()) {
        await _instance[dbName]!.closeDb();
      }

      _instance.remove(dbName);
    }

    String fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.attachStreamDb(fileName, stream);
    final instance = await getInstance(dbName: dbName);

    if (openDb) {
      await instance.openDb();
    }

    return instance;
  }

  /// Copies the current database to a new database with the given [destDbName].
  ///
  /// The copy is performed as a streaming chunk-by-chunk operation so the
  /// entire file does not need to reside in memory at once.
  ///
  /// On native platforms the file is streamed from disk.
  /// On web the copy is performed between OPFS file handles.
  Future<void> streamCopyDb(String destDbName) async {
    String sourceFileName = await getAppDatabasePath(dbName: dbName);
    String destFileName = await getAppDatabasePath(dbName: destDbName);
    await _platform.streamCopyDb(sourceFileName, destFileName);
  }

  /// Returns the raw bytes of the database file.
  ///
  /// Useful for backup, export or transferring the database to another device.
  Future<List<int>> getContent() async {
    String fileName = await getAppDatabasePath(dbName: dbName);
    return await _platform.getContent(fileName);
  }

  /// Deletes the database file, including WAL and SHM journal files.
  ///
  /// If the database is currently open, it will be closed first.
  /// Does nothing if the database file does not exist.
  Future<void> dropDb() async {
    if (!await databaseExists()) {
      return;
    }

    if (isOpened()) {
      await closeDb();
    }

    String fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.dropDb(fileName);
  }

  /// Returns the full filesystem path for the database.
  ///
  /// If [dbName] is not provided, uses the instance's [dbName].
  ///
  /// In test mode (`FLUTTER_TEST`), the path points to `test/db/` in the
  /// project directory. On web, returns a virtual path. On other platforms,
  /// uses [getApplicationSupportDirectory].
  Future<String> getAppDatabasePath({String? dbName}) async {
    dbName ??= this.dbName;

    if (DbasSqlitePlatformUtil.isTest()) {
      String dbPath = path.join(Directory.current.path, 'test', 'db');
      Directory dbDir = Directory(dbPath);
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      return path.join(dbPath, dbName);
    }

    String dbPath = await _getDbPath();
    return '$dbPath/$dbName';
  }

  /// Opens the database using a connection pool with WAL mode.
  ///
  /// Creates one writer connection and [readerPoolSize] read-only reader
  /// connections. The writer is used for all DML/DDL operations while
  /// readers are automatically acquired and released for SELECT queries.
  ///
  /// The database file path is resolved automatically via [getAppDatabasePath].
  /// After calling this method, [isOpened] returns `true`.
  ///
  /// Throws an [Exception] if the database cannot be opened.
  Future<void> openDb({int readerPoolSize = 4}) async {
    String fileName = await getAppDatabasePath(dbName: dbName);

    if (readerPoolSize > 0) {
      final poolPtr = await _platform.createPool(dbName, fileName, readerPoolSize);
      if (poolPtr != 0) {
        _poolPtr = poolPtr;
        final writerPtr = _platform.poolGetWriter(dbName, poolPtr);
        _db = DbasSqliteDb(dbName, writerPtr);
        return;
      }
    }

    _db = await _platform.openDb(fileName);
  }

  /// Returns `true` if the database connection is currently open.
  bool isOpened() {
    return _db != null && _platform.isOpened(_db!);
  }

  /// Executes a SQL statement (DDL or DML) and returns the number of affected rows.
  ///
  /// Supports both positional [params] and named [nameParams]:
  ///
  /// ```dart
  /// // Positional parameters (1-based internally)
  /// await db.executeSql(
  ///   'INSERT INTO users (name, age) VALUES (?, ?)',
  ///   params: ['Alice', 30],
  /// );
  ///
  /// // Named parameters (auto-prefixed with ':' if needed)
  /// await db.executeSql(
  ///   'INSERT INTO users (name, age) VALUES (:name, :age)',
  ///   nameParams: {'name': 'Alice', 'age': 30},
  /// );
  /// ```
  ///
  /// Throws a [StateError] if the database is not opened.
  /// Throws an [Exception] if the query cannot be prepared or executed.
  Future<int> executeSql(String sql, {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before executing SQL commands.');
    }

    final lockHeld = _isInTransaction;
    if (!lockHeld) await _acquireWriterLock();
    try {
      if (!isOpened()) {
        throw StateError('Database was closed while waiting for writer lock.');
      }
      final conn = _db!;
      // On web, hint that this prepareQuery is for a write operation
      // so the pool acquires a write-exclusive slot.
      if (kIsWeb) _platform.setWriteMode(dbName);
      int prepared = await _platform.prepareQuery(conn, sql);
      if (prepared != _sqliteOk) {
        String error = _platform.getLastDbError(conn) ?? 'Unknown error.';
        await _platform.closeReader(conn);
        throw Exception("It was not possible to prepare the query ($prepared): $error");
      }

      try {
        _bindParameters(conn, params);
        _bindNameParameters(conn, nameParams);

        int readResult = await _readRowAndValidate(conn, () => _platform.closeReader(conn));

        int result = 0;
        if (readResult != _sqliteRow) {
          result = _platform.getAffectedRows(conn);
        }
        return result;
      } finally {
        await _platform.closeReader(conn);
      }
    } finally {
      if (!lockHeld) _releaseWriterLock();
    }
  }

  Future<int> _readRowAndValidate(DbasSqliteDb conn, Future<void> Function() onClose) async {
    int readResult = await _platform.readRow(conn);
    if (!_sqliteSuccessResults.contains(readResult)) {
      String? error = _platform.getLastDbError(conn);
      await onClose();
      if (error == null && readResult == _sqliteMisuse) {
        error = 'Misuse: possibly missing or invalid bind.';
      }
      error ??= 'Unknown error ($readResult).';
      throw Exception("It was not possible to run the query ($readResult): $error");
    }
    return readResult;
  }

  /// Prepares and binds a SELECT query, returning an independent
  /// [DbasSqliteReader] for row-by-row iteration.
  ///
  /// Each call returns a new reader with its own connection, so multiple
  /// readers can be active simultaneously for parallel reads.
  ///
  /// ```dart
  /// final reader = await db.executeReader('SELECT * FROM users WHERE age > ?', params: [18]);
  /// while (await reader.readRow()) {
  ///   print(reader.getColumnText(0));
  /// }
  /// await reader.close();
  /// ```
  ///
  /// Supports both positional [params] and named [nameParams].
  ///
  /// Throws a [StateError] if the database is not opened.
  /// Throws an [Exception] if the query cannot be prepared.
  Future<DbasSqliteReader> executeReader(String sql, {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before executing SQL commands.');
    }

    DbasSqliteDb? poolReader;
    bool readerHoldsWriterLock = false;

    if (!kIsWeb) {
      if (_poolPtr != null && !_isInTransaction) {
        // Try to acquire a pool reader without blocking
        final readerPtr = _platform.poolAcquireReader(dbName, _poolPtr!);
        if (readerPtr != 0) {
          poolReader = DbasSqliteDb(dbName, readerPtr);
        }
      }

      // No pool, pool exhausted, or in transaction — use writer connection
      if (poolReader == null) {
        if (!_isInTransaction) {
          await _acquireWriterLock();
          if (!isOpened()) {
            _releaseWriterLock();
            throw StateError('Database was closed while waiting for writer lock.');
          }
          readerHoldsWriterLock = true;
        }
      }
    }

    final conn = poolReader ?? _db!;
    DbasSqliteReader? reader;

    Future<void> releaseConnection() async {
      if (reader != null) {
        _activeReaders.remove(reader);
      }
      if (poolReader != null && _poolPtr != null) {
        _platform.poolReleaseReader(dbName, _poolPtr!, poolReader!.ptr);
        poolReader = null;
        _drainPoolReaderWaitQueue();
      } else if (readerHoldsWriterLock) {
        readerHoldsWriterLock = false;
        _releaseWriterLock();
      }
    }

    int prepared = await _platform.prepareQuery(conn, sql);
    if (prepared != _sqliteOk) {
      final error = _platform.getLastDbError(conn) ?? 'Unknown error.';
      await _platform.closeReader(conn);
      await releaseConnection();
      throw Exception("It was not possible to prepare the query ($prepared): $error");
    }

    try {
      _bindParameters(conn, params);
      _bindNameParameters(conn, nameParams);
    } catch (_) {
      await _platform.closeReader(conn);
      await releaseConnection();
      rethrow;
    }

    reader = DbasSqliteReader(conn, _platform, releaseConnection);
    _activeReaders.add(reader);
    return reader;
  }

  /// Returns the row ID of the last successfully inserted row.
  int getLastInsertedId() {
    return _platform.getLastInsertedId(_db!);
  }

  // ── Async locks (FIFO queues for writer + reader) ──────────────────
  Future<void> _acquireWriterLock() async {
    if (!_writerLockHeld) {
      _writerLockHeld = true;
      return;
    }
    final waiter = Completer<void>();
    _writerWaitQueue.add(waiter);
    await waiter.future;
  }

  void _releaseWriterLock() {
    if (_writerWaitQueue.isNotEmpty) {
      _writerWaitQueue.removeFirst().complete();
    } else {
      _writerLockHeld = false;
    }
  }

  void _cancelWriterWaitQueue() {
    while (_writerWaitQueue.isNotEmpty) {
      _writerWaitQueue.removeFirst().completeError(
        StateError('Database was closed while waiting for writer lock.'),
      );
    }
    _writerLockHeld = false;
  }

  void _drainPoolReaderWaitQueue() {
    if (_poolReaderReleasedQueue.isNotEmpty) {
      _poolReaderReleasedQueue.removeFirst().complete();
    }
  }

  void _bindParameters(DbasSqliteDb conn, List<Object?>? parameters) {
    if (parameters == null || parameters.isEmpty) {
      return;
    }

    for (int i = 0; i < parameters.length; i++) {
      final index = i + 1; // SQLite index are based on starting 1
      final value = parameters[i];

      int paramResult = -1;
      if (value == null) {
        paramResult = _platform.bindNull(conn, index);
      } else if (value is bool) {
        paramResult = _platform.bindInt(conn, index, value ? 1 : 0);
      } else if (value is int) {
        paramResult = _platform.bindInt(conn, index, value);
      } else if (value is double) {
        paramResult = _platform.bindDouble(conn, index, value);
      } else if (value is Decimal) {
        paramResult = _platform.bindDecimal(conn, index, value);
      } else if (value is String) {
        paramResult = _platform.bindText(conn, index, value);
      } else if (value is Uint8List) {
        paramResult = _platform.bindBlob(conn, index, value);
      } else if (value is List<int>) {
        paramResult = _platform.bindBlob(conn, index, Uint8List.fromList(value));
      } else if (value is Enum) {
        paramResult = _platform.bindInt(conn, index, value.index);
      } else {
        throw UnsupportedError('Unsupported type to SQLite bind: ${value.runtimeType}');
      }

      if (paramResult != _sqliteOk) {
        throw Exception("It was not possible to bind the parameter ($paramResult): ${_platform.getLastDbError(conn) ?? 'Unknown error.'}");
      }
    }
  }

  void _bindNameParameters(DbasSqliteDb conn, Map<String, Object?>? parameters) {
    if (parameters == null || parameters.isEmpty) {
      return;
    }

    for (MapEntry<String, Object?> entry in parameters.entries) {
      String paramName = entry.key;
      Object? value = entry.value;

      if (!paramName.startsWith(':') && !paramName.startsWith('@') && !paramName.startsWith(r'$')) {
        paramName = ':$paramName';
      }

      int paramResult = -1;
      if (value == null) {
        paramResult = _platform.bindNameNull(conn, paramName);
      } else if (value is bool) {
        paramResult = _platform.bindNameInt(conn, paramName, value ? 1 : 0);
      } else if (value is int) {
        paramResult = _platform.bindNameInt(conn, paramName, value);
      } else if (value is double) {
        paramResult = _platform.bindNameDouble(conn, paramName, value.toDouble());
      } else if (value is Decimal) {
        paramResult = _platform.bindNameDecimal(conn, paramName, value);
      } else if (value is String) {
        paramResult = _platform.bindNameText(conn, paramName, value);
      } else if (value is Uint8List) {
        paramResult = _platform.bindNameBlob(conn, paramName, value);
      } else if (value is Enum) {
        paramResult = _platform.bindNameInt(conn, paramName, value.index);
      } else {
        throw UnsupportedError('Unsupported type to SQLite named bind: ${value.runtimeType}');
      }

      if (paramResult == _sqliteRange) {
        if (throwOnMissingNamedParams) {
          throw Exception("Named parameter '$paramName' not found in the prepared statement");
        }
        continue;
      }
      if (paramResult != _sqliteOk) {
        throw Exception("It was not possible to bind the named parameter: ${_platform.getLastDbError(conn) ?? 'Unknown error ($paramResult)'}");
      }
    }
  }

  /// Closes the database connection and removes the instance from the cache.
  /// If a transaction is currently active, it will be automatically rolled
  /// back before closing to prevent silent data loss.
  ///
  /// After calling this method, [isOpened] returns `false` and a new call
  /// to [getInstance] with the same name will create a fresh instance.
  Future<void> closeDb() async {
    // Close all active readers before shutting down — this releases their
    // pool connections and writer locks so the pool/db can be closed cleanly.
    final readers = List<DbasSqliteReader>.of(_activeReaders);
    for (final reader in readers) {
      await reader.close();
    }

    await rollback();
    _cancelWriterWaitQueue();

    if (!kIsWeb) {
      // Cancel any pool-reader waiters
      while (_poolReaderReleasedQueue.isNotEmpty) {
        _poolReaderReleasedQueue.removeFirst().completeError(
          StateError('Database was closed while waiting for a reader connection.'),
        );
      }
    }

    if (_instance.containsKey(dbName)) {
      _instance.remove(dbName);
    }

    if (_poolPtr != null) {
      await _platform.closePool(dbName, _poolPtr!);
      _poolPtr = null;
      _db = null;
    } else if (_db != null) {
      await _platform.closeDb(_db!);
      _db = null;
    }
  }

  /// Returns `true` if a transaction is currently active.
  ///
  /// A transaction is considered active after calling [beginTransaction]
  /// and before calling [commit] or [rollback].
  bool get isInTransaction => _isInTransaction;

  /// Begins a new database transaction.
  ///
  /// All subsequent SQL statements will be part of this transaction until
  /// [commit] or [rollback] is called.
  ///
  /// If a transaction is already active, this method does nothing.
  ///
  /// For automatic rollback on errors, prefer using [transaction] instead.
  ///
  /// ```dart
  /// await db.beginTransaction();
  /// try {
  ///   await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Alice']);
  ///   await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Bob']);
  ///   await db.commit();
  /// } catch (_) {
  ///   await db.rollback();
  ///   rethrow;
  /// }
  /// ```
  ///
  /// Throws a [StateError] if the database is not opened.
  Future<void> beginTransaction() async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before starting a transaction.');
    }
    if (_isInTransaction) {
      return;
    }
    await _acquireWriterLock();
    try {
      if (!isOpened()) {
        _releaseWriterLock();
        throw StateError('Database was closed while waiting for writer lock.');
      }
      await _platform.executeSql(_db!, 'BEGIN TRANSACTION');
      _isInTransaction = true;
    } catch (_) {
      if (_isInTransaction) rethrow;
      _releaseWriterLock();
      rethrow;
    }
  }

  /// Commits the current transaction, persisting all changes made since
  /// [beginTransaction] was called.
  ///
  /// If no transaction is active, this method does nothing.
  ///
  /// After calling this method, [isInTransaction] returns `false`.
  Future<void> commit() async {
    if (!_isInTransaction) {
      return;
    }
    try {
      await _platform.executeSql(_db!, 'COMMIT');
      _isInTransaction = false;
      _releaseWriterLock();
    } catch(e) {
      await rollback();
      rethrow;
    }
  }

  /// Rolls back the current transaction, discarding all changes made since
  /// [beginTransaction] was called.
  ///
  /// If no transaction is active, this method does nothing.
  ///
  /// After calling this method, [isInTransaction] returns `false`.
  Future<void> rollback() async {
    if (!_isInTransaction) {
      return;
    }
    try {
      await _platform.executeSql(_db!, 'ROLLBACK');
    } finally {
      _isInTransaction = false;
      _releaseWriterLock();
    }
  }

  /// Executes [action] within a database transaction with automatic
  /// commit and rollback.
  ///
  /// If [action] completes successfully, the transaction is committed.
  /// If [action] throws an exception, the transaction is rolled back
  /// and the exception is rethrown.
  ///
  /// ```dart
  /// await db.transaction((db) async {
  ///   await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Alice']);
  ///   await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Bob']);
  /// });
  /// ```
  ///
  /// Throws a [StateError] if the database is not opened.
  /// Throws a [StateError] if a transaction is already active.
  Future<void> transaction(Future<void> Function(DbasSqlite db) action) async {
    if (_isInTransaction) {
      throw StateError('A transaction is already active. Cannot nest transactions.');
    }
    await beginTransaction();
    try {
      await action(this);
      await commit();
    } catch (originalError) {
      try {
        await rollback();
      } catch (rollbackError) {
        throw StateError(
          'Transaction failed: $originalError. '
          'Additionally, rollback also failed: $rollbackError. '
          'The database may be in an inconsistent state.',
        );
      }
      rethrow;
    }
  }

  /// Rebuilds the database file, repacking it into the minimum amount of
  /// disk space.
  ///
  /// This is useful after deleting a large amount of data to reclaim unused
  /// space, or to defragment the database file.
  ///
  /// **Note:** VACUUM cannot be run inside a transaction. If a transaction is
  /// currently active, a [StateError] is thrown.
  ///
  /// ```dart
  /// await db.executeSql('DELETE FROM logs WHERE created < ?', params: [cutoff]);
  /// await db.vacuum();
  /// ```
  ///
  /// Throws a [StateError] if the database is not opened.
  /// Throws a [StateError] if a transaction is currently active.
  Future<void> vacuum() async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before executing VACUUM.');
    }
    if (_isInTransaction) {
      throw StateError('Cannot run VACUUM inside a transaction.');
    }
    await _acquireWriterLock();
    try {
      if (!isOpened()) {
        throw StateError('Database was closed while waiting for writer lock.');
      }
      await _platform.executeSql(_db!, 'VACUUM');
    } finally {
      _releaseWriterLock();
    }
  }
}
