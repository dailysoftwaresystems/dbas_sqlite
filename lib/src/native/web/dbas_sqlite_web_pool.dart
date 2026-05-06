import 'dart:async';
import 'dart:developer' as developer;
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';
import 'package:dbas_sqlite/src/stub/dbas_sqlite_db_stub.dart'
    show sqliteRow, sqliteDone;

const _workerUrl = 'assets/packages/dbas_sqlite/web/libs/dbas_sqlite_worker.js';
// Relative to the worker script location (same directory), not the page root.
// importScripts() inside the worker resolves URLs relative to the worker URL.
const _libUrl = 'dbas_sqlite.js';

/// Raw property accessor for JS objects (avoids dartify on complex types
/// like ReadableStream that would lose their identity).
@JS()
extension type _JSObj._(JSObject _) implements JSObject {
  external JSAny? operator [](String key);
  external void operator []=(String key, JSAny? value);
}

/// JS `Number(value)` — converts BigInt, strings, etc. to a JS Number.
/// Used to safely extract int64 return values from Emscripten WASM exports
/// which may arrive as BigInt.
@JS('Number')
external JSNumber _jsToNumber(JSAny? value);

/// Per-DB web pool backed by a single Web Worker running `dbas_sqlite_worker.js`.
///
/// The worker loads the WASM module, initializes OPFS, and opens the database.
/// Inside the worker, `createPool(readerCount)` creates a WAL connection pool
/// with 1 writer + N readers — all within the same WASM instance.
///
/// Communication follows the protocol from the DBAS.SQLite worker:
///   init, exec, query, batch, drop, attachStreamBegin/Chunk/End,
///   exportStream (Transferable + chunked fallback), streamCopy, close
class DbasSqliteWebPool {
  static final Map<String, DbasSqliteWebPool> _pools = {};
  static final Map<String, Future<DbasSqliteWebPool>> _pending = {};

  final String dbName;
  final web.Worker _worker;
  int _nextId = 0;
  final Map<int, Completer<dynamic>> _requests = {};

  /// Handlers for multi-message streaming protocols.
  /// These receive the raw [_JSObj] (not dartified) so they can handle
  /// non-dartifiable types like [ReadableStream].
  final Map<int, void Function(_JSObj)> _streamHandlers = {};
  bool _closed = false;

  DbasSqliteWebPool._(this.dbName, this._worker) {
    _worker.onmessage = ((web.MessageEvent e) {
      final jsData = e.data;
      if (jsData == null || jsData.isUndefinedOrNull) return;
      final jsObj = jsData as _JSObj;

      final idProp = jsObj['id'];
      if (idProp == null || idProp.isUndefinedOrNull) return;
      final id = (idProp as JSNumber).toDartDouble.toInt();

      // Streaming handlers get raw JS (not dartified)
      final streamHandler = _streamHandlers[id];
      if (streamHandler != null) {
        streamHandler(jsObj);
        return;
      }

      // Normal single-response path
      final data = (jsData as JSObject).dartify();
      if (data is! Map) return;
      final completer = _requests.remove(id);
      if (completer == null) return;
      if (data.containsKey('error') && data['error'] != null) {
        final err = data['error'];
        final msg = err is Map ? (err['message'] ?? err.toString()) : err.toString();
        completer.completeError(Exception(msg.toString()));
      } else {
        completer.complete(data['result']);
      }
    }).toJS;
    _worker.onerror = ((web.Event e) {
      // Capture the ErrorEvent's actual message / filename / lineno so
      // worker-load failures (404 on the script URL, syntax error in
      // the JS, COOP/COEP missing, etc.) surface a useful diagnostic
      // instead of the generic event type 'error'.
      String detail = e.type;
      if (e.isA<web.ErrorEvent>()) {
        final ev = e as web.ErrorEvent;
        final parts = <String>[];
        if (ev.message.isNotEmpty) parts.add(ev.message);
        if (ev.filename.isNotEmpty) parts.add(ev.filename);
        if (ev.lineno != 0) parts.add('line ${ev.lineno}');
        if (parts.isNotEmpty) detail = parts.join(' @ ');
      }
      final error = Exception('Web Worker error: $detail');
      for (final c in _requests.values) {
        if (!c.isCompleted) c.completeError(error);
      }
      _requests.clear();
      // Propagate to stream handlers via synthetic error message
      final handlers = Map.of(_streamHandlers);
      _streamHandlers.clear();
      for (final entry in handlers.entries) {
        try {
          final errMsg = <String, dynamic>{
            'id': entry.key,
            'error': {'code': 'WORKER_CRASHED', 'message': error.toString()},
          }.jsify() as _JSObj;
          entry.value(errMsg);
        } catch (handlerError) {
          developer.log(
            'DbasSqliteWebPool: failed to propagate worker crash to '
            'stream handler ${entry.key}',
            name: 'dbas_sqlite.DbasSqliteWebPool',
            error: handlerError,
          );
        }
      }
    }).toJS;
  }

  /// Get or create a pool for the given [dbName].
  static Future<DbasSqliteWebPool> create({
    required String dbName,
    int readerCount = 3,
  }) async {
    if (_pools.containsKey(dbName)) return _pools[dbName]!;
    return _pending.putIfAbsent(dbName, () async {
      try {
        return await _doCreate(dbName: dbName, readerCount: readerCount);
      } finally {
        _pending.remove(dbName);
      }
    });
  }

  static Future<DbasSqliteWebPool> _doCreate({
    required String dbName,
    int readerCount = 3,
  }) async {
    final worker = web.Worker(_workerUrl.toJS);
    final pool = DbasSqliteWebPool._(dbName, worker);

    // Initialize: load WASM + OPFS, open DB
    await pool.send('init', {
      'dbName': dbName.endsWith('.db') ? dbName : '$dbName.db',
      'role': 'writer',
      'libUrl': _libUrl,
    });

    _pools[dbName] = pool;
    return pool;
  }

  /// Send a command to the worker and await the single response.
  Future<dynamic> send(String action, [Map<String, dynamic>? payload]) {
    if (_closed) throw StateError('Pool is closed for "$dbName"');
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _requests[id] = completer;
    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': action,
        'payload': payload ?? {},
      }.jsify());
    } catch (e) {
      _requests.remove(id);
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Execute a write statement.
  ///
  /// Uses raw JS property access for the result to correctly handle
  /// `lastInsertId` which may be a JS BigInt (Emscripten `long long`).
  Future<Map<String, dynamic>> exec(String sql, [dynamic params]) async {
    if (_closed) throw StateError('Pool is closed for "$dbName"');
    final id = _nextId++;
    final completer = Completer<dynamic>();
    // Use a stream handler to get raw JS access (avoids dartify losing BigInt)
    _streamHandlers[id] = (_JSObj jsData) {
      _streamHandlers.remove(id);
      final errorProp = jsData['error'];
      if (errorProp != null && !errorProp.isUndefinedOrNull) {
        final err = (errorProp as JSObject).dartify();
        final msg = err is Map ? (err['message'] ?? err.toString()) : err.toString();
        completer.completeError(Exception(msg.toString()));
        return;
      }
      final resultProp = jsData['result'];
      if (resultProp != null && !resultProp.isUndefinedOrNull) {
        final jsResult = resultProp as _JSObj;
        final out = <String, dynamic>{
          'affectedRows': _jsToInt(jsResult['affectedRows']),
          'lastInsertId': _jsToInt(jsResult['lastInsertId']),
        };
        // Propagate `rows` if a future worker action shape includes
        // them. The current bundle's `exec` action returns counters
        // only; SELECTs go through the per-stmt streaming path
        // (`prepareQueryStream` / `bindParams` / `readRows` /
        // `finalizeStmt`) instead, which is how `Statement.executeReader`
        // operates on every platform after the v2.5.0 unification. This
        // branch is kept defensively so a worker upgrade that adds
        // rows here would not silently lose data.
        final rowsProp = jsResult['rows'];
        if (rowsProp != null && !rowsProp.isUndefinedOrNull) {
          final dartified = (rowsProp as JSObject).dartify();
          if (dartified is List) out['rows'] = dartified;
        }
        completer.complete(out);
      } else {
        completer.complete({'affectedRows': 0, 'lastInsertId': 0});
      }
    };
    final payload = <String, dynamic>{'sql': sql};
    if (params != null) payload['params'] = params;
    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'exec',
        'payload': payload,
      }.jsify());
    } catch (e) {
      _streamHandlers.remove(id);
      completer.completeError(e);
    }
    final result = await completer.future;
    if (result is Map) return Map<String, dynamic>.from(result);
    return {'affectedRows': 0, 'lastInsertId': 0};
  }

  /// Execute a read query. Returns all rows.
  ///
  /// **Eager**. Used internally for short PRAGMA / version probes
  /// where the result set is known to be tiny (e.g.
  /// `SELECT sqlite_version()`, `PRAGMA journal_mode`). User-facing
  /// SELECTs go through the per-stmt streaming path
  /// ([prepareQueryStream] + [bindParams] + [readRow] for the first
  /// step + [readRows] for subsequent chunks + [finalizeStmt]) which
  /// is what `DbasSqliteStatement.executeReader` and
  /// `DbasSqliteStatement.executeScalar` drive on every platform
  /// after the v2.5.0 unification. That path matches native FFI
  /// `executeReader` behaviour exactly: rows arrive incrementally,
  /// `executeScalar` issues exactly one `readRow` and then closes.
  Future<List<Map<String, dynamic>>> query(String sql, [dynamic params]) async {
    final payload = <String, dynamic>{'sql': sql};
    if (params != null) payload['params'] = params;
    final result = await send('query', payload);
    if (result is List) {
      return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    }
    if (result == null) return [];
    throw StateError('Unexpected query result type: ${result.runtimeType}');
  }

  // ── Streaming SELECT (1:1 mirror of native FFI prepare/step/finalize) ──
  //
  // These primitives expose the worker's per-statement streaming
  // protocol (worker bundle v4.5.0: prepareQuery / bindParams /
  // readRow / readRows (chunked) / finalizeStmt + getStmtAffectedRows /
  // getStmtLastInsertedId). They are the web-side counterpart of the
  // native FFI `prepareQuery` / `bindParams` / `readRowAndCache` /
  // `finalizeStmt` calls.
  //
  // Statement handles cross postMessage as JS BigInts (the worker
  // stores them in a JS `Map` keyed by BigInt; sending them back as
  // `Number` would miss the lookup and produce `UNKNOWN_HANDLE`). We
  // keep the handle as a raw [JSAny] (carrying the JS BigInt) so it
  // round-trips back to the worker via `postMessage` without going
  // through Dart `BigInt` — the Dart SDK shipped with this Flutter
  // version (3.11.4) does not have the `BigInt.toJS` / `JSBigInt.toDart`
  // extensions yet, and a raw passthrough is more efficient anyway.

  /// Prepares a SQL statement on the worker and returns the raw JS
  /// handle (a `BigInt`, opaque to Dart) plus column metadata captured
  /// at prepare time. The worker holds the SHARED reader fence across
  /// the statement's lifetime; it is released by [finalizeStmt].
  Future<
      ({
        JSAny rawHandle,
        int columnCount,
        List<String> columnNames
      })> prepareQueryStream(String sql) {
    if (_closed) throw StateError('Pool is closed for "$dbName"');
    final id = _nextId++;
    final completer = Completer<
        ({
          JSAny rawHandle,
          int columnCount,
          List<String> columnNames
        })>();

    _streamHandlers[id] = (_JSObj jsData) {
      _streamHandlers.remove(id);
      final errorProp = jsData['error'];
      if (errorProp != null && !errorProp.isUndefinedOrNull) {
        final err = (errorProp as JSObject).dartify();
        final msg =
            err is Map ? (err['message'] ?? err.toString()) : err.toString();
        completer.completeError(Exception(msg.toString()));
        return;
      }
      final resultProp = jsData['result'];
      if (resultProp == null || resultProp.isUndefinedOrNull) {
        completer.completeError(
            Exception('prepareQuery: worker returned no result for "$sql"'));
        return;
      }
      final result = resultProp as _JSObj;
      final handleRaw = result['handle'];
      if (handleRaw == null || handleRaw.isUndefinedOrNull) {
        completer.completeError(
            Exception('prepareQuery: response missing handle for "$sql"'));
        return;
      }
      final cc =
          ((result['columnCount'] as JSNumber).toDartDouble).toInt();
      final namesRaw = result['columnNames'];
      final names = <String>[];
      if (namesRaw != null && !namesRaw.isUndefinedOrNull) {
        final arr = (namesRaw as JSArray<JSAny?>).toDart;
        for (final n in arr) {
          if (n != null && !n.isUndefinedOrNull) {
            names.add((n as JSString).toDart);
          } else {
            names.add('');
          }
        }
      }
      completer.complete((
        rawHandle: handleRaw,
        columnCount: cc,
        columnNames: names,
      ));
    };

    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'prepareQuery',
        'payload': <String, dynamic>{'sql': sql},
      }.jsify());
    } catch (e) {
      _streamHandlers.remove(id);
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Binds [params] (positional list or named map, same shape used by
  /// [exec] / [query]) onto the prepared [handle].
  ///
  /// On bind failure the worker does **not** auto-finalize — matching
  /// native FFI semantics. The caller is responsible for calling
  /// [finalizeStmt] to release the handle.
  Future<void> bindParams(JSAny rawHandle, dynamic params) {
    if (_closed) throw StateError('Pool is closed for "$dbName"');
    final id = _nextId++;
    final completer = Completer<void>();
    _requests[id] = completer;

    final payload = <String, dynamic>{'handle': rawHandle};
    if (params != null) payload['params'] = params;

    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'bindParams',
        'payload': payload,
      }.jsify());
    } catch (e) {
      _requests.remove(id);
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Steps the prepared [rawHandle] one row.
  ///
  /// Returns `(rc: 100, columns: [...])` on `SQLITE_ROW` (with one
  /// [ColumnData] per column in [columnNames] order), or
  /// `(rc: 101, columns: null)` on `SQLITE_DONE`. Throws on any other
  /// rc. The caller is responsible for [finalizeStmt] in both cases —
  /// the worker does not auto-finalize on `SQLITE_DONE`.
  ///
  /// Used by `DbasSqliteNativeWeb.readRowAndCache` for the **first**
  /// step of every prepared SELECT — so `executeScalar` issues
  /// exactly one round-trip and exits without fetching additional
  /// rows. Subsequent steps use [readRows] to bulk-fetch chunks.
  Future<({int rc, List<ColumnData>? columns})> readRow(
      JSAny rawHandle, List<String> columnNames) {
    if (_closed) throw StateError('Pool is closed for "$dbName"');
    final id = _nextId++;
    final completer =
        Completer<({int rc, List<ColumnData>? columns})>();

    _streamHandlers[id] = (_JSObj jsData) {
      _streamHandlers.remove(id);
      final errorProp = jsData['error'];
      if (errorProp != null && !errorProp.isUndefinedOrNull) {
        final err = (errorProp as JSObject).dartify();
        final msg =
            err is Map ? (err['message'] ?? err.toString()) : err.toString();
        completer.completeError(Exception(msg.toString()));
        return;
      }
      final resultProp = jsData['result'];
      if (resultProp == null || resultProp.isUndefinedOrNull) {
        completer.completeError(Exception('readRow: empty result'));
        return;
      }
      final result = resultProp as _JSObj;
      final rcRaw = result['rc'];
      final rc = (rcRaw as JSNumber).toDartDouble.toInt();
      if (rc == sqliteDone) {
        completer.complete((rc: rc, columns: null));
        return;
      }
      if (rc != sqliteRow) {
        completer.completeError(
            Exception('readRow: unexpected rc=$rc from worker'));
        return;
      }
      final rowProp = result['row'];
      if (rowProp == null || rowProp.isUndefinedOrNull) {
        completer.completeError(
            Exception('readRow: rc=100 but no row payload'));
        return;
      }
      final rowObj = rowProp as _JSObj;
      final cols = <ColumnData>[];
      for (final name in columnNames) {
        cols.add(_classifyJsColumnValue(rowObj[name]));
      }
      completer.complete((rc: rc, columns: cols));
    };

    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'readRow',
        'payload': <String, dynamic>{'handle': rawHandle},
      }.jsify());
    } catch (e) {
      _streamHandlers.remove(id);
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Steps the prepared [rawHandle] up to [maxRows] times in a single
  /// worker round-trip and returns the rows fetched plus a flag
  /// indicating whether more rows might be available.
  ///
  ///  - `hasMore == true`: [maxRows] reached without `SQLITE_DONE` —
  ///    call [readRows] again to fetch the next chunk.
  ///  - `hasMore == false`: the worker observed `SQLITE_DONE`; the
  ///    statement is exhausted and any further [readRows] returns an
  ///    empty list with `hasMore == false`.
  ///
  /// Throws on SQLite step errors. The caller is responsible for
  /// [finalizeStmt] in both cases — the worker does not auto-finalize
  /// on `SQLITE_DONE`.
  ///
  /// The worker caps [maxRows] at 10000 to bound memory; values up to
  /// that cap are accepted. Typical chunk size is 50.
  Future<({List<List<ColumnData>> rows, bool hasMore})> readRows(
      JSAny rawHandle, List<String> columnNames, int maxRows) {
    if (_closed) throw StateError('Pool is closed for "$dbName"');
    final id = _nextId++;
    final completer =
        Completer<({List<List<ColumnData>> rows, bool hasMore})>();

    _streamHandlers[id] = (_JSObj jsData) {
      _streamHandlers.remove(id);
      final errorProp = jsData['error'];
      if (errorProp != null && !errorProp.isUndefinedOrNull) {
        final err = (errorProp as JSObject).dartify();
        final msg =
            err is Map ? (err['message'] ?? err.toString()) : err.toString();
        completer.completeError(Exception(msg.toString()));
        return;
      }
      final resultProp = jsData['result'];
      if (resultProp == null || resultProp.isUndefinedOrNull) {
        completer.completeError(Exception('readRows: empty result'));
        return;
      }
      final result = resultProp as _JSObj;
      final hasMoreRaw = result['hasMore'];
      final hasMore = hasMoreRaw != null &&
          !hasMoreRaw.isUndefinedOrNull &&
          (hasMoreRaw as JSBoolean).toDart;
      final rowsArr = result['rows'];
      final outRows = <List<ColumnData>>[];
      if (rowsArr != null && !rowsArr.isUndefinedOrNull) {
        // Inspect each row's raw JS values directly. Going through
        // `dartify()` would lose precision for SQLite INTEGER values
        // outside int32 range (the worker emits a JS BigInt for those,
        // which dartify converts to a Dart String in some Dart-on-web
        // build configurations — see the legacy comment in
        // `dbas_sqlite_row_cache.dart`). Reading the JS object directly
        // and classifying via `typeofEquals` / `isA<>` keeps the type
        // and the bit-pattern intact end-to-end.
        final rowList = (rowsArr as JSArray<JSAny?>).toDart;
        for (final r in rowList) {
          if (r == null || r.isUndefinedOrNull) {
            outRows.add(List.filled(
                columnNames.length, ColumnData(type: 5, isNull: true)));
            continue;
          }
          final rowObj = r as _JSObj;
          final cols = <ColumnData>[];
          for (final name in columnNames) {
            cols.add(_classifyJsColumnValue(rowObj[name]));
          }
          outRows.add(cols);
        }
      }
      completer.complete((rows: outRows, hasMore: hasMore));
    };

    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'readRows',
        'payload': <String, dynamic>{
          'handle': rawHandle,
          'maxRows': maxRows,
        },
      }.jsify());
    } catch (e) {
      _streamHandlers.remove(id);
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Finalises the prepared [rawHandle] on the worker. Idempotent and
  /// tolerant of unknown handles, so it is safe to call after a
  /// successful `SQLITE_DONE` step or after a bind failure.
  Future<void> finalizeStmt(JSAny rawHandle) {
    if (_closed) {
      // Worker is gone; the handle is implicitly finalized.
      return Future.value();
    }
    final id = _nextId++;
    final completer = Completer<void>();
    _requests[id] = completer;
    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'finalizeStmt',
        'payload': <String, dynamic>{'handle': rawHandle},
      }.jsify());
    } catch (e) {
      _requests.remove(id);
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Returns `sqlite3_changes()` for the connection scoped to the
  /// prepared [rawHandle]. The worker throws `STMT_NEVER_STEPPED` if
  /// the handle has never been successfully stepped via [readRow] or
  /// [readRows], so callers must read counters only after at least
  /// one successful step.
  Future<int> getStmtAffectedRows(JSAny rawHandle) async {
    if (_closed) throw StateError('Pool is closed for "$dbName"');
    final id = _nextId++;
    final completer = Completer<int>();
    _streamHandlers[id] = (_JSObj jsData) {
      _streamHandlers.remove(id);
      final errorProp = jsData['error'];
      if (errorProp != null && !errorProp.isUndefinedOrNull) {
        final err = (errorProp as JSObject).dartify();
        final msg =
            err is Map ? (err['message'] ?? err.toString()) : err.toString();
        completer.completeError(Exception(msg.toString()));
        return;
      }
      final resultProp = jsData['result'];
      if (resultProp == null || resultProp.isUndefinedOrNull) {
        completer.completeError(
            Exception('getStmtAffectedRows: empty result'));
        return;
      }
      final result = resultProp as _JSObj;
      completer.complete(_jsToInt(result['value']));
    };
    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'getStmtAffectedRows',
        'payload': <String, dynamic>{'handle': rawHandle},
      }.jsify());
    } catch (e) {
      _streamHandlers.remove(id);
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Returns `sqlite3_last_insert_rowid()` for the connection scoped
  /// to the prepared [rawHandle]. Same `STMT_NEVER_STEPPED` invariant
  /// as [getStmtAffectedRows].
  Future<int> getStmtLastInsertedId(JSAny rawHandle) async {
    if (_closed) throw StateError('Pool is closed for "$dbName"');
    final id = _nextId++;
    final completer = Completer<int>();
    _streamHandlers[id] = (_JSObj jsData) {
      _streamHandlers.remove(id);
      final errorProp = jsData['error'];
      if (errorProp != null && !errorProp.isUndefinedOrNull) {
        final err = (errorProp as JSObject).dartify();
        final msg =
            err is Map ? (err['message'] ?? err.toString()) : err.toString();
        completer.completeError(Exception(msg.toString()));
        return;
      }
      final resultProp = jsData['result'];
      if (resultProp == null || resultProp.isUndefinedOrNull) {
        completer.completeError(
            Exception('getStmtLastInsertedId: empty result'));
        return;
      }
      final result = resultProp as _JSObj;
      completer.complete(_jsToInt(result['value']));
    };
    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'getStmtLastInsertedId',
        'payload': <String, dynamic>{'handle': rawHandle},
      }.jsify());
    } catch (e) {
      _streamHandlers.remove(id);
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Inspect a raw JS value pulled out of a `readRow` row payload and
  /// produce a typed [ColumnData]. The classification mirrors what the
  /// native FFI `readRowAndCache` produces:
  ///
  ///   - `bigint` JS values (SQLite INTEGER outside int32 range) →
  ///     INTEGER, materialised via `BigInt.toInt()` (clamped to the
  ///     53-bit Dart-on-web int range).
  ///   - `number` JS values: integral and within the safe int range →
  ///     INTEGER; otherwise → FLOAT. SQLite FLOAT columns whose value
  ///     happens to be exactly integral collapse to INTEGER on this
  ///     side — this is a JS-side precision loss that the worker can't
  ///     avoid without an extra getColumnType round-trip.
  ///   - `string` → TEXT.
  ///   - `Uint8Array` / `ArrayBuffer` → BLOB.
  ///   - `null` / `undefined` → NULL.
  static ColumnData _classifyJsColumnValue(JSAny? raw) {
    if (raw == null || raw.isUndefinedOrNull) {
      return ColumnData(type: 5, isNull: true);
    }
    if (raw.typeofEquals('bigint')) {
      // Convert via JS `Number(bigint)` — exact within the 53-bit safe
      // integer range (which is also Dart-on-web's `int` range), and
      // truncates beyond that. Equivalent to `BigInt.toInt()` on the
      // web Dart runtime; we use the JS path because the
      // `JSBigInt.toDart` extension isn't available in the Dart SDK
      // shipped with this Flutter version (3.11.4).
      final n = _jsToNumber(raw).toDartDouble;
      return ColumnData(type: 1, isNull: false, value: n.toInt());
    }
    if (raw.typeofEquals('number')) {
      final n = (raw as JSNumber).toDartDouble;
      if (n.isFinite &&
          n.truncateToDouble() == n &&
          n.abs() <= 9007199254740992.0 /* 2^53 — Dart-on-web safe int */) {
        return ColumnData(type: 1, isNull: false, value: n.toInt());
      }
      return ColumnData(type: 2, isNull: false, value: n);
    }
    if (raw.typeofEquals('string')) {
      return ColumnData(
          type: 3, isNull: false, value: (raw as JSString).toDart);
    }
    if (raw.isA<JSUint8Array>()) {
      return ColumnData(
          type: 4, isNull: false, value: (raw as JSUint8Array).toDart);
    }
    if (raw.isA<JSArrayBuffer>()) {
      return ColumnData(
          type: 4,
          isNull: false,
          value: (raw as JSArrayBuffer).toDart.asUint8List());
    }
    // Defensive — the worker only emits the typed forms above. If a
    // future worker version adds another type, surface it as TEXT
    // rather than NULL so the caller can at least see the value.
    return ColumnData(
        type: 3, isNull: false, value: 'unsupported:${raw.runtimeType}');
  }

  /// Execute a batch of statements.
  Future<void> batch(List<Map<String, dynamic>> statements) async {
    await send('batch', {'statements': statements});
  }

  /// Drop the database (removes all OPFS files).
  Future<void> drop() async {
    await send('drop');
  }

  // ── Streaming attach (chunked protocol) ─────────────────────────────────

  /// Attach a database from a Dart [Stream] using the chunked protocol
  /// (`attachStreamBegin` / `attachStreamChunk` / `attachStreamEnd`).
  ///
  /// Each chunk is transferred as an ArrayBuffer for zero-copy handoff.
  /// The worker sends an ACK after each chunk, providing backpressure.
  Future<void> attachStreamChunked(Stream<List<int>> stream, {int? totalSize}) async {
    if (_closed) throw StateError('Pool is closed for "$dbName"');

    final id = _nextId++;
    final readyCompleter = Completer<void>();
    final endCompleter = Completer<void>();
    Completer<void>? ackCompleter;

    _streamHandlers[id] = (_JSObj jsData) {
      // Error
      final errorProp = jsData['error'];
      if (errorProp != null && !errorProp.isUndefinedOrNull) {
        _streamHandlers.remove(id);
        final err = (errorProp as JSObject).dartify();
        final msg = err is Map ? (err['message'] ?? err.toString()) : err.toString();
        final exception = Exception(msg.toString());
        if (!readyCompleter.isCompleted) readyCompleter.completeError(exception);
        ackCompleter?.completeError(exception);
        if (!endCompleter.isCompleted) endCompleter.completeError(exception);
        return;
      }

      // Action-based messages (ready / ack)
      final actionProp = jsData['action'];
      if (actionProp != null && !actionProp.isUndefinedOrNull) {
        final action = (actionProp as JSString).toDart;
        if (action == 'attachStreamReady') {
          if (!readyCompleter.isCompleted) readyCompleter.complete();
        } else if (action == 'attachStreamAck') {
          final ac = ackCompleter;
          if (ac != null && !ac.isCompleted) ac.complete();
        }
        return;
      }

      // Normal result (from attachStreamEnd response)
      final resultProp = jsData['result'];
      if (resultProp != null && !resultProp.isUndefinedOrNull) {
        _streamHandlers.remove(id);
        if (!endCompleter.isCompleted) endCompleter.complete();
      }
    };

    try {
      // Begin — worker closes DB and opens FS path for writing
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'attachStreamBegin',
        'payload': totalSize != null ? {'totalSize': totalSize} : <String, dynamic>{},
      }.jsify());
      await readyCompleter.future;

      // Stream chunks with backpressure (wait for ACK after each)
      await for (final chunk in stream) {
        ackCompleter = Completer<void>();
        final bytes = Uint8List.fromList(chunk);
        final jsBuffer = bytes.buffer.toJS;
        _worker.postMessage(<String, dynamic>{
          'id': id,
          'action': 'attachStreamChunk',
          'payload': {'chunk': jsBuffer},
        }.jsify(), [jsBuffer].toJS);
        await ackCompleter.future;
      }

      // End — worker closes FS, reopens DB
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'attachStreamEnd',
        'payload': <String, dynamic>{},
      }.jsify());
      await endCompleter.future;
    } catch (e) {
      _streamHandlers.remove(id);
      // Fire-and-forget abort using the original session ID so the worker
      // can correlate it with the active attach session.
      if (!_closed) {
        try {
          _worker.postMessage(<String, dynamic>{
            'id': id,
            'action': 'attachStreamAbort',
            'payload': <String, dynamic>{},
          }.jsify());
        } catch (_) {}
      }
      rethrow;
    }
  }

  // ── Streaming export ────────────────────────────────────────────────────

  /// Export the database content as bytes using the streaming protocol.
  ///
  /// Handles both the Transferable Streams path (Chrome/Firefox — the worker
  /// sends a [ReadableStream]) and the chunked postMessage fallback (Safari —
  /// `exportStreamChunk` messages with ACK-based backpressure).
  Future<List<int>> exportContentStream() async {
    if (_closed) throw StateError('Pool is closed for "$dbName"');

    final id = _nextId++;
    final completer = Completer<List<int>>();
    final chunks = <Uint8List>[];

    _streamHandlers[id] = (_JSObj jsData) {
      // Error
      final errorProp = jsData['error'];
      if (errorProp != null && !errorProp.isUndefinedOrNull) {
        _streamHandlers.remove(id);
        final err = (errorProp as JSObject).dartify();
        final msg = err is Map ? (err['message'] ?? err.toString()) : err.toString();
        if (!completer.isCompleted) completer.completeError(Exception(msg.toString()));
        return;
      }

      // Chunked path: exportStreamChunk action
      final actionProp = jsData['action'];
      if (actionProp != null && !actionProp.isUndefinedOrNull) {
        final action = (actionProp as JSString).toDart;
        if (action == 'exportStreamChunk') {
          final payloadObj = jsData['payload'] as _JSObj;
          final chunkProp = payloadObj['chunk'];
          if (chunkProp != null && !chunkProp.isUndefinedOrNull) {
            chunks.add((chunkProp as JSArrayBuffer).toDart.asUint8List());
          }
          // Send ACK for backpressure
          _worker.postMessage(<String, dynamic>{
            'id': id,
            'action': 'exportStreamAck',
          }.jsify());
        }
        return;
      }

      // Result — either a ReadableStream (transferable path) or final
      // success object from the chunked path.
      final resultProp = jsData['result'];
      if (resultProp != null && !resultProp.isUndefinedOrNull) {
        if (resultProp.isA<web.ReadableStream>()) {
          // Transferable Streams path — read chunks from the stream
          _readStreamToBytes(resultProp as web.ReadableStream).then((bytes) {
            _streamHandlers.remove(id);
            if (!completer.isCompleted) completer.complete(bytes);
          }).catchError((Object e) {
            _streamHandlers.remove(id);
            if (!completer.isCompleted) completer.completeError(e);
          });
        } else {
          // Final success from chunked path — assemble accumulated chunks
          _streamHandlers.remove(id);
          if (!completer.isCompleted) {
            final builder = BytesBuilder();
            for (final c in chunks) {
              builder.add(c);
            }
            completer.complete(builder.toBytes());
          }
        }
        return;
      }

      // Progress messages — ignore
    };

    _worker.postMessage(<String, dynamic>{
      'id': id,
      'action': 'exportStream',
      'payload': <String, dynamic>{},
    }.jsify());

    return completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        _streamHandlers.remove(id);
        throw TimeoutException('exportContentStream did not complete within 120 seconds');
      },
    );
  }

  /// Read all bytes from a [ReadableStream] (used for the Transferable
  /// Streams export path).
  Future<Uint8List> _readStreamToBytes(web.ReadableStream stream) async {
    final reader = stream.getReader() as web.ReadableStreamDefaultReader;
    final builder = BytesBuilder();
    try {
      while (true) {
        final result = await reader.read().toDart;
        final jsResult = result as _JSObj;
        final doneVal = jsResult['done'];
        if (doneVal != null && !doneVal.isUndefinedOrNull &&
            (doneVal as JSBoolean).toDart) {
          break;
        }
        final value = jsResult['value'];
        if (value != null && !value.isUndefinedOrNull) {
          if (value.isA<JSUint8Array>()) {
            builder.add((value as JSUint8Array).toDart);
          } else if (value.isA<JSArrayBuffer>()) {
            builder.add((value as JSArrayBuffer).toDart.asUint8List());
          } else {
            throw StateError(
              '_readStreamToBytes: unexpected chunk type from ReadableStream');
          }
        }
      }
    } finally {
      try {
        reader.releaseLock();
      } catch (e) {
        developer.log(
          'DbasSqliteWebPool: releaseLock failed',
          name: 'dbas_sqlite.DbasSqliteWebPool',
          error: e,
        );
      }
    }
    return builder.toBytes();
  }

  /// Convert a JS value (Number, BigInt, or null) to a Dart int.
  /// Uses JS `Number()` to handle BigInt from Emscripten `long long` returns.
  static int _jsToInt(JSAny? v) {
    if (v == null || v.isUndefinedOrNull) return 0;
    // Use JS Number() to convert any numeric JS type (Number, BigInt, etc.)
    // to a standard JS Number, then convert to Dart int.
    try {
      return _jsToNumber(v).toDartDouble.toInt();
    } catch (_) {
      return 0;
    }
  }

  /// Copy the database to a new OPFS file.
  Future<void> streamCopy(String destName) async {
    await send('streamCopy', {
      'destName': destName.endsWith('.db') ? destName : '$destName.db',
    });
  }

  /// Close the worker and release resources.
  Future<void> close() async {
    if (_closed) return;
    // Flip the flag synchronously BEFORE awaiting the graceful close so
    // any concurrent send() invocation rejects immediately instead of
    // queueing a request whose response will never arrive once we
    // terminate the worker below.
    _closed = true;
    _pools.remove(dbName);

    // Post the 'close' message directly (bypassing send() which now
    // throws on _closed) and await the response inline.
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _requests[id] = completer;
    try {
      _worker.postMessage(<String, dynamic>{
        'id': id,
        'action': 'close',
        'payload': <String, dynamic>{},
      }.jsify());
      await completer.future;
    } catch (e) {
      developer.log(
        'DbasSqliteWebPool: graceful close failed for "$dbName"',
        name: 'dbas_sqlite.DbasSqliteWebPool',
        error: e,
      );
    } finally {
      _requests.remove(id);
    }

    _worker.terminate();

    // After terminate, any still-pending completers will never receive
    // a response. Reject them so callers don't hang forever.
    final closedErr = StateError('Pool closed for "$dbName"');
    for (final c in _requests.values) {
      if (!c.isCompleted) c.completeError(closedErr);
    }
    _requests.clear();

    // Stream handlers own their completers inside their closures (see
    // `prepareQueryStream`, `readRow`, `readRows`, `getStmtAffectedRows`,
    // `getStmtLastInsertedId`, `exec`, `attachStreamChunked`,
    // `exportContentStream`). Synthesise an `error`-shaped JS object
    // and dispatch it to each handler — they're already structured to
    // unwrap the error and reject their captured completer. Without
    // this, an in-flight stream-RPC caller (e.g. a `readRows` chunk
    // fetch driving `DbasSqliteReader.readRow` mid-iteration) would
    // hang forever after a graceful close.
    final handlersSnapshot = Map.of(_streamHandlers);
    _streamHandlers.clear();
    for (final entry in handlersSnapshot.entries) {
      try {
        final errMsg = <String, dynamic>{
          'id': entry.key,
          'error': {
            'code': 'POOL_CLOSED',
            'message': 'Pool closed for "$dbName"',
          },
        }.jsify() as _JSObj;
        entry.value(errMsg);
      } catch (e, st) {
        developer.log(
          'DbasSqliteWebPool: failed to wake stream handler ${entry.key} '
          'during close',
          name: 'dbas_sqlite.DbasSqliteWebPool',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  static void removePool(String dbName) {
    _pools.remove(dbName);
  }
}
