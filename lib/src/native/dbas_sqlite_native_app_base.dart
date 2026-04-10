import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dbas_sqlite_native_interface.dart';
import 'dbas_sqlite_connection_pool.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';

/// Base class for native app implementations (FFI and IO/AOT).
///
/// Contains all shared marshalling logic (Pointer allocation, try/finally,
/// file I/O). Subclasses only need to provide the raw native function calls
/// via the protected abstract [nativeXxx] methods.
abstract class DbasSqliteNativeAppBase extends DbasSqliteNativeInterface {
  DbasSqliteNativeAppBase(super.dbName);

  // ── Protected abstract methods (raw native calls) ──────────────────────
  Pointer<DbasSqliteDbStruct> nativeOpenDb(Pointer<Utf8> path);
  int nativeIsOpened(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeExecuteSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);
  int nativePrepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);

  int nativeBindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index);
  int nativeBindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value);
  int nativeBindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);
  int nativeBindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);
  int nativeBindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value);
  int nativeBindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Uint8> value, int length);

  int nativeBindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name);
  int nativeBindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value);
  int nativeBindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);
  int nativeBindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);
  int nativeBindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value);
  int nativeBindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Uint8> value, int length);

  int nativeReadRow(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeIsNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  Pointer<Utf8> nativeGetColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  int nativeGetColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  double nativeGetColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  double nativeGetColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  Pointer<Uint8> nativeGetColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);
  int nativeGetColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);
  Pointer<Utf8> nativeGetColumnName(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);
  int nativeGetColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  int nativeGetColumnCount(Pointer<DbasSqliteDbStruct> dbPtr);

  Pointer<Utf8> nativeGetLastDbError(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeGetAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeGetLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr);

  void nativeCloseReader(Pointer<DbasSqliteDbStruct> dbPtr);
  void nativeCloseDb(Pointer<DbasSqliteDbStruct> dbPtr);

  // ── Connection Pool ──
  Pointer<DbasSqlitePoolStruct> nativeCreatePool(Pointer<Utf8> path, int readerCount);
  Pointer<DbasSqliteDbStruct> nativePoolGetWriter(Pointer<DbasSqlitePoolStruct> poolPtr);
  Pointer<DbasSqliteDbStruct> nativePoolAcquireReader(Pointer<DbasSqlitePoolStruct> poolPtr);
  void nativePoolReleaseReader(Pointer<DbasSqlitePoolStruct> poolPtr, Pointer<DbasSqliteDbStruct> readerPtr);
  void nativeClosePool(Pointer<DbasSqlitePoolStruct> poolPtr);

  // ── Pointer resolution (overridable for extra validation) ──────────────
  Pointer<DbasSqliteDbStruct> resolveDbPtr(int address) =>
      Pointer<DbasSqliteDbStruct>.fromAddress(address);

  Pointer<DbasSqlitePoolStruct> resolvePoolPtr(int address) =>
      Pointer<DbasSqlitePoolStruct>.fromAddress(address);

  // ── Shared implementation ──────────────────────────────────────────────
  @override
  Future<int> openDb(String path) async {
    Pointer<Utf8> pathPtr = nullptr;
    try {
      pathPtr = path.toNativeUtf8();
      final ptr = nativeOpenDb(pathPtr);
      return ptr.address;
    } finally {
      if (pathPtr != nullptr) {
        calloc.free(pathPtr);
      }
    }
  }

  @override
  Future<bool> databaseExists(String fileName) async {
    final dbFile = File(fileName);
    return await dbFile.exists();
  }

  @override
  Future attachDb(String fileName, List<int> content) async {
    await dropDb(fileName);
    final dbFile = File(fileName);
    await dbFile.writeAsBytes(content);
  }

  @override
  Future attachStreamDb(String fileName, Stream<List<int>> stream) async {
    await dropDb(fileName);
    final sink = File(fileName).openWrite();
    try {
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<List<int>> getContent(String fileName) async {
    final dbFile = File(fileName);
    return await dbFile.readAsBytes();
  }

  @override
  Future<void> streamCopyDb(String sourceFileName, String destFileName) async {
    for (final ext in ['', '-wal', '-shm']) {
      final f = File('$destFileName$ext');
      if (await f.exists()) await f.delete();
    }

    final sourceFile = File(sourceFileName);
    final destFile = File(destFileName);
    final sink = destFile.openWrite();
    try {
      await sourceFile.openRead().pipe(sink);
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> dropDb(String fileName) async {
    final dbFile = File(fileName);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    final walFile = File('$fileName-wal');
    if (await walFile.exists()) {
      await walFile.delete();
    }
    final shmFile = File('$fileName-shm');
    if (await shmFile.exists()) {
      await shmFile.delete();
    }
  }

  @override
  bool isOpened(int dbPtr) => nativeIsOpened(resolveDbPtr(dbPtr)) == 1;

  @override
  Future<int> executeSql(int dbPtr, String sql) async {
    Pointer<Utf8> sqlPtr = nullptr;
    try {
      sqlPtr = sql.toNativeUtf8();
      return nativeExecuteSql(resolveDbPtr(dbPtr), sqlPtr);
    } finally {
      if (sqlPtr != nullptr) {
        calloc.free(sqlPtr);
      }
    }
  }

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async {
    Pointer<Utf8> sqlPtr = nullptr;
    try {
      sqlPtr = sql.toNativeUtf8();
      return nativePrepareQuery(resolveDbPtr(dbPtr), sqlPtr);
    } finally {
      if (sqlPtr != nullptr) {
        calloc.free(sqlPtr);
      }
    }
  }

  @override
  int bindNull(int dbPtr, int index) =>
      nativeBindNull(resolveDbPtr(dbPtr), index);

  @override
  int bindInt(int dbPtr, int index, int value) =>
      nativeBindInt(resolveDbPtr(dbPtr), index, value);

  @override
  int bindFloat(int dbPtr, int index, double value) =>
      nativeBindFloat(resolveDbPtr(dbPtr), index, value);

  @override
  int bindDouble(int dbPtr, int index, double value) =>
      nativeBindDouble(resolveDbPtr(dbPtr), index, value);

  @override
  int bindText(int dbPtr, int index, String value) {
    Pointer<Utf8> valuePtr = nullptr;
    try {
      valuePtr = value.toNativeUtf8();
      return nativeBindText(resolveDbPtr(dbPtr), index, valuePtr);
    } finally {
      if (valuePtr != nullptr) {
        calloc.free(valuePtr);
      }
    }
  }

  @override
  int bindBlob(int dbPtr, int index, List<int> value) {
    Pointer<Uint8> ptr = nullptr;
    try {
      ptr = calloc<Uint8>(value.length);
      for (var i = 0; i < value.length; i++) {
        ptr[i] = value[i];
      }
      return nativeBindBlob(resolveDbPtr(dbPtr), index, ptr, value.length);
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
    }
  }

  @override
  int bindNameNull(int dbPtr, String name) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameNull(resolveDbPtr(dbPtr), namePtr);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int bindNameInt(int dbPtr, String name, int value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameInt(resolveDbPtr(dbPtr), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int bindNameFloat(int dbPtr, String name, double value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameFloat(resolveDbPtr(dbPtr), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int bindNameDouble(int dbPtr, String name, double value) {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameDouble(resolveDbPtr(dbPtr), namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  int bindNameText(int dbPtr, String name, String value) {
    Pointer<Utf8> namePtr = nullptr;
    Pointer<Utf8> valuePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      valuePtr = value.toNativeUtf8();
      return nativeBindNameText(resolveDbPtr(dbPtr), namePtr, valuePtr);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
      if (valuePtr != nullptr) calloc.free(valuePtr);
    }
  }

  @override
  int bindNameBlob(int dbPtr, String name, List<int> value) {
    Pointer<Utf8> namePtr = nullptr;
    Pointer<Uint8> ptr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      ptr = calloc<Uint8>(value.length);
      for (var i = 0; i < value.length; i++) {
        ptr[i] = value[i];
      }
      return nativeBindNameBlob(resolveDbPtr(dbPtr), namePtr, ptr, value.length);
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  Future<int> readRow(int dbPtr) async =>
      nativeReadRow(resolveDbPtr(dbPtr));

  @override
  bool isNull(int dbPtr, int colIndex) =>
      nativeIsNull(resolveDbPtr(dbPtr), colIndex) == 1;

  @override
  String getColumnText(int dbPtr, int colIndex) =>
      nativeGetColumnText(resolveDbPtr(dbPtr), colIndex).toDartString();

  @override
  int getColumnInt(int dbPtr, int colIndex) =>
      nativeGetColumnInt(resolveDbPtr(dbPtr), colIndex);

  @override
  double getColumnFloat(int dbPtr, int colIndex) =>
      nativeGetColumnFloat(resolveDbPtr(dbPtr), colIndex);

  @override
  double getColumnDouble(int dbPtr, int colIndex) =>
      nativeGetColumnDouble(resolveDbPtr(dbPtr), colIndex);

  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) {
    final ptr = nativeGetColumnBlob(resolveDbPtr(dbPtr), columnIndex);
    final length = nativeGetColumnBytes(resolveDbPtr(dbPtr), columnIndex);
    return ptr.asTypedList(length);
  }

  @override
  int getColumnBytes(int dbPtr, int columnIndex) =>
      nativeGetColumnBytes(resolveDbPtr(dbPtr), columnIndex);

  @override
  String getColumnName(int dbPtr, int colIndex) =>
      nativeGetColumnName(resolveDbPtr(dbPtr), colIndex).toDartString();

  @override
  int getColumnType(int dbPtr, int colIndex) =>
      nativeGetColumnType(resolveDbPtr(dbPtr), colIndex);

  @override
  int getColumnCount(int dbPtr) =>
      nativeGetColumnCount(resolveDbPtr(dbPtr));

  @override
  String? getLastDbError(int dbPtr) {
    final errorPtr = nativeGetLastDbError(resolveDbPtr(dbPtr));

    if (errorPtr == nullptr || errorPtr.address == 0) {
      return null;
    }

    return errorPtr.toDartString();
  }

  @override
  int getAffectedRows(int dbPtr) =>
      nativeGetAffectedRows(resolveDbPtr(dbPtr));

  @override
  int getLastInsertedId(int dbPtr) =>
      nativeGetLastInsertedId(resolveDbPtr(dbPtr));

  @override
  Future closeReader(int dbPtr) async =>
      nativeCloseReader(resolveDbPtr(dbPtr));

  @override
  Future closeDb(int dbPtr) async =>
      nativeCloseDb(resolveDbPtr(dbPtr));

  // ── Connection Pool (Dart-managed, general-purpose) ─────────────────

  static int _nextPoolKey = 1;
  static final Map<int, DbasSqliteConnectionPool> _nativePools = {};

  @override
  Future<int> createPool(String path, int readerCount) async {
    final connections = <DbasSqliteDb>[];

    // Open readerCount + 1 general-purpose connections (all read-write)
    for (int i = 0; i <= readerCount; i++) {
      final ptr = await openDb(path);
      if (ptr == 0 || !isOpened(ptr)) {
        // Close any already-opened connections before throwing
        for (final c in connections) {
          nativeCloseDb(resolveDbPtr(c.ptr));
        }
        throw Exception('Failed to open connection $i for pool: $path');
      }
      connections.add(DbasSqliteDb(dbName, ptr));

      // Enable WAL mode on every connection
      Pointer<Utf8> walPtr = nullptr;
      try {
        walPtr = 'PRAGMA journal_mode=WAL'.toNativeUtf8();
        nativeExecuteSql(resolveDbPtr(ptr), walPtr);
      } finally {
        if (walPtr != nullptr) calloc.free(walPtr);
      }
    }

    final key = _nextPoolKey++;
    _nativePools[key] = DbasSqliteConnectionPool(connections);
    return key;
  }

  @override
  int poolGetWriter(int poolPtr) =>
      _nativePools[poolPtr]?.writer.ptr ?? 0;

  @override
  int poolAcquireReader(int poolPtr) =>
      _nativePools[poolPtr]?.acquireReader()?.ptr ?? 0;

  @override
  void poolReleaseReader(int poolPtr, int readerPtr) =>
      _nativePools[poolPtr]?.releaseConnection(readerPtr);

  @override
  Future<void> closePool(int poolPtr) async {
    final pool = _nativePools.remove(poolPtr);
    if (pool == null) return;
    for (final conn in pool.all) {
      nativeCloseDb(resolveDbPtr(conn.ptr));
    }
  }
}

