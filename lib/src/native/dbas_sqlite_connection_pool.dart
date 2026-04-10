import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart'
    if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/stub/dbas_sqlite_db_stub.dart';

/// Pure-Dart connection pool for native SQLite connections.
///
/// Manages a fixed set of general-purpose connections. All connections are
/// opened in read-write mode with WAL journal. Connection 0 is designated
/// as the writer (used by DbasSqlite under _writerLock). Connections 1..N
/// are available as readers via [acquireReader]/[releaseConnection].
///
/// Concurrency rules:
/// - Multiple readers may run simultaneously (connections 1..N).
/// - The writer (connection 0) is managed externally by DbasSqlite._writerLock.
class DbasSqliteConnectionPool {
  final List<DbasSqliteDb> _connections;
  final List<bool> _busy;

  DbasSqliteConnectionPool(List<DbasSqliteDb> connections)
      : _connections = List.unmodifiable(connections),
        _busy = List.filled(connections.length, false);

  /// The designated writer connection (index 0).
  DbasSqliteDb get writer => _connections[0];

  /// All connections, used when closing the pool.
  List<DbasSqliteDb> get all => _connections;

  /// Acquire a free reader connection (indices 1..N).
  /// Returns null if all readers are busy.
  DbasSqliteDb? acquireReader() {
    for (int i = 1; i < _connections.length; i++) {
      if (!_busy[i]) {
        _busy[i] = true;
        return _connections[i];
      }
    }
    return null;
  }

  /// Release a reader connection back to the pool by its native pointer.
  void releaseConnection(int ptr) {
    for (int i = 1; i < _connections.length; i++) {
      if (_connections[i].ptr == ptr) {
        _busy[i] = false;
        return;
      }
    }
  }
}
