import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:dbas_sqlite/src/dbas_sqlite_db.dart'
    if (dart.library.js_interop) 'package:dbas_sqlite/src/stub/dbas_sqlite_db_stub.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_platform.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_statement.dart';
import 'package:dbas_sqlite/src/exceptions/dbas_sqlite_exception.dart';
import 'package:dbas_sqlite/src/helpers/paths/dbas_sqlite_paths.dart' as paths;
import 'package:dbas_sqlite/src/helpers/dbas_sqlite_platform_util.dart';
import 'package:dbas_sqlite/src/native/dbas_sqlite_native_interface.dart';
import 'package:flutter/foundation.dart';

/// A cross-platform SQLite database wrapper for Flutter.
///
/// Provides a unified API to interact with SQLite databases on
/// Android, iOS, macOS, Linux, Windows and Web platforms.
///
/// Uses a singleton pattern per database name — calling [getInstance]
/// with the same `dbName` always returns the same instance.
///
/// ```dart
/// final db = await DbasSqlite.getInstance(dbName: 'myapp.db');
/// await db.openDb();
///
/// // Write
/// final stmt = await db.prepareQuery(
///   'INSERT INTO users (name, email) VALUES (?, ?)',
/// );
/// await stmt.executeSql(params: ['John', 'john@example.com']);
/// final id = stmt.getLastInsertedId();
/// await stmt.close();
///
/// // Read
/// final readStmt = await db.prepareQuery(
///   'SELECT * FROM users WHERE id > ?',
/// );
/// final reader = await readStmt.executeReader(params: [0]);
/// while (await reader.readRow()) {
///   print(reader.getColumnText(0));
/// }
/// await reader.close();
/// await readStmt.close();
///
/// await db.closeDb();
/// ```
class DbasSqlite {
  /// Default timeout for `PoolAcquireReaderBlocking` when an
  /// `executeReader` must wait for a free pool slot. The C-side
  /// condvar is signalled on every reader release so this is a
  /// pure deadline, not a polling loop.
  static const int kPoolAcquireTimeoutMs = 30000;

  /// Default per-slot timeout when [setBusyTimeout] reconfigures
  /// pool readers. Shorter than [kPoolAcquireTimeoutMs] because
  /// reconfiguration is best-effort and the user should know quickly
  /// when readers are too contended.
  static const int kSetBusyTimeoutAcquireMs = 5000;

  /// Test-only override for [kPoolAcquireTimeoutMs]. Setting this in
  /// production code is a smell; the field exists so timeout-path
  /// tests complete in milliseconds.
  @visibleForTesting
  static int? debugPoolAcquireTimeoutMs;

  /// Test-only override for [kSetBusyTimeoutAcquireMs]. Same rationale
  /// as [debugPoolAcquireTimeoutMs] — without this, the busy-reader
  /// negative test would pause for 5 s on every run.
  @visibleForTesting
  static int? debugSetBusyTimeoutAcquireMs;

  static final Map<String, DbasSqlite> _instance = {};

  final DbasSqlitePlatform _platform;
  final String dbName;
  DbasSqliteDb? _db;
  bool _isInTransaction = false;
  // Set when an `executeSql` runs while a transaction is active, so
  // subsequent `executeReader` / `executeScalar` calls in the same tx
  // route through the writer connection (read-your-writes). Cleared on
  // begin/commit/rollback. The flag is only read by the statement layer.
  bool _transactionHasWrites = false;
  int? _poolPtr;
  /// Reader count requested at openDb time; used by
  /// [setBusyTimeout] to bound its reader-reconfiguration loop. `0`
  /// when the pool wasn't created (single-connection fallback).
  int _readerPoolSize = 0;
  final Set<DbasSqliteStatement> _activeStatements = {};
  final Queue<Completer<void>> _writerWaitQueue = Queue<Completer<void>>();
  bool _writerLockHeld = false;
  // Dart-level FIFO semaphore that gates entry to
  // `poolAcquireReaderBlocking`. Capacity is set to [_readerPoolSize]
  // on openDb, so at most that many concurrent C-level blocking
  // acquires can be in flight. Without this gate, a `Future.wait` of
  // many `executeReader` calls fans out one blocking acquire per
  // call across the worker isolates; once every worker is parked
  // inside `pool_acquire_reader_blocking`, no worker remains to
  // process `prepareQuery` / `finalizeStmt` for in-flight reads, so
  // no reader is ever released and the pool deadlocks until the
  // 30 s C-side timeout fires. The gate caps concurrent blocking
  // acquires at [_readerPoolSize]; with the worker pool sized at
  // `readerPoolSize + 2`, at least two workers are always available
  // for the non-blocking read steps. Excess callers wait here in
  // Dart microtasks instead of occupying a worker.
  int _readerSlotsAvailable = 0;
  final Queue<Completer<void>> _readerSlotWaitQueue = Queue<Completer<void>>();

  /// When `true`, binding a named parameter that does not exist in
  /// the prepared statement throws an exception instead of silently
  /// skipping it. Defaults to `false` (C#/SQLite-compatible behaviour).
  bool throwOnMissingNamedParams = false;

  DbasSqlite._dbasSqlite(this._platform, this.dbName,
      {this.throwOnMissingNamedParams = false});

  /// Returns a singleton instance of [DbasSqlite] for the given
  /// [dbName]. Defaults to `'dbas.db'`.
  static Future<DbasSqlite> getInstance({
    String dbName = 'dbas.db',
    bool throwOnMissingNamedParams = false,
    int workerPoolSize = 4,
  }) async {
    if (_instance.containsKey(dbName)) {
      assert(
        workerPoolSize == DbasSqliteNativeInterface.workerPoolSize,
        'DbasSqlite.getInstance: workerPoolSize=$workerPoolSize was passed for '
        'an already-initialized instance of "$dbName" (current pool size is '
        '${DbasSqliteNativeInterface.workerPoolSize}).',
      );
      _instance[dbName]!.throwOnMissingNamedParams = throwOnMissingNamedParams;
      return _instance[dbName]!;
    }

    DbasSqliteNativeInterface.workerPoolSize = workerPoolSize;
    _instance[dbName] = DbasSqlite._dbasSqlite(
      await DbasSqlitePlatform.getInstance(dbName: dbName),
      dbName,
      throwOnMissingNamedParams: throwOnMissingNamedParams,
    );
    return _instance[dbName]!;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  /// Returns the full filesystem path for the database.
  Future<String> getAppDatabasePath({String? dbName}) async {
    dbName ??= this.dbName;
    final dbPath = await paths.resolveDatabaseDirectory(
      isTest: DbasSqlitePlatformUtil.isTest(),
    );
    return '$dbPath/$dbName';
  }

  /// Checks whether the database file exists on disk (or in OPFS on web).
  Future<bool> databaseExists() async {
    final fileName = await getAppDatabasePath(dbName: dbName);
    return await _platform.databaseExists(fileName);
  }

  /// Attaches a database from bytes and optionally opens it.
  ///
  /// **Eager input**: the caller passes the full database content as
  /// a single in-memory buffer. For multi-hundred-MB imports prefer
  /// [attachStreamDb], which writes chunks incrementally without
  /// holding the whole file in memory.
  Future<DbasSqlite> attachDb(List<int> bytes, {bool openDb = true}) async {
    if (_instance.containsKey(dbName)) {
      if (_instance[dbName]!.isOpened()) {
        await _instance[dbName]!.closeDb();
      }
      _instance.remove(dbName);
    }

    final fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.attachDb(fileName, bytes);
    final instance = await getInstance(dbName: dbName);
    if (openDb) await instance.openDb();
    return instance;
  }

  /// Attaches a database from a byte stream and optionally opens it.
  ///
  /// **Streaming input**: chunks are written incrementally as they
  /// arrive from [stream]. Native pipes them through
  /// `File.openWrite()`; web sends each chunk via the worker's
  /// chunked-attach protocol with per-chunk ACK backpressure, so the
  /// worker holds at most one chunk at a time. Use this for imports
  /// large enough that the in-memory [attachDb] would be wasteful.
  Future<DbasSqlite> attachStreamDb(Stream<List<int>> stream,
      {bool openDb = true}) async {
    if (_instance.containsKey(dbName)) {
      if (_instance[dbName]!.isOpened()) {
        await _instance[dbName]!.closeDb();
      }
      _instance.remove(dbName);
    }

    final fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.attachStreamDb(fileName, stream);
    final instance = await getInstance(dbName: dbName);
    if (openDb) await instance.openDb();
    return instance;
  }

  /// Copies the current database to a new database with the given
  /// [destDbName]. Streamed chunk-by-chunk.
  Future<void> streamCopyDb(String destDbName) async {
    final src = await getAppDatabasePath(dbName: dbName);
    final dest = await getAppDatabasePath(dbName: destDbName);
    await _platform.streamCopyDb(src, dest);
  }

  /// Returns the raw bytes of the database file.
  ///
  /// **Eager**: the full database content is materialised in Dart
  /// memory before this future completes. For large databases (more
  /// than a few hundred MB) prefer [streamCopyDb] to copy the file
  /// into another OPFS / filesystem location without round-tripping
  /// the bytes through the Dart heap, or feed [attachStreamDb] from
  /// a real source stream when re-importing.
  Future<List<int>> getContent() async {
    final fileName = await getAppDatabasePath(dbName: dbName);
    return await _platform.getContent(fileName);
  }

  /// Deletes the database file (including WAL and SHM journal files).
  Future<void> dropDb() async {
    if (!await databaseExists()) return;
    if (isOpened()) await closeDb();

    final fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.dropDb(fileName);
  }

  /// Opens the database using a connection pool with WAL mode.
  ///
  /// Creates one writer connection and [readerPoolSize] read-only
  /// readers. Falls back to a single connection if pool creation
  /// fails.
  ///
  /// **Idempotent.** Calling `openDb()` on an already-open instance is
  /// a no-op and returns immediately. Calling it with a different
  /// [readerPoolSize] than the original open throws a
  /// [DbasSqliteException] with code
  /// [DbasSqliteErrorCode.openDbReopenWithDifferentPoolSize] — pool
  /// resizing isn't supported; close the database first if you need to
  /// change the pool size.
  Future<void> openDb({int readerPoolSize = 4}) async {
    if (isOpened()) {
      if (readerPoolSize != _readerPoolSize) {
        throw DbasSqliteException.dart(
          DbasSqliteErrorCode.openDbReopenWithDifferentPoolSize,
          'openDb("$dbName") was called with readerPoolSize=$readerPoolSize '
          'but the database is already opened with readerPoolSize=$_readerPoolSize. '
          'Close the database before re-opening with a different pool size.',
        );
      }
      return;
    }

    final fileName = await getAppDatabasePath(dbName: dbName);

    if (readerPoolSize > 0) {
      final poolPtr = await _platform.createPool(dbName, fileName, readerPoolSize);
      if (poolPtr != 0) {
        _poolPtr = poolPtr;
        _readerPoolSize = readerPoolSize;
        _readerSlotsAvailable = readerPoolSize;
        final writerPtr = _platform.poolGetWriter(dbName, poolPtr);
        _db = DbasSqliteDb(dbName, writerPtr);
        return;
      }
    }

    _readerPoolSize = 0;
    _readerSlotsAvailable = 0;
    _db = await _platform.openDb(fileName);
  }

  /// Returns `true` if the database connection is currently open.
  bool isOpened() => _db != null && _platform.isOpened(_db!);

  /// Closes the database connection and removes the instance from
  /// the cache. Active readers and statements are closed first.
  /// Active transactions are rolled back.
  ///
  /// If the in-flight `rollback()` itself fails (e.g. the connection
  /// is already in a corrupt state at the SQLite layer), the failure
  /// is logged via `dart:developer` and teardown continues — otherwise
  /// a single rollback failure would skip statement cleanup, queue
  /// cancellation, and pool close, leaving the cache and OS resources
  /// dangling. Code that needs to react to a failed rollback must call
  /// `rollback()` explicitly before `closeDb()`.
  Future<void> closeDb() async {
    try {
      await rollback();
    } catch (e, st) {
      developer.log(
        'closeDb: rollback of in-flight transaction failed; '
        'continuing teardown',
        name: 'dbas_sqlite.DbasSqlite',
        error: e,
        stackTrace: st,
      );
    }

    // Close every still-open statement (which closes its active reader
    // if any). List.of() snapshots the set since close() mutates it.
    int stmtCloseFailures = 0;
    for (final stmt in List.of(_activeStatements)) {
      try {
        await stmt.close();
      } catch (e, st) {
        stmtCloseFailures++;
        developer.log(
          'closeDb: statement close failed for "$dbName"',
          name: 'dbas_sqlite.DbasSqlite',
          error: e,
          stackTrace: st,
        );
      }
    }
    _activeStatements.clear();

    _cancelWriterWaitQueue();
    _cancelReaderSlotWaitQueue();

    if (_instance.containsKey(dbName)) {
      _instance.remove(dbName);
    }

    if (_poolPtr != null) {
      // ClosePool force-drains any handles we missed (defensive).
      await _platform.closePool(dbName, _poolPtr!);
      _poolPtr = null;
      _db = null;
    } else if (_db != null) {
      // Single-connection fallback. Tracked statements above should
      // have finalised every handle; if CloseDb returns SQLITE_BUSY
      // it means at least one handle is still live — either tracked
      // statements that failed to finalise (stmtCloseFailures > 0) or
      // a handle leaked outside our tracking. Surface the right one.
      final rc = await _platform.closeDb(_db!, checkpoint: false);
      if (rc == sqliteBusy) {
        final err = _platform.getLastDbError(_db!) ?? 'live handles';
        _db = null;
        if (stmtCloseFailures > 0) {
          throw DbasSqliteException.sqlite(
            DbasSqliteErrorCode.closeDbBusyWithStmtFinalizeFailures,
            rc,
            'Cannot close database "$dbName": $err. '
            '$stmtCloseFailures tracked statement(s) failed to finalize '
            '(see prior log entries for the underlying errors).',
          );
        }
        throw DbasSqliteException.sqlite(
          DbasSqliteErrorCode.closeDbBusyLeakedHandle,
          rc,
          'Cannot close database "$dbName": $err. '
          'A statement handle was leaked outside the tracked set; '
          'this is a bug — please report.',
        );
      }
      _db = null;
    }
  }

  // ── New: prepare / utilities ─────────────────────────────────────────

  /// Prepares a SQL statement. Returns a [DbasSqliteStatement] that
  /// owns parameter binding and execution.
  ///
  /// The statement holds the SQL until executed; the underlying
  /// native handle is allocated lazily at execute time on the
  /// connection appropriate for the execution mode (writer for
  /// `executeSql`, pool reader for `executeReader` outside
  /// transactions, writer inside transactions).
  ///
  /// Multiple statements may be prepared on the same `DbasSqlite`
  /// without blocking each other. Caller MUST call
  /// [DbasSqliteStatement.close] when done; closing the database
  /// auto-closes any still-open statements as a safety net.
  Future<DbasSqliteStatement> prepareQuery(String sql) async {
    if (!isOpened()) {
      throw DbasSqliteException.dart(
        DbasSqliteErrorCode.prepareQueryDatabaseNotOpened,
        'Database is not opened. Please open the database before preparing.',
      );
    }
    final stmt = DbasSqliteStatement.internal(this, _platform, sql);
    _activeStatements.add(stmt);
    return stmt;
  }

  /// Returns the runtime SQLite version (e.g. `"3.52.0"`).
  ///
  /// On native: cached during platform initialization (one FFI call
  /// during `getInstance`); subsequent calls return synchronously.
  ///
  /// On web: populated from `SELECT sqlite_version()` against the JS
  /// pool the first time `createPool` runs. Returns `''` until the
  /// pool exists (i.e. before `openDb`).
  String getSqliteVersion() => _platform.getSqliteVersion(dbName);

  /// Cumulative row-change counter for this connection
  /// (`sqlite3_total_changes64`). Returns `-1` if the database is not
  /// opened.
  ///
  /// **Web platform:** always returns `0` — the JS pool does not
  /// expose `sqlite3_total_changes`. Do not use this as a
  /// cache-invalidation or audit signal in code that runs on web.
  int getTotalChanges() {
    if (_db == null) return -1;
    return _platform.getTotalChanges(_db!);
  }

  /// File name used to open the connection. `null` if the database is
  /// not opened. The C string is copied into a Dart [String]
  /// immediately, so the value outlives the C buffer — safe to keep
  /// across `closeDb()`.
  String? getDbFileName() {
    if (_db == null) return null;
    return _platform.getDbFileName(_db!);
  }

  /// Override the SQLite busy-timeout (ms) on the writer and every
  /// pool reader.
  ///
  /// **Native:** holds each reader slot in turn for
  /// [kSetBusyTimeoutAcquireMs] before reconfiguring; throws a
  /// [DbasSqliteException] with code
  /// [DbasSqliteErrorCode.setBusyTimeoutReaderBusy] if any one slot is
  /// still busy after the timeout. Other failure codes from this method:
  /// [DbasSqliteErrorCode.setBusyTimeoutDatabaseNotOpened],
  /// [DbasSqliteErrorCode.setBusyTimeoutWriterFailed],
  /// [DbasSqliteErrorCode.setBusyTimeoutReaderFailed].
  /// Recommended: call at openDb time before any reads, or inside a
  /// `db.transaction(...)` block where readers are quiescent.
  ///
  /// **Web:** silent no-op. The JS pool has its own busy-handling
  /// model and does not expose a per-connection `busy_timeout`
  /// accessor. Apps relying on a specific busy-timeout value on web
  /// must not depend on this call to apply it.
  Future<void> setBusyTimeout(int ms) async {
    if (_db == null) {
      throw DbasSqliteException.dart(
        DbasSqliteErrorCode.setBusyTimeoutDatabaseNotOpened,
        'Database is not opened.',
      );
    }
    if (kIsWeb) {
      // The JS pool does not expose a per-connection busy_timeout
      // accessor; the writer worker manages its own busy handling.
      // Returning silently here is consistent with the JS pool's
      // model — there is nothing to do.
      return;
    }
    final rc = await _platform.setBusyTimeout(_db!, ms);
    if (rc != sqliteOk) {
      final err = _platform.getLastDbError(_db!) ?? 'rc=$rc';
      throw DbasSqliteException.sqlite(
        DbasSqliteErrorCode.setBusyTimeoutWriterFailed,
        rc,
        'setBusyTimeout failed on writer: $err',
      );
    }

    if (_poolPtr == null || _readerPoolSize == 0) return;

    // Hold all reader slots exclusively, then reconfigure each one
    // exactly once. Acquiring all up front prevents the same slot
    // from being reconfigured multiple times in a release-then-
    // re-acquire cycle. Release happens in the `finally` so a mid-
    // loop failure doesn't leak slots.
    final acquireMs =
        debugSetBusyTimeoutAcquireMs ?? kSetBusyTimeoutAcquireMs;
    final delegate = _platform.delegate(dbName);
    final acquired = <int>[];
    try {
      for (int i = 0; i < _readerPoolSize; i++) {
        final readerPtr =
            await delegate.poolAcquireReaderBlocking(_poolPtr!, acquireMs);
        if (readerPtr == 0) {
          throw DbasSqliteException.dart(
            DbasSqliteErrorCode.setBusyTimeoutReaderBusy,
            'setBusyTimeout: pool reader $i was busy for '
            '${acquireMs}ms — close in-flight readers first.',
          );
        }
        acquired.add(readerPtr);
      }
      for (final readerPtr in acquired) {
        final rrc = await _platform.setBusyTimeout(
            DbasSqliteDb(dbName, readerPtr), ms);
        if (rrc != sqliteOk) {
          throw DbasSqliteException.sqlite(
            DbasSqliteErrorCode.setBusyTimeoutReaderFailed,
            rrc,
            'setBusyTimeout failed on a pool reader: rc=$rrc',
          );
        }
      }
    } finally {
      for (final readerPtr in acquired) {
        delegate.poolReleaseReader(_poolPtr!, readerPtr);
      }
    }
  }

  /// Switches the writer to WAL journal mode and verifies the readback.
  ///
  /// **Native:** dispatches to the C lib's `EnableWal` (idempotent on
  /// a pool that's already in WAL).
  ///
  /// **Web:** runs `PRAGMA journal_mode` and verifies the result is
  /// `wal`. The JS pool always opens with WAL via the writer worker;
  /// this serves as a defensive check that pool initialization
  /// actually succeeded.
  ///
  /// Throws an exception when WAL cannot be activated (read-only
  /// media, unsupported VFS, or — on web — pool init silently
  /// failing to set WAL).
  Future<void> enableWal() async {
    if (_db == null) {
      throw DbasSqliteException.dart(
        DbasSqliteErrorCode.enableWalDatabaseNotOpened,
        'Database is not opened.',
      );
    }
    final rc = await _platform.enableWal(_db!);
    if (rc != sqliteOk) {
      final err = _platform.getLastDbError(_db!) ?? 'rc=$rc';
      throw DbasSqliteException.sqlite(
        DbasSqliteErrorCode.enableWalFailed,
        rc,
        'enableWal failed: $err',
      );
    }
  }

  // ── Transactions ─────────────────────────────────────────────────────

  /// Returns `true` if a transaction is currently active.
  bool get isInTransaction => _isInTransaction;

  /// Begins a new database transaction. Idempotent — does nothing if
  /// already inside a transaction.
  Future<void> beginTransaction() async {
    if (!isOpened()) {
      throw DbasSqliteException.dart(
        DbasSqliteErrorCode.beginTransactionDatabaseNotOpened,
        'Database is not opened. Please open the database before starting a transaction.',
      );
    }
    if (_isInTransaction) return;

    await _acquireWriterLock();
    try {
      if (!isOpened()) {
        throw DbasSqliteException.dart(
          DbasSqliteErrorCode.beginTransactionDatabaseClosedWaitingLock,
          'Database was closed while waiting for writer lock.',
        );
      }
      final rc = await _platform.executeSql(_db!, 'BEGIN TRANSACTION');
      if (rc != sqliteOk) {
        final err = _platform.getLastDbError(_db!) ?? 'rc=$rc';
        throw DbasSqliteException.sqlite(
          DbasSqliteErrorCode.beginTransactionFailed,
          rc,
          'BEGIN TRANSACTION failed: $err',
        );
      }
      _transactionHasWrites = false;
      _isInTransaction = true;
    } catch (_) {
      if (!_isInTransaction) _releaseWriterLock();
      rethrow;
    }
  }

  /// Commits the current transaction. No-op if no transaction is active.
  Future<void> commit() async {
    if (!_isInTransaction) return;
    try {
      final rc = await _platform.executeSql(_db!, 'COMMIT');
      if (rc != sqliteOk) {
        final err = _platform.getLastDbError(_db!) ?? 'rc=$rc';
        throw DbasSqliteException.sqlite(
          DbasSqliteErrorCode.commitFailed,
          rc,
          'COMMIT failed: $err',
        );
      }
      _isInTransaction = false;
      _transactionHasWrites = false;
      _releaseWriterLock();
    } catch (_) {
      await rollback();
      rethrow;
    }
  }

  /// Rolls back the current transaction. No-op if no transaction is active.
  ///
  /// If the underlying ROLLBACK fails (corrupt connection, lock loss),
  /// the Dart-side transaction flag is still cleared and the writer
  /// lock is released — but the failure is rethrown wrapped in a
  /// [DbasSqliteException] with code [DbasSqliteErrorCode.rollbackFailed]
  /// so the caller knows the C connection's autocommit state may be
  /// inconsistent. When the underlying cause is itself a
  /// [DbasSqliteException] its [DbasSqliteException.sqliteCode] is
  /// lifted onto the outer exception; the original error is attached
  /// as [DbasSqliteException.cause] for programmatic inspection.
  Future<void> rollback() async {
    if (!_isInTransaction) return;
    Object? rollbackCause;
    StackTrace? rollbackCauseStack;
    int? rollbackRc;
    String rollbackDetail = '';
    try {
      final rc = await _platform.executeSql(_db!, 'ROLLBACK');
      if (rc != sqliteOk) {
        final err = _platform.getLastDbError(_db!) ?? 'rc=$rc';
        rollbackRc = rc;
        rollbackDetail = 'ROLLBACK rc=$rc: $err';
        rollbackCauseStack = StackTrace.current;
      }
    } catch (e, st) {
      rollbackCause = e;
      rollbackCauseStack = st;
      rollbackDetail = e.toString();
      if (e is DbasSqliteException) {
        rollbackRc = e.sqliteCode;
      }
    } finally {
      _isInTransaction = false;
      _transactionHasWrites = false;
      _releaseWriterLock();
    }
    if (rollbackCauseStack != null) {
      final msg =
          'ROLLBACK failed; database may still be in a transaction: $rollbackDetail';
      final ex = rollbackRc != null
          ? DbasSqliteException.sqlite(
              DbasSqliteErrorCode.rollbackFailed,
              rollbackRc,
              msg,
              cause: rollbackCause,
              causeStackTrace: rollbackCauseStack,
            )
          : DbasSqliteException.dart(
              DbasSqliteErrorCode.rollbackFailed,
              msg,
              cause: rollbackCause,
              causeStackTrace: rollbackCauseStack,
            );
      Error.throwWithStackTrace(ex, rollbackCauseStack);
    }
  }

  /// Executes [action] within a database transaction with automatic
  /// commit and rollback. If [action] throws, the transaction is
  /// rolled back and the exception is rethrown.
  ///
  /// When BOTH [action] (or `commit`) and the subsequent `rollback`
  /// fail, a [DbasSqliteException] with code
  /// [DbasSqliteErrorCode.transactionRollbackAlsoFailed] is thrown.
  /// The original error is preserved on
  /// [DbasSqliteException.cause] with its stack trace on
  /// [DbasSqliteException.causeStackTrace]; the rollback failure is
  /// logged via `dart:developer` (its stack would otherwise be lost in
  /// the wrapper). When the original error is itself a
  /// [DbasSqliteException], its [DbasSqliteException.sqliteCode] is
  /// lifted onto the outer exception.
  Future<void> transaction(Future<void> Function(DbasSqlite db) action) async {
    if (_isInTransaction) {
      throw DbasSqliteException.dart(
        DbasSqliteErrorCode.transactionAlreadyActive,
        'A transaction is already active. Cannot nest transactions.',
      );
    }
    await beginTransaction();
    try {
      await action(this);
      await commit();
    } catch (originalError, originalStack) {
      try {
        await rollback();
      } catch (rollbackError, rollbackStack) {
        developer.log(
          'transaction: rollback failed after action/commit failure; '
          'wrapping into transactionRollbackAlsoFailed',
          name: 'dbas_sqlite.DbasSqlite',
          error: rollbackError,
          stackTrace: rollbackStack,
        );
        final liftedRc = originalError is DbasSqliteException
            ? originalError.sqliteCode
            : (rollbackError is DbasSqliteException
                ? rollbackError.sqliteCode
                : null);
        final msg = 'Transaction failed: $originalError. '
            'Additionally, rollback also failed: $rollbackError. '
            'The database may be in an inconsistent state.';
        final ex = liftedRc != null
            ? DbasSqliteException.sqlite(
                DbasSqliteErrorCode.transactionRollbackAlsoFailed,
                liftedRc,
                msg,
                cause: originalError,
                causeStackTrace: originalStack,
              )
            : DbasSqliteException.dart(
                DbasSqliteErrorCode.transactionRollbackAlsoFailed,
                msg,
                cause: originalError,
                causeStackTrace: originalStack,
              );
        Error.throwWithStackTrace(ex, originalStack);
      }
      rethrow;
    }
  }

  /// Rebuilds the database file via VACUUM. Cannot run inside a
  /// transaction.
  Future<void> vacuum() async {
    if (!isOpened()) {
      throw DbasSqliteException.dart(
        DbasSqliteErrorCode.vacuumDatabaseNotOpened,
        'Database is not opened.',
      );
    }
    if (_isInTransaction) {
      throw DbasSqliteException.dart(
        DbasSqliteErrorCode.vacuumInsideTransaction,
        'Cannot run VACUUM inside a transaction.',
      );
    }
    await _acquireWriterLock();
    try {
      if (!isOpened()) {
        throw DbasSqliteException.dart(
          DbasSqliteErrorCode.vacuumDatabaseClosedWaitingLock,
          'Database was closed while waiting for writer lock.',
        );
      }
      final rc = await _platform.executeSql(_db!, 'VACUUM');
      if (rc != sqliteOk) {
        final err = _platform.getLastDbError(_db!) ?? 'rc=$rc';
        throw DbasSqliteException.sqlite(
          DbasSqliteErrorCode.vacuumFailed,
          rc,
          'VACUUM failed: $err',
        );
      }
    } finally {
      _releaseWriterLock();
    }
  }

  // ── Async writer lock (FIFO) ─────────────────────────────────────────

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
        DbasSqliteException.dart(
          DbasSqliteErrorCode.writerLockWaitCancelled,
          'Database was closed while waiting for writer lock.',
        ),
      );
    }
    _writerLockHeld = false;
  }

  // ── Async reader-slot semaphore (FIFO) ───────────────────────────────

  /// Waits up to [timeoutMs] for a reader-slot to become available.
  /// Slots are released by [_releaseReaderSlot]. The release order is
  /// load-bearing: the C reader is returned to the pool BEFORE the
  /// Dart slot is released, so when the next caller's await resumes
  /// the C-side acquire is guaranteed to find a free reader.
  Future<void> _acquireReaderSlot(int timeoutMs) async {
    if (_readerSlotsAvailable > 0) {
      _readerSlotsAvailable--;
      return;
    }
    final waiter = Completer<void>();
    _readerSlotWaitQueue.add(waiter);
    Timer? timer;
    if (timeoutMs > 0) {
      timer = Timer(Duration(milliseconds: timeoutMs), () {
        if (waiter.isCompleted) return;
        _readerSlotWaitQueue.remove(waiter);
        waiter.completeError(DbasSqliteException.dart(
          DbasSqliteErrorCode.readerSlotWaitTimeout,
          'Dart-side reader-slot wait timed out after ${timeoutMs}ms — '
          'all pool readers are busy. Close in-flight readers or raise '
          'DbasSqlite.kPoolAcquireTimeoutMs.',
        ));
      });
    }
    try {
      await waiter.future;
    } finally {
      timer?.cancel();
    }
  }

  void _releaseReaderSlot() {
    if (_readerSlotWaitQueue.isNotEmpty) {
      _readerSlotWaitQueue.removeFirst().complete();
    } else {
      _readerSlotsAvailable++;
    }
  }

  void _cancelReaderSlotWaitQueue() {
    while (_readerSlotWaitQueue.isNotEmpty) {
      _readerSlotWaitQueue.removeFirst().completeError(
        DbasSqliteException.dart(
          DbasSqliteErrorCode.readerSlotWaitCancelled,
          'Database was closed while waiting for reader slot.',
        ),
      );
    }
    _readerSlotsAvailable = 0;
  }

  // ── Internal hooks for DbasSqliteStatement ───────────────────────────
  // These have visible names but are only intended for the
  // statement implementation.

  Future<void> acquireWriterLockInternal() => _acquireWriterLock();
  void releaseWriterLockInternal() => _releaseWriterLock();
  DbasSqliteDb? get dbInternal => _db;
  int? get poolPtrInternal => _poolPtr;
  bool get transactionHasWritesInternal => _transactionHasWrites;
  void markTransactionWriteInternal() {
    if (_isInTransaction) _transactionHasWrites = true;
  }
  int get poolAcquireTimeoutMsInternal =>
      debugPoolAcquireTimeoutMs ?? kPoolAcquireTimeoutMs;
  void unregisterStatementInternal(DbasSqliteStatement stmt) =>
      _activeStatements.remove(stmt);

  /// Acquires a pool-reader connection, gated by the Dart-level
  /// reader-slot semaphore so at most [_readerPoolSize] concurrent
  /// blocking acquires can be in flight against the C pool. Returns
  /// the reader pointer on success, or `0` if the C-side acquire
  /// timed out.
  ///
  /// Throws a [DbasSqliteException] with code
  /// [DbasSqliteErrorCode.readerSlotWaitTimeout] when the Dart-side
  /// wait exceeds [timeoutMs] (i.e. no slot freed in time), code
  /// [DbasSqliteErrorCode.readerSlotWaitCancelled] if the database is
  /// closed while waiting, or code
  /// [DbasSqliteErrorCode.acquireReaderConnectionNoPool] when called
  /// against a single-connection (non-pool) database.
  Future<int> acquireReaderConnectionInternal(int timeoutMs) async {
    if (_poolPtr == null) {
      throw DbasSqliteException.dart(
        DbasSqliteErrorCode.acquireReaderConnectionNoPool,
        'No reader pool — single-connection mode does not use this path.',
      );
    }
    final stopwatch = Stopwatch()..start();
    await _acquireReaderSlot(timeoutMs);
    try {
      // With the semaphore granting at most [_readerPoolSize] slots,
      // the C pool always has a reader available here. The remaining
      // budget is a safety net in case some other caller (e.g.
      // setBusyTimeout, which intentionally bypasses the semaphore)
      // is holding readers concurrently.
      //
      // `timeoutMs <= 0` is the documented "non-blocking" form on the
      // C side; passing it through unmodified preserves that
      // semantic. Otherwise clamp the elapsed-adjusted budget into
      // [1, timeoutMs] so the C call still gets a tick to make
      // progress even when the Dart wait consumed the full window.
      final int remaining = timeoutMs <= 0
          ? timeoutMs
          : (timeoutMs - stopwatch.elapsedMilliseconds).clamp(1, timeoutMs);
      final readerPtr = await _platform.poolAcquireReaderBlocking(
          dbName, _poolPtr!, remaining);
      if (readerPtr == 0) {
        _releaseReaderSlot();
        return 0;
      }
      return readerPtr;
    } catch (_) {
      _releaseReaderSlot();
      rethrow;
    }
  }

  /// Returns a reader pointer to the C pool and releases the
  /// Dart-level slot. Order matters: C release first so the next
  /// semaphore-granted caller finds the reader already available.
  void releaseReaderConnectionInternal(int readerPtr) {
    if (_poolPtr == null) return;
    _platform.poolReleaseReader(dbName, _poolPtr!, readerPtr);
    _releaseReaderSlot();
  }
}
