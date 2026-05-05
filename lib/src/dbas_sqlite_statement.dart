import 'dart:async';
import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'package:dbas_sqlite/src/dbas_sqlite.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_db.dart'
    if (dart.library.js_interop) 'package:dbas_sqlite/src/stub/dbas_sqlite_db_stub.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_platform.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_reader.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';

/// A prepared SQL statement.
///
/// Owns its own bind buffers (positional + named) and dispatches
/// execution through the platform layer. Use [DbasSqlite.prepareQuery]
/// to obtain one — never construct directly.
///
/// The native handle is allocated lazily at execute time on the
/// connection appropriate for the execution mode (writer for
/// [executeSql], pool reader for [executeReader] outside transactions,
/// writer inside transactions). Bind values are buffered Dart-side
/// and replayed onto the freshly-prepared handle on every execute,
/// so the same statement object can be reused with new values.
///
/// On failure, the bind buffers are preserved so the caller can fix
/// one slot and retry without re-binding everything else.
///
/// Closing the statement closes any active reader. Closing the owning
/// [DbasSqlite] auto-closes every still-open statement.
class DbasSqliteStatement {
  final DbasSqlite _db;
  final DbasSqlitePlatform _platform;
  final String _sql;

  List<Object?> _positionalBinds = [];
  Map<String, Object?> _namedBinds = {};

  DbasSqliteReader? _activeReader;
  bool _closed = false;
  int _lastAffectedRows = -1;
  int _lastInsertedId = -1;
  String? _lastError;

  /// Internal — see [DbasSqlite.prepareQuery].
  DbasSqliteStatement.internal(
    this._db,
    this._platform,
    this._sql,
  );

  /// The SQL text used to prepare this statement.
  String get sql => _sql;

  /// `true` after [close] has been called or after the database
  /// closed and invalidated this statement.
  bool get isClosed => _closed;

  // ── Bindings (positional, fluent) ────────────────────────────────────

  DbasSqliteStatement bindNull(int index) {
    _ensurePositionalSlot(index);
    _positionalBinds[index - 1] = null;
    return this;
  }

  DbasSqliteStatement bindBool(int index, bool value) =>
      bindInt(index, value ? 1 : 0);

  DbasSqliteStatement bindInt(int index, int value) {
    _ensurePositionalSlot(index);
    _positionalBinds[index - 1] = value;
    return this;
  }

  DbasSqliteStatement bindFloat(int index, double value) {
    _ensurePositionalSlot(index);
    _positionalBinds[index - 1] = value;
    return this;
  }

  DbasSqliteStatement bindDouble(int index, double value) {
    _ensurePositionalSlot(index);
    _positionalBinds[index - 1] = value;
    return this;
  }

  DbasSqliteStatement bindDecimal(int index, Decimal value) {
    _ensurePositionalSlot(index);
    _positionalBinds[index - 1] = value;
    return this;
  }

  DbasSqliteStatement bindText(int index, String value) {
    _ensurePositionalSlot(index);
    _positionalBinds[index - 1] = value;
    return this;
  }

  DbasSqliteStatement bindBlob(int index, Uint8List value) {
    _ensurePositionalSlot(index);
    _positionalBinds[index - 1] = value;
    return this;
  }

  DbasSqliteStatement bindEnum(int index, Enum value) {
    _ensurePositionalSlot(index);
    _positionalBinds[index - 1] = value;
    return this;
  }

  /// Replaces the entire positional buffer.
  DbasSqliteStatement bindParameters(List<Object?> params) {
    _positionalBinds = List.of(params);
    return this;
  }

  void _ensurePositionalSlot(int index) {
    while (_positionalBinds.length < index) {
      _positionalBinds.add(null);
    }
  }

  // ── Bindings (named, fluent) ─────────────────────────────────────────

  DbasSqliteStatement bindNameNull(String name) {
    _namedBinds[name] = null;
    return this;
  }

  DbasSqliteStatement bindNameBool(String name, bool value) =>
      bindNameInt(name, value ? 1 : 0);

  DbasSqliteStatement bindNameInt(String name, int value) {
    _namedBinds[name] = value;
    return this;
  }

  DbasSqliteStatement bindNameFloat(String name, double value) {
    _namedBinds[name] = value;
    return this;
  }

  DbasSqliteStatement bindNameDouble(String name, double value) {
    _namedBinds[name] = value;
    return this;
  }

  DbasSqliteStatement bindNameDecimal(String name, Decimal value) {
    _namedBinds[name] = value;
    return this;
  }

  DbasSqliteStatement bindNameText(String name, String value) {
    _namedBinds[name] = value;
    return this;
  }

  DbasSqliteStatement bindNameBlob(String name, Uint8List value) {
    _namedBinds[name] = value;
    return this;
  }

  DbasSqliteStatement bindNameEnum(String name, Enum value) {
    _namedBinds[name] = value;
    return this;
  }

  /// Replaces the entire named buffer.
  ///
  /// **Note:** at execute time, named parameters that don't appear in
  /// the prepared SQL are silently skipped (SQLITE_RANGE), matching
  /// `Microsoft.Data.Sqlite` behaviour. Set
  /// [DbasSqlite.throwOnMissingNamedParams] to `true` to convert
  /// missing names into an exception.
  DbasSqliteStatement bindNameParameters(Map<String, Object?> params) {
    _namedBinds = Map.of(params);
    return this;
  }

  // ── Execution: SQL (write / DDL / DML) ───────────────────────────────

  /// Executes the prepared statement as DML/DDL. Returns affected
  /// rows. Pass [params] / [nameParams] to replace the bind buffer
  /// before execution (mirroring the v2.3.x convenience shape).
  ///
  /// The Dart-side bind buffer is preserved on failure — fix the
  /// offending value and call again without re-binding the rest.
  Future<int> executeSql({
    List<Object?>? params,
    Map<String, Object?>? nameParams,
  }) async {
    _checkUsable();
    // Snapshot the buffers so a thrown execute restores the previous
    // bind state — honouring the docstring promise that the caller
    // can fix one slot and retry without re-binding everything.
    final positionalSnapshot = List<Object?>.of(_positionalBinds);
    final namedSnapshot = Map<String, Object?>.of(_namedBinds);
    if (params != null) _positionalBinds = List.of(params);
    if (nameParams != null) _namedBinds = Map.of(nameParams);

    try {
      if (kIsWeb) {
        return await _executeSqlWeb();
      }
      return await _executeSqlNative();
    } catch (_) {
      _positionalBinds = positionalSnapshot;
      _namedBinds = namedSnapshot;
      rethrow;
    }
  }

  Future<int> _executeSqlNative() async {
    final lockHeld = _db.isInTransaction;
    if (!lockHeld) await _db.acquireWriterLockInternal();

    final conn = _db.dbInternal!;
    int handle = sqliteInvalidStmtHandle;
    try {
      final prepared = await _platform.prepareQuery(conn, _sql);
      handle = prepared.handle;
      if (handle == sqliteInvalidStmtHandle) {
        final err = _platform.getLastDbError(conn) ?? 'Unknown error.';
        throw Exception('It was not possible to prepare the query: $err');
      }

      try {
        await _replayBindsNative(conn, handle);

        final cache = RowData();
        final rc = await _platform.readRowAndCache(conn, handle, cache);
        if (rc != sqliteOk && rc != sqliteRow && rc != sqliteDone) {
          final err = _platform.getLastStmtError(conn, handle) ??
              'Unknown error ($rc).';
          throw Exception('It was not possible to run the query ($rc): $err');
        }

        // Counters MUST be read BEFORE finalize. After finalize the
        // handle is removed from the C lib's liveStmts map and any
        // subsequent stmt-scoped accessor returns the stale-handle
        // sentinel (-1).
        _lastAffectedRows = _platform.getStmtAffectedRows(conn, handle);
        _lastInsertedId = _platform.getStmtLastInsertedId(conn, handle);
        return rc == sqliteRow ? 0 : _lastAffectedRows;
      } finally {
        if (handle != sqliteInvalidStmtHandle) {
          try {
            await _platform.finalizeStmt(conn, handle);
          } catch (e, st) {
            developer.log(
              'finalizeStmt failed during executeSql cleanup',
              name: 'dbas_sqlite.DbasSqliteStatement',
              error: e,
              stackTrace: st,
            );
          }
        }
      }
    } finally {
      if (!lockHeld) _db.releaseWriterLockInternal();
    }
  }

  Future<int> _executeSqlWeb() async {
    final delegate = _platform.delegate(_db.dbName) as dynamic;
    final result = await delegate.executeStatementWrite(_sql, _mergedParams());
    _lastAffectedRows = result.affectedRows as int;
    _lastInsertedId = result.lastInsertedId as int;
    return _lastAffectedRows;
  }

  Future<void> _replayBindsNative(DbasSqliteDb conn, int handle) async {
    for (int i = 0; i < _positionalBinds.length; i++) {
      final index = i + 1;
      final value = _positionalBinds[i];
      final rc = await _bindPositional(conn, handle, index, value);
      if (rc != sqliteOk) {
        final err = _platform.getLastStmtError(conn, handle) ??
            'Bind failed at positional index $index ($rc).';
        throw Exception('Bind failed at positional index $index: $err');
      }
    }
    for (final entry in _namedBinds.entries) {
      String name = entry.key;
      if (!name.startsWith(':') && !name.startsWith('@') && !name.startsWith(r'$')) {
        name = ':$name';
      }
      final rc = await _bindNamed(conn, handle, name, entry.value);
      if (rc == sqliteRange) {
        if (_db.throwOnMissingNamedParams) {
          throw Exception("Named parameter '$name' not found in the prepared statement");
        }
        continue;
      }
      if (rc != sqliteOk) {
        final err = _platform.getLastStmtError(conn, handle) ??
            'Bind failed for named parameter "$name" ($rc).';
        throw Exception('Bind failed for "$name": $err');
      }
    }
  }

  Future<int> _bindPositional(
      DbasSqliteDb conn, int handle, int index, Object? value) {
    if (value == null) return _platform.bindNull(conn, handle, index);
    if (value is bool) {
      return _platform.bindInt(conn, handle, index, value ? 1 : 0);
    }
    if (value is int) {
      // Route through Int64 for values outside Int32 range.
      if (value > 0x7fffffff || value < -0x80000000) {
        return _platform.bindInt64(conn, handle, index, value);
      }
      return _platform.bindInt(conn, handle, index, value);
    }
    if (value is double) return _platform.bindDouble(conn, handle, index, value);
    if (value is Decimal) {
      return _platform.bindText(conn, handle, index, value.toString());
    }
    if (value is String) return _platform.bindText(conn, handle, index, value);
    if (value is Uint8List) {
      return _platform.bindBlob(conn, handle, index, value);
    }
    if (value is List<int>) {
      return _platform.bindBlob(conn, handle, index, value);
    }
    if (value is Enum) {
      return _platform.bindInt(conn, handle, index, value.index);
    }
    throw UnsupportedError('Unsupported type to SQLite bind: ${value.runtimeType}');
  }

  Future<int> _bindNamed(
      DbasSqliteDb conn, int handle, String name, Object? value) {
    if (value == null) return _platform.bindNameNull(conn, handle, name);
    if (value is bool) {
      return _platform.bindNameInt(conn, handle, name, value ? 1 : 0);
    }
    if (value is int) {
      if (value > 0x7fffffff || value < -0x80000000) {
        return _platform.bindNameInt64(conn, handle, name, value);
      }
      return _platform.bindNameInt(conn, handle, name, value);
    }
    if (value is double) {
      return _platform.bindNameDouble(conn, handle, name, value);
    }
    if (value is Decimal) {
      return _platform.bindNameText(conn, handle, name, value.toString());
    }
    if (value is String) {
      return _platform.bindNameText(conn, handle, name, value);
    }
    if (value is Uint8List) {
      return _platform.bindNameBlob(conn, handle, name, value);
    }
    if (value is List<int>) {
      return _platform.bindNameBlob(conn, handle, name, value);
    }
    if (value is Enum) {
      return _platform.bindNameInt(conn, handle, name, value.index);
    }
    throw UnsupportedError('Unsupported type to SQLite named bind: ${value.runtimeType}');
  }

  /// Web-only: merge positional + named into a single payload that
  /// the JS pool's exec/query understand. Positional wins if both are
  /// set; if only named is set, we send a JS object with auto-prefixed
  /// keys.
  dynamic _mergedParams() {
    if (_positionalBinds.isNotEmpty) {
      return _positionalBinds.map(_jsifyBindValue).toList();
    }
    if (_namedBinds.isNotEmpty) {
      final out = <String, dynamic>{};
      for (final e in _namedBinds.entries) {
        String name = e.key;
        if (!name.startsWith(':') && !name.startsWith('@') && !name.startsWith(r'$')) {
          name = ':$name';
        }
        out[name] = _jsifyBindValue(e.value);
      }
      return out;
    }
    return null;
  }

  Object? _jsifyBindValue(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is Decimal) return value.toString();
    if (value is Enum) return value.index;
    // Blobs MUST cross the postMessage boundary as a typed-array so
    // the JS wrapper's bindParams recognises them via
    // `instanceof Uint8Array` and routes through bindBlob. A raw
    // `List<int>` jsifies to a regular JS Array and gets stringified
    // by the bindText fallback, silently corrupting the bytes.
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return value;
  }

  // ── Execution: reader ────────────────────────────────────────────────

  /// Executes the prepared statement as a SELECT and returns a
  /// [DbasSqliteReader] for row-by-row iteration.
  ///
  /// Connection routing:
  ///   - **Native, outside a transaction**: blocking-acquires a pool
  ///     reader (default 30 s timeout). On timeout, throws
  ///     [TimeoutException]; the statement remains in a clean,
  ///     retriable state.
  ///   - **Native, inside a transaction**: uses the writer connection
  ///     (lock already held by `beginTransaction`).
  ///   - **Web, outside a transaction**: dispatches `pool.query` to a
  ///     reader worker. Rows are pre-buffered in Dart.
  ///   - **Web, inside a transaction**: dispatches `pool.exec` (writer
  ///     worker, EXCLUSIVE MRSW fence) so reads observe in-flight
  ///     transactional state.
  ///
  /// Only one reader may be active per statement at a time. Throws
  /// [StateError] if a reader is already active.
  Future<DbasSqliteReader> executeReader({
    List<Object?>? params,
    Map<String, Object?>? nameParams,
  }) async {
    _checkUsable();
    if (_activeReader != null && !_activeReader!.isClosed) {
      throw StateError('A reader from this statement is still active.');
    }
    // Snapshot for restore-on-failure — same rationale as executeSql.
    final positionalSnapshot = List<Object?>.of(_positionalBinds);
    final namedSnapshot = Map<String, Object?>.of(_namedBinds);
    if (params != null) _positionalBinds = List.of(params);
    if (nameParams != null) _namedBinds = Map.of(nameParams);

    try {
      if (kIsWeb) {
        return await _executeReaderWeb();
      }
      return await _executeReaderNative();
    } catch (_) {
      _positionalBinds = positionalSnapshot;
      _namedBinds = namedSnapshot;
      rethrow;
    }
  }

  Future<DbasSqliteReader> _executeReaderNative() async {
    final inTx = _db.isInTransaction;
    final DbasSqliteDb conn;
    final Future<void> Function() releaseFn;

    if (inTx) {
      conn = _db.dbInternal!;
      releaseFn = () async {};
    } else if (_db.poolPtrInternal != null) {
      final timeout = _db.poolAcquireTimeoutMsInternal;
      final readerPtr = await _platform.poolAcquireReaderBlocking(
          _db.dbName, _db.poolPtrInternal!, timeout);
      if (readerPtr == 0) {
        throw TimeoutException(
          'No pool reader became available within ${timeout}ms — '
          'all readers busy. Close in-flight readers or raise '
          'DbasSqlite.kPoolAcquireTimeoutMs.',
        );
      }
      conn = DbasSqliteDb(_db.dbName, readerPtr);
      releaseFn = () async {
        _platform.poolReleaseReader(_db.dbName, _db.poolPtrInternal!, readerPtr);
      };
    } else {
      // Single-connection fallback: use writer with the writer lock.
      await _db.acquireWriterLockInternal();
      conn = _db.dbInternal!;
      releaseFn = () async {
        _db.releaseWriterLockInternal();
      };
    }

    int handle = sqliteInvalidStmtHandle;
    bool transferred = false;
    try {
      final prepared = await _platform.prepareQuery(conn, _sql);
      handle = prepared.handle;
      if (handle == sqliteInvalidStmtHandle) {
        final err = _platform.getLastDbError(conn) ?? 'Unknown error.';
        throw Exception('It was not possible to prepare the query: $err');
      }

      await _replayBindsNative(conn, handle);

      final reader = DbasSqliteReader.internal(
        conn: conn,
        handle: handle,
        platform: _platform,
        // Pre-populate the reader's cache with column metadata
        // captured at prepare time so getColumnCount / getColumnName
        // work BEFORE the first readRow call.
        initialColumnCount: prepared.columnCount,
        initialColumnNames: prepared.columnNames,
        onClose: () async {
          // Order is load-bearing: read counters BEFORE finalize, then
          // release. We track the first error and log subsequent ones
          // so no failure is silently dropped if multiple steps fail.
          Object? firstErr;
          StackTrace? firstStack;
          try {
            _lastAffectedRows = _platform.getStmtAffectedRows(conn, handle);
            _lastInsertedId = _platform.getStmtLastInsertedId(conn, handle);
            _lastError = _platform.getLastStmtError(conn, handle);
          } catch (e, st) {
            firstErr = e;
            firstStack = st;
            developer.log(
              'reader onClose: counter read failed',
              name: 'dbas_sqlite.DbasSqliteStatement',
              error: e,
              stackTrace: st,
            );
          }
          try {
            await _platform.finalizeStmt(conn, handle);
          } catch (e, st) {
            firstErr ??= e;
            firstStack ??= st;
            developer.log(
              'reader onClose: finalizeStmt failed',
              name: 'dbas_sqlite.DbasSqliteStatement',
              error: e,
              stackTrace: st,
            );
          }
          try {
            await releaseFn();
          } catch (e, st) {
            firstErr ??= e;
            firstStack ??= st;
            developer.log(
              'reader onClose: releaseFn failed',
              name: 'dbas_sqlite.DbasSqliteStatement',
              error: e,
              stackTrace: st,
            );
          }
          _activeReader = null;
          if (firstErr != null) {
            Error.throwWithStackTrace(firstErr, firstStack!);
          }
        },
      );
      _activeReader = reader;
      transferred = true;
      return reader;
    } finally {
      // If we never got far enough to transfer ownership to a reader,
      // unwind everything we acquired in this scope. The primary
      // error is already in flight; cleanup failures are logged so
      // they don't go unnoticed but don't replace the original error.
      if (!transferred) {
        if (handle != sqliteInvalidStmtHandle) {
          try {
            await _platform.finalizeStmt(conn, handle);
          } catch (e, st) {
            developer.log(
              'finalizeStmt failed during executeReader bailout',
              name: 'dbas_sqlite.DbasSqliteStatement',
              error: e,
              stackTrace: st,
            );
          }
        }
        try {
          await releaseFn();
        } catch (e, st) {
          developer.log(
            'releaseFn failed during executeReader bailout',
            name: 'dbas_sqlite.DbasSqliteStatement',
            error: e,
            stackTrace: st,
          );
        }
      }
    }
  }

  Future<DbasSqliteReader> _executeReaderWeb() async {
    final delegate = _platform.delegate(_db.dbName) as dynamic;
    final buffer = await delegate.executeStatementRead(
      _sql,
      _mergedParams(),
      inTransaction: _db.isInTransaction,
    );
    final reader = DbasSqliteReader.internal(
      conn: _db.dbInternal!,
      handle: sqliteInvalidStmtHandle, // unused on web pool path
      platform: _platform,
      webBuffer: buffer,
      onClose: () async {
        _activeReader = null;
      },
    );
    _activeReader = reader;
    return reader;
  }

  // ── Per-stmt state ───────────────────────────────────────────────────

  /// Affected rows from the most recent successful execute. -1 if the
  /// statement has never been successfully stepped.
  int getAffectedRows() => _lastAffectedRows;

  /// rowid of the most recent successful insert through this
  /// statement. -1 if never successfully stepped or the SQL is not
  /// an INSERT.
  int getLastInsertedId() => _lastInsertedId;

  /// Most recent statement-scoped error message. `null` when no
  /// error is pending.
  String? getLastError() => _lastError;

  // ── Lifecycle ────────────────────────────────────────────────────────

  /// Closes any active reader, clears the bind buffers, and marks the
  /// statement closed. Idempotent. Subsequent execute calls throw
  /// [StateError].
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final reader = _activeReader;
    if (reader != null && !reader.isClosed) {
      try {
        await reader.close();
      } catch (e, st) {
        developer.log(
          'reader.close failed during statement close',
          name: 'dbas_sqlite.DbasSqliteStatement',
          error: e,
          stackTrace: st,
        );
      }
    }
    _positionalBinds = const [];
    _namedBinds = const {};
    _db.unregisterStatementInternal(this);
  }

  void _checkUsable() {
    if (_closed) throw StateError('Statement is closed.');
    if (!_db.isOpened()) {
      throw StateError('Database is not opened.');
    }
  }
}
