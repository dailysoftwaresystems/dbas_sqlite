import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show protected;
import 'dbas_sqlite_native_interface.dart';
import 'dbas_sqlite_row_cache.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';

/// Base class for native app implementations (FFI and IO/AOT).
///
/// Contains all shared marshalling logic (Pointer allocation, try/finally,
/// file I/O). Subclasses only need to provide the raw native function calls
/// via the protected abstract [nativeXxx] methods.
abstract class DbasSqliteNativeAppBase extends DbasSqliteNativeInterface {
  DbasSqliteNativeAppBase(super.dbName);

  /// Cached row data from the last [readRow] call — column accessors read
  /// from this cache instead of making FFI calls per column.
  ///
  /// This is a single cache shared across all pool connections. This is safe
  /// because [DbasSqlite] serializes all access: `executeSql` calls
  /// `_closePendingReader()` before operating, and locks prevent concurrent
  /// reader+writer usage on the same [DbasSqliteNativeAppBase] instance.
  @protected
  final RowData rowCache = RowData();

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

  // ── Connection Pool (C-managed) ──
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
      if (valuePtr != nullptr) calloc.free(valuePtr);
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
  Future<int> prepareQuery(int dbPtr, String sql) async {
    Pointer<Utf8> sqlPtr = nullptr;
    try {
      sqlPtr = sql.toNativeUtf8();
      final rc = nativePrepareQuery(resolveDbPtr(dbPtr), sqlPtr);
      if (rc == 0) {
        // Cache column metadata after successful prepare
        final ptr = resolveDbPtr(dbPtr);
        final count = nativeGetColumnCount(ptr);
        final names = <String>[];
        for (int i = 0; i < count; i++) {
          names.add(nativeGetColumnName(ptr, i).toDartString());
        }
        rowCache.columnCount = count;
        rowCache.columnNames = names;
        rowCache.columns = null;
      }
      return rc;
    } finally {
      if (sqlPtr != nullptr) {
        calloc.free(sqlPtr);
      }
    }
  }

  @override
  Future<int> readRow(int dbPtr) async {
    final ptr = resolveDbPtr(dbPtr);
    final status = nativeReadRow(ptr);

    // SQLite result codes
    const sqliteRow = 100;

    if (status == sqliteRow) {
      // Cache all column values so getColumn* don't need FFI calls
      final count = nativeGetColumnCount(ptr);
      rowCache.columnCount = count;
      final columns = <ColumnData>[];
      for (int i = 0; i < count; i++) {
        final type = nativeGetColumnType(ptr, i);
        final isNull = nativeIsNull(ptr, i) == 1;
        dynamic value;
        if (!isNull) {
          switch (type) {
            case 1: // SQLITE_INTEGER
              value = nativeGetColumnInt(ptr, i);
            case 2: // SQLITE_FLOAT
              value = nativeGetColumnDouble(ptr, i);
            case 3: // SQLITE_TEXT
              value = nativeGetColumnText(ptr, i).toDartString();
            case 4: // SQLITE_BLOB
              final blobPtr = nativeGetColumnBlob(ptr, i);
              final length = nativeGetColumnBytes(ptr, i);
              value = blobPtr.asTypedList(length).toList();
            default:
              value = null;
          }
        }
        columns.add(ColumnData(type: type, isNull: isNull, value: value));
      }
      rowCache.columns = columns;
    } else {
      rowCache.columns = null;
    }

    // Cache state for post-read access
    rowCache.affectedRows = nativeGetAffectedRows(ptr);
    rowCache.lastInsertedId = nativeGetLastInsertedId(ptr);
    final errorPtr = nativeGetLastDbError(ptr);
    rowCache.lastError = (errorPtr == nullptr || errorPtr.address == 0)
        ? null
        : errorPtr.toDartString();

    return status;
  }

  @override
  bool isNull(int dbPtr, int colIndex) =>
      rowCache.columns?[colIndex].isNull ?? true;

  @override
  String getColumnText(int dbPtr, int colIndex) =>
      rowCache.columns?[colIndex].value?.toString() ?? '';

  @override
  int getColumnInt(int dbPtr, int colIndex) =>
      toIntSafe(rowCache.columns?[colIndex].value);

  @override
  double getColumnFloat(int dbPtr, int colIndex) =>
      toDoubleSafe(rowCache.columns?[colIndex].value);

  @override
  double getColumnDouble(int dbPtr, int colIndex) =>
      toDoubleSafe(rowCache.columns?[colIndex].value);

  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) {
    final value = rowCache.columns?[columnIndex].value;
    if (value is List) return value.cast<int>();
    return [];
  }

  @override
  int getColumnBytes(int dbPtr, int columnIndex) =>
      getColumnBlob(dbPtr, columnIndex).length;

  @override
  String getColumnName(int dbPtr, int colIndex) =>
      colIndex < rowCache.columnNames.length ? rowCache.columnNames[colIndex] : '';

  @override
  int getColumnType(int dbPtr, int colIndex) =>
      rowCache.columns?[colIndex].type ?? 5;

  @override
  int getColumnCount(int dbPtr) => rowCache.columnCount;

  @override
  String? getLastDbError(int dbPtr) => rowCache.lastError;

  @override
  int getAffectedRows(int dbPtr) => rowCache.affectedRows;

  @override
  int getLastInsertedId(int dbPtr) => rowCache.lastInsertedId;

  @override
  Future closeReader(int dbPtr) async {
    nativeCloseReader(resolveDbPtr(dbPtr));
    rowCache.columns = null;
  }

  @override
  Future closeDb(int dbPtr) async =>
      nativeCloseDb(resolveDbPtr(dbPtr));

  // ── Connection Pool (C-managed) ─────────────────────────────────────

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
  int poolGetWriter(int poolPtr) {
    final writer = nativePoolGetWriter(resolvePoolPtr(poolPtr));
    return writer.address;
  }

  @override
  int poolAcquireReader(int poolPtr) {
    final reader = nativePoolAcquireReader(resolvePoolPtr(poolPtr));
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

