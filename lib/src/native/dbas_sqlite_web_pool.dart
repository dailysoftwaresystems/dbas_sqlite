import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';

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
          // ignore: avoid_print
          print('DbasSqliteWebPool: failed to propagate worker crash to '
              'stream handler ${entry.key}: $handlerError');
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
        // Propagate `rows` if the JS worker included it (current
        // bundled `dbas_sqlite_worker.js` v4.3.6 doesn't, but a
        // future build that supports SELECT through pool.exec will,
        // and the in-transaction read path on web depends on it).
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
        // ignore: avoid_print
        print('DbasSqliteWebPool: releaseLock failed: $e');
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
    _pools.remove(dbName);
    try {
      await send('close');
    } catch (e) {
      // ignore: avoid_print
      print('DbasSqliteWebPool: graceful close failed for "$dbName": $e');
    }
    _closed = true;
    _worker.terminate();
  }

  static void removePool(String dbName) {
    _pools.remove(dbName);
  }
}

// ── WebQueryBuffer ─────────────────────────────────────────────────────

/// Buffered row data for cursor-based reading from query results.
class WebQueryBuffer {
  final List<Map<String, dynamic>> rows;
  final List<String> columnNames;
  int currentRowIndex = -1;

  WebQueryBuffer(this.rows)
      : columnNames = rows.isNotEmpty ? rows.first.keys.toList() : [];

  bool moveNext() {
    currentRowIndex++;
    return currentRowIndex < rows.length;
  }

  Map<String, dynamic>? get currentRow =>
      currentRowIndex >= 0 && currentRowIndex < rows.length
          ? rows[currentRowIndex]
          : null;

  int get columnCount => columnNames.length;

  ColumnData getColumnData(int index) {
    if (currentRow == null || index >= columnNames.length) {
      return ColumnData(type: 5, isNull: true);
    }
    final name = columnNames[index];
    final value = currentRow![name];
    if (value == null) return ColumnData(type: 5, isNull: true, value: null);
    if (value is int) return ColumnData(type: 1, isNull: false, value: value);
    if (value is double) return ColumnData(type: 2, isNull: false, value: value);
    if (value is String) return ColumnData(type: 3, isNull: false, value: value);
    if (value is List) return ColumnData(type: 4, isNull: false, value: value);
    return ColumnData(type: 3, isNull: false, value: value.toString());
  }
}
