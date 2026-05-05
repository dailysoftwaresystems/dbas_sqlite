import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show protected;
import 'dbas_sqlite_native_interface.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_row_cache.dart';

/// Base class for the native FFI app implementation.
///
/// Owns shared FFI marshalling — pointer alloc/free, UTF-8 conversion,
/// blob copying. The single concrete subclass [DbasSqliteNativeApp]
/// (in `dbas_sqlite_native_app_ffi.dart`) provides the raw `nativeXxx`
/// calls via the protected abstract methods below.
///
/// The v2.4.0 ABI threads a [SQLiteStmtHandle] (uint64 → Dart `int`)
/// through every per-stmt call. There is no shared row cache here in
/// v2.4.0 — each `DbasSqliteReader` owns its own [RowData] cache,
/// populated by [readRowAndCache].
abstract class DbasSqliteNativeAppBase extends DbasSqliteNativeInterface {
  DbasSqliteNativeAppBase(super.dbName);

  /// SQLite version cached at [initialize] time. Sync return.
  String _sqliteVersion = '';

  // ── Protected abstract methods (raw native calls) ──────────────────────

  // Library-scoped
  Pointer<Utf8> nativeGetSqliteVersion();
  int nativeGetAbiVersion();

  // Connection lifecycle
  Pointer<DbasSqliteDbStruct> nativeOpenDb(Pointer<Utf8> path);
  int nativeIsOpened(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeExecuteSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);
  int nativeCloseDb(Pointer<DbasSqliteDbStruct> dbPtr, int checkpoint);
  Pointer<Utf8> nativeGetLastDbError(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeGetAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeGetLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeGetTotalChanges(Pointer<DbasSqliteDbStruct> dbPtr);
  Pointer<Utf8> nativeGetDbFileName(Pointer<DbasSqliteDbStruct> dbPtr);
  int nativeSetBusyTimeout(Pointer<DbasSqliteDbStruct> dbPtr, int ms);
  int nativeEnableWal(Pointer<DbasSqliteDbStruct> dbPtr);

  // Statement lifecycle
  int nativePrepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);
  int nativeFinalizeStmt(Pointer<DbasSqliteDbStruct> dbPtr, int handle);
  int nativeReadRow(Pointer<DbasSqliteDbStruct> dbPtr, int handle);
  Pointer<Utf8> nativeGetLastStmtError(Pointer<DbasSqliteDbStruct> dbPtr, int handle);
  int nativeGetStmtAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr, int handle);
  int nativeGetStmtLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr, int handle);

  // Bindings (positional) — every call takes (db, handle, index, …)
  int nativeBindNull(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index);
  int nativeBindInt(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index, int value);
  int nativeBindInt64(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index, int value);
  int nativeBindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index, double value);
  int nativeBindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index, double value);
  int nativeBindText(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index, Pointer<Utf8> value);
  int nativeBindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int index, Pointer<Uint8> value, int length);

  // Bindings (named)
  int nativeBindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, int handle, Pointer<Utf8> name);
  int nativeBindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, int handle, Pointer<Utf8> name, int value);
  int nativeBindNameInt64(Pointer<DbasSqliteDbStruct> dbPtr, int handle, Pointer<Utf8> name, int value);
  int nativeBindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, int handle, Pointer<Utf8> name, double value);
  int nativeBindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, int handle, Pointer<Utf8> name, double value);
  int nativeBindNameText(Pointer<DbasSqliteDbStruct> dbPtr, int handle, Pointer<Utf8> name, Pointer<Utf8> value);
  int nativeBindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, int handle, Pointer<Utf8> name, Pointer<Uint8> value, int length);

  // Column accessors
  int nativeIsNull(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex);
  Pointer<Utf8> nativeGetColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex);
  int nativeGetColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex);
  int nativeGetColumnInt64(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex);
  double nativeGetColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex);
  double nativeGetColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex);
  Pointer<Uint8> nativeGetColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int columnIndex);
  int nativeGetColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int columnIndex);
  Pointer<Utf8> nativeGetColumnName(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int columnIndex);
  int nativeGetColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int handle, int colIndex);
  int nativeGetColumnCount(Pointer<DbasSqliteDbStruct> dbPtr, int handle);

  // Connection pool (C-managed)
  Pointer<DbasSqlitePoolStruct> nativeCreatePool(Pointer<Utf8> path, int readerCount);
  Pointer<DbasSqliteDbStruct> nativePoolGetWriter(Pointer<DbasSqlitePoolStruct> poolPtr);
  Pointer<DbasSqliteDbStruct> nativePoolAcquireReader(Pointer<DbasSqlitePoolStruct> poolPtr);
  Pointer<DbasSqliteDbStruct> nativePoolAcquireReaderBlocking(Pointer<DbasSqlitePoolStruct> poolPtr, int timeoutMs);
  void nativePoolReleaseReader(Pointer<DbasSqlitePoolStruct> poolPtr, Pointer<DbasSqliteDbStruct> readerPtr);
  void nativeClosePool(Pointer<DbasSqlitePoolStruct> poolPtr);

  // ── Pointer resolution (overridable for extra validation) ──────────────

  Pointer<DbasSqliteDbStruct> resolveDbPtr(int address) =>
      Pointer<DbasSqliteDbStruct>.fromAddress(address);

  Pointer<DbasSqlitePoolStruct> resolvePoolPtr(int address) =>
      Pointer<DbasSqlitePoolStruct>.fromAddress(address);

  // ── Library-scoped ─────────────────────────────────────────────────────

  /// Captures the SQLite version into [_sqliteVersion]. Subclasses
  /// must call this once after FFI bindings are loaded.
  @protected
  void cacheSqliteVersion() {
    final ptr = nativeGetSqliteVersion();
    _sqliteVersion = (ptr == nullptr || ptr.address == 0) ? '' : ptr.toDartString();
  }

  @override
  String getSqliteVersion() => _sqliteVersion;

  @override
  int getAbiVersion() => nativeGetAbiVersion();

  // ── Shared lifecycle implementation ────────────────────────────────────

  @override
  Future<int> openDb(String path) async {
    Pointer<Utf8> pathPtr = nullptr;
    try {
      pathPtr = path.toNativeUtf8();
      final ptr = nativeOpenDb(pathPtr);
      return ptr.address;
    } finally {
      if (pathPtr != nullptr) calloc.free(pathPtr);
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
    // Attempt every deletion even if one fails — partial cleanup is
    // worse than reporting all failures together. A leftover WAL/SHM
    // after the .db is gone produces a corrupt-looking next openDb.
    final errors = <String>[];
    for (final ext in ['', '-wal', '-shm', '-journal']) {
      final f = File('$fileName$ext');
      try {
        if (await f.exists()) await f.delete();
      } catch (e) {
        errors.add('$fileName$ext: $e');
      }
    }
    if (errors.isNotEmpty) {
      throw FileSystemException(
        'dropDb: ${errors.length} of 4 paths failed to delete:\n'
        '${errors.join("\n")}',
        fileName,
      );
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
      if (sqlPtr != nullptr) calloc.free(sqlPtr);
    }
  }

  @override
  Future<int> closeDb(int dbPtr, {bool checkpoint = false}) async =>
      nativeCloseDb(resolveDbPtr(dbPtr), checkpoint ? 1 : 0);

  @override
  String? getLastDbError(int dbPtr) {
    final ptr = nativeGetLastDbError(resolveDbPtr(dbPtr));
    return (ptr == nullptr || ptr.address == 0) ? null : ptr.toDartString();
  }

  @override
  int getAffectedRows(int dbPtr) => nativeGetAffectedRows(resolveDbPtr(dbPtr));

  @override
  int getLastInsertedId(int dbPtr) =>
      nativeGetLastInsertedId(resolveDbPtr(dbPtr));

  @override
  int getTotalChanges(int dbPtr) => nativeGetTotalChanges(resolveDbPtr(dbPtr));

  @override
  String? getDbFileName(int dbPtr) {
    final ptr = nativeGetDbFileName(resolveDbPtr(dbPtr));
    return (ptr == nullptr || ptr.address == 0) ? null : ptr.toDartString();
  }

  @override
  Future<int> setBusyTimeout(int dbPtr, int ms) async =>
      nativeSetBusyTimeout(resolveDbPtr(dbPtr), ms);

  @override
  Future<int> enableWal(int dbPtr) async => nativeEnableWal(resolveDbPtr(dbPtr));

  // ── Statement lifecycle ────────────────────────────────────────────────

  @override
  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(int dbPtr, String sql) async {
    Pointer<Utf8> sqlPtr = nullptr;
    try {
      sqlPtr = sql.toNativeUtf8();
      final ptr = resolveDbPtr(dbPtr);
      final handle = nativePrepareQuery(ptr, sqlPtr);
      if (handle == sqliteInvalidStmtHandle) {
        return (
          handle: handle,
          columnCount: 0,
          columnNames: const <String>[],
        );
      }
      // Capture column metadata once — stable for the lifetime of the
      // prepared statement, available before the first step.
      final count = nativeGetColumnCount(ptr, handle);
      final names = <String>[];
      for (int i = 0; i < count; i++) {
        final namePtr = nativeGetColumnName(ptr, handle, i);
        names.add((namePtr == nullptr || namePtr.address == 0)
            ? ''
            : namePtr.toDartString());
      }
      return (handle: handle, columnCount: count, columnNames: names);
    } finally {
      if (sqlPtr != nullptr) calloc.free(sqlPtr);
    }
  }

  @override
  Future<int> finalizeStmt(int dbPtr, int handle) async =>
      nativeFinalizeStmt(resolveDbPtr(dbPtr), handle);

  @override
  Future<int> readRowAndCache(int dbPtr, int handle, RowData cache) async {
    final ptr = resolveDbPtr(dbPtr);
    final status = nativeReadRow(ptr, handle);

    if (status == sqliteRow) {
      // columnCount / columnNames are populated at prepare time
      // (see prepareQuery). Honour the cached value but heal the
      // cache if for any reason it disagrees with the live column
      // count — defensive against future code paths that bypass
      // prepareQuery's metadata capture.
      final count = nativeGetColumnCount(ptr, handle);
      if (cache.columnCount != count) cache.columnCount = count;
      if (cache.columnNames.length != count) {
        final names = <String>[];
        for (int i = 0; i < count; i++) {
          names.add(nativeGetColumnName(ptr, handle, i).toDartString());
        }
        cache.columnNames = names;
      }
      final columns = <ColumnData>[];
      for (int i = 0; i < count; i++) {
        final type = nativeGetColumnType(ptr, handle, i);
        final isNull = nativeIsNull(ptr, handle, i) == 1;
        dynamic value;
        if (!isNull) {
          switch (type) {
            case 1: // SQLITE_INTEGER
              value = nativeGetColumnInt64(ptr, handle, i);
            case 2: // SQLITE_FLOAT
              value = nativeGetColumnDouble(ptr, handle, i);
            case 3: // SQLITE_TEXT
              value = nativeGetColumnText(ptr, handle, i).toDartString();
            case 4: // SQLITE_BLOB
              final blobPtr = nativeGetColumnBlob(ptr, handle, i);
              final length = nativeGetColumnBytes(ptr, handle, i);
              value = blobPtr.asTypedList(length).toList();
            default:
              // Unknown SQLite type code — surface loudly so a
              // future SQLite extension or a custom type doesn't
              // silently lose its value. Treat as text (the
              // C lib's GetColumnText will coerce per SQLite's
              // type-affinity rules).
              developer.log(
                'Unknown SQLite column type $type at index $i — '
                'falling back to text coercion',
                name: 'dbas_sqlite.DbasSqliteNativeAppBase',
              );
              final textPtr = nativeGetColumnText(ptr, handle, i);
              value = (textPtr == nullptr || textPtr.address == 0)
                  ? null
                  : textPtr.toDartString();
          }
        }
        columns.add(ColumnData(type: type, isNull: isNull, value: value));
      }
      cache.columns = columns;
    } else {
      cache.columns = null;
    }
    return status;
  }

  @override
  String? getLastStmtError(int dbPtr, int handle) {
    final ptr = nativeGetLastStmtError(resolveDbPtr(dbPtr), handle);
    return (ptr == nullptr || ptr.address == 0) ? null : ptr.toDartString();
  }

  @override
  int getStmtAffectedRows(int dbPtr, int handle) =>
      nativeGetStmtAffectedRows(resolveDbPtr(dbPtr), handle);

  @override
  int getStmtLastInsertedId(int dbPtr, int handle) =>
      nativeGetStmtLastInsertedId(resolveDbPtr(dbPtr), handle);

  // ── Bindings (positional) ──────────────────────────────────────────────
  // The base implementations are synchronous from Dart's perspective —
  // they call into native FFI directly. They are typed as `Future<int>`
  // in the interface so the worker variant can override them with an
  // isolate dispatch; the base supports both shapes via `async` returns.

  @override
  Future<int> bindNull(int dbPtr, int handle, int index) async =>
      nativeBindNull(resolveDbPtr(dbPtr), handle, index);

  @override
  Future<int> bindInt(int dbPtr, int handle, int index, int value) async =>
      nativeBindInt(resolveDbPtr(dbPtr), handle, index, value);

  @override
  Future<int> bindInt64(int dbPtr, int handle, int index, int value) async =>
      nativeBindInt64(resolveDbPtr(dbPtr), handle, index, value);

  @override
  Future<int> bindFloat(int dbPtr, int handle, int index, double value) async =>
      nativeBindFloat(resolveDbPtr(dbPtr), handle, index, value);

  @override
  Future<int> bindDouble(int dbPtr, int handle, int index, double value) async =>
      nativeBindDouble(resolveDbPtr(dbPtr), handle, index, value);

  @override
  Future<int> bindText(int dbPtr, int handle, int index, String value) async {
    Pointer<Utf8> valuePtr = nullptr;
    try {
      valuePtr = value.toNativeUtf8();
      return nativeBindText(resolveDbPtr(dbPtr), handle, index, valuePtr);
    } finally {
      if (valuePtr != nullptr) calloc.free(valuePtr);
    }
  }

  @override
  Future<int> bindBlob(int dbPtr, int handle, int index, List<int> value) async {
    Pointer<Uint8> ptr = nullptr;
    try {
      ptr = calloc<Uint8>(value.length);
      for (var i = 0; i < value.length; i++) {
        ptr[i] = value[i];
      }
      return nativeBindBlob(resolveDbPtr(dbPtr), handle, index, ptr, value.length);
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
    }
  }

  // ── Bindings (named) ───────────────────────────────────────────────────

  @override
  Future<int> bindNameNull(int dbPtr, int handle, String name) async {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameNull(resolveDbPtr(dbPtr), handle, namePtr);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  Future<int> bindNameInt(int dbPtr, int handle, String name, int value) async {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameInt(resolveDbPtr(dbPtr), handle, namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  Future<int> bindNameInt64(int dbPtr, int handle, String name, int value) async {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameInt64(resolveDbPtr(dbPtr), handle, namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  Future<int> bindNameFloat(int dbPtr, int handle, String name, double value) async {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameFloat(resolveDbPtr(dbPtr), handle, namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  Future<int> bindNameDouble(int dbPtr, int handle, String name, double value) async {
    Pointer<Utf8> namePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      return nativeBindNameDouble(resolveDbPtr(dbPtr), handle, namePtr, value);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  @override
  Future<int> bindNameText(int dbPtr, int handle, String name, String value) async {
    Pointer<Utf8> namePtr = nullptr;
    Pointer<Utf8> valuePtr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      valuePtr = value.toNativeUtf8();
      return nativeBindNameText(resolveDbPtr(dbPtr), handle, namePtr, valuePtr);
    } finally {
      if (namePtr != nullptr) calloc.free(namePtr);
      if (valuePtr != nullptr) calloc.free(valuePtr);
    }
  }

  @override
  Future<int> bindNameBlob(int dbPtr, int handle, String name, List<int> value) async {
    Pointer<Utf8> namePtr = nullptr;
    Pointer<Uint8> ptr = nullptr;
    try {
      namePtr = name.toNativeUtf8();
      ptr = calloc<Uint8>(value.length);
      for (var i = 0; i < value.length; i++) {
        ptr[i] = value[i];
      }
      return nativeBindNameBlob(resolveDbPtr(dbPtr), handle, namePtr, ptr, value.length);
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
      if (namePtr != nullptr) calloc.free(namePtr);
    }
  }

  // ── Column accessors — kept for ABI completeness ──────────────────────
  // Both the native pool path and the native single-connection path
  // go through `readRowAndCache` + per-reader `RowData`, so these are
  // not called from any current consumer. Leaving them in keeps the
  // FFI binding table aligned with the C header so a future
  // direct-step reader can use them without re-binding.

  @override
  bool isNull(int dbPtr, int handle, int colIndex) =>
      nativeIsNull(resolveDbPtr(dbPtr), handle, colIndex) == 1;

  @override
  String getColumnText(int dbPtr, int handle, int colIndex) {
    final ptr = nativeGetColumnText(resolveDbPtr(dbPtr), handle, colIndex);
    return (ptr == nullptr || ptr.address == 0) ? '' : ptr.toDartString();
  }

  @override
  int getColumnInt(int dbPtr, int handle, int colIndex) =>
      nativeGetColumnInt(resolveDbPtr(dbPtr), handle, colIndex);

  @override
  int getColumnInt64(int dbPtr, int handle, int colIndex) =>
      nativeGetColumnInt64(resolveDbPtr(dbPtr), handle, colIndex);

  @override
  double getColumnFloat(int dbPtr, int handle, int colIndex) =>
      nativeGetColumnFloat(resolveDbPtr(dbPtr), handle, colIndex);

  @override
  double getColumnDouble(int dbPtr, int handle, int colIndex) =>
      nativeGetColumnDouble(resolveDbPtr(dbPtr), handle, colIndex);

  @override
  List<int> getColumnBlob(int dbPtr, int handle, int columnIndex) {
    final length = nativeGetColumnBytes(resolveDbPtr(dbPtr), handle, columnIndex);
    if (length <= 0) return const [];
    final ptr = nativeGetColumnBlob(resolveDbPtr(dbPtr), handle, columnIndex);
    if (ptr == nullptr || ptr.address == 0) return const [];
    return ptr.asTypedList(length).toList();
  }

  @override
  int getColumnBytes(int dbPtr, int handle, int columnIndex) =>
      nativeGetColumnBytes(resolveDbPtr(dbPtr), handle, columnIndex);

  @override
  String getColumnName(int dbPtr, int handle, int columnIndex) {
    final ptr = nativeGetColumnName(resolveDbPtr(dbPtr), handle, columnIndex);
    return (ptr == nullptr || ptr.address == 0) ? '' : ptr.toDartString();
  }

  @override
  int getColumnType(int dbPtr, int handle, int colIndex) =>
      nativeGetColumnType(resolveDbPtr(dbPtr), handle, colIndex);

  @override
  int getColumnCount(int dbPtr, int handle) =>
      nativeGetColumnCount(resolveDbPtr(dbPtr), handle);

  // ── Connection Pool (C-managed) ────────────────────────────────────────

  @override
  Future<int> createPool(String path, int readerCount) async {
    Pointer<Utf8> pathPtr = nullptr;
    try {
      pathPtr = path.toNativeUtf8();
      final poolPtr = nativeCreatePool(pathPtr, readerCount);
      if (poolPtr == nullptr || poolPtr.address == 0) {
        throw Exception('Failed to create pool: $path');
      }
      return poolPtr.address;
    } finally {
      if (pathPtr != nullptr) calloc.free(pathPtr);
    }
  }

  @override
  int poolGetWriter(int poolPtr) =>
      nativePoolGetWriter(resolvePoolPtr(poolPtr)).address;

  @override
  int poolAcquireReader(int poolPtr) {
    final reader = nativePoolAcquireReader(resolvePoolPtr(poolPtr));
    if (reader == nullptr || reader.address == 0) return 0;
    return reader.address;
  }

  @override
  Future<int> poolAcquireReaderBlocking(int poolPtr, int timeoutMs) async {
    final reader =
        nativePoolAcquireReaderBlocking(resolvePoolPtr(poolPtr), timeoutMs);
    if (reader == nullptr || reader.address == 0) return 0;
    return reader.address;
  }

  @override
  void poolReleaseReader(int poolPtr, int readerPtr) {
    nativePoolReleaseReader(resolvePoolPtr(poolPtr), resolveDbPtr(readerPtr));
  }

  @override
  Future<void> closePool(int poolPtr) async {
    nativeClosePool(resolvePoolPtr(poolPtr));
  }
}

