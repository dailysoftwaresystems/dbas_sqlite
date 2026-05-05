---
name: dbas-sqlite-flutter
description: >
  DBAS.SQLite.Flutter repository guide — architecture, platform abstraction layers, native C FFI bindings,
  web JS interop, connection pooling (WAL mode), public API, database lifecycle, transactions, testing,
  and contribution guidelines.
user-invocable: true
argument-hint: "[topic or question]"
---

# DBAS.SQLite.Flutter — Repository Guide Skill

You are assisting with the **DBAS.SQLite.Flutter** project. The rules below are a comprehensive
reference for the repository structure and conventions.

---

## 1. Overview

- **dbas_sqlite** is a multiplatform Flutter plugin providing direct SQLite access on
  Android, iOS, macOS, Linux, Windows, and Web.
- Wraps a native C library (`dbas_sqlite.cpp`) via FFI on native platforms and a JS/WASM wrapper
  (`dbas_sqlite_wrapper.js`) on web.
- Main responsibilities: database open/close, SQL execution, parameterized queries (positional and named),
  row-by-row reading, typed column accessors, binary blob support, transactions, connection pooling
  (WAL mode with writer + readers), streaming database attach/copy, and database export/drop.
- Main technologies: **Dart / Flutter**, **C / SQLite** (native library), **Emscripten / WASM** (web),
  **dart:ffi** (FFI binding), **dart:js_interop** (web binding).

---

## 2. Package Structure

| Directory | Purpose |
|-----------|---------|
| `lib/` | Public API surface and source code |
| `lib/dbas_sqlite.dart` | Barrel file exporting `DbasSqlite` and `SqliteColumnType` |
| `lib/src/` | Internal implementation |
| `lib/src/native/` | Platform-specific native implementations |
| `lib/src/native/stub/` | Stub implementations for unsupported platforms |
| `lib/src/stub/` | Web stub for `DbasSqliteDb` (no `dart:ffi`) |
| `lib/src/helpers/` | Platform utility helpers |
| `test/` | Automated tests |
| `example/` | Sample application consuming the plugin |
| `scripts/` | Build, dependency and run helper scripts |
| `native_libs/` | Pre-built native SQLite binaries per platform |
| `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/` | Platform glue and bundled native libraries |

---

## 3. Architecture — Layered Abstraction

The plugin uses a layered architecture with platform-conditional compilation:

```
DbasSqlite (public API)
  └─ DbasSqlitePlatform (platform dispatcher, routes by dbName)
       └─ DbasSqliteNativeInterface (abstract contract)
            ├─ DbasSqliteNativeAppBase (shared FFI marshalling)
            │    ├─ DbasSqliteNativeApp [FFI] (DynamicLibrary.open + lookupFunction)
            │    └─ DbasSqliteNativeApp [IO/AOT] (@Native compile-time linking)
            ├─ DbasSqliteNativeWeb (dart:js_interop → JS wrapper → WASM)
            └─ Stubs (UnsupportedError for wrong platform)
```

### Platform Selection (`dbas_sqlite_native_app_selector.dart`)

Uses conditional exports to pick the right implementation at compile time:
- `dart.library.ffi` → FFI implementation
- `dart.library.io` → AOT/IO implementation
- `dart.library.js_interop` → Web implementation (for interface) / Stub (for app)
- Default → Stub

### Key Files

| File | Role |
|------|------|
| `lib/src/dbas_sqlite.dart` | **Public API** — `DbasSqlite` class, singleton per dbName |
| `lib/src/dbas_sqlite_platform.dart` | Platform dispatcher, delegates to native interface by dbName |
| `lib/src/dbas_sqlite_db.dart` | `DbasSqliteDb` (name + pointer) and FFI structs (`DbasSqliteDbStruct`, `DbasSqlitePoolStruct`) |
| `lib/src/dbas_sqlite_column_type.dart` | `SqliteColumnType` enum |
| `lib/src/native/dbas_sqlite_native_interface.dart` | Abstract contract for all native operations |
| `lib/src/native/dbas_sqlite_native_app_base.dart` | Shared FFI marshalling (pointer alloc, try/finally, file I/O) |
| `lib/src/native/dbas_sqlite_native_app_ffi.dart` | FFI: `DynamicLibrary.open` + `lookupFunction` |
| `lib/src/native/dbas_sqlite_native_app_io.dart` | AOT: `@Native` annotations for compile-time linking |
| `lib/src/native/dbas_sqlite_native_web.dart` | Web: `dart:js_interop` bindings to JS wrapper |

---

## 4. Native C Library

The native C library (`dbas_sqlite.cpp`) compiled per platform exposes:

### Single Connection
- `OpenDb`, `IsOpened`, `CloseDb`, `CloseReader`
- `ExecuteSql`, `PrepareQuery`, `ReadRow`
- `BindText/Int/Float/Double/Null/Blob` (positional and named variants)
- `GetColumnText/Int/Float/Double/Blob/Bytes/Name/Type/Count`
- `GetLastDbError`, `GetAffectedRows`, `GetLastInsertedId`

### Connection Pool (WAL mode)
- `CreatePool(fileName, readerCount)` — opens 1 writer (WAL mode) + N read-only readers
- `PoolGetWriter(pool)` — returns the writer connection
- `PoolAcquireReader(pool)` — returns a free reader (or nullptr if all busy)
- `PoolReleaseReader(pool, reader)` — marks a reader as available
- `ClosePool(pool)` — closes all connections

### FFI Structs (Dart mirror in `dbas_sqlite_db.dart`)

```c
typedef struct SQLiteDb {
    sqlite3* db;
    sqlite3_stmt* stmt;
    char* lastError;
    char* fileName;
} SQLiteDb;

typedef struct SQLitePool {
    SQLiteDb* writer;
    SQLiteDb** readers;
    bool* readerBusy;
    int readerCount;
    char* fileName;
} SQLitePool;
```

---

## 5. Web Implementation

On web, the plugin uses an Emscripten-compiled WASM module with a JS wrapper class (`DbasSqliteWrapper`):

- **OPFS backend** — database files stored in the Origin Private File System for persistence
- **Sync access handles** — uses `createSyncAccessHandle()` for direct read/write
- The JS wrapper exposes methods matching the C API (`openDb`, `executeSql`, `prepareQuery`, etc.)
- Pool support via `createPool(size)` returning a JS object with `poolPtr`, `writer`, `acquireReader()`, `releaseReader()`, `close()`
- The Dart `DbasSqliteNativeWeb` stores the JS pool object in a `Map<int, JSObject>` keyed by poolPtr

---

## 6. Connection Pooling — Implicit

Pooling is **automatic and transparent** to the consumer:

- `openDb({readerPoolSize: 4})` creates a pool (1 WAL-mode writer + 4 read-only readers) by default
- If `readerPoolSize = 0` or pool creation fails, falls back to a single connection
- **Writes** (`executeSql`, `beginTransaction`, `commit`, `rollback`) always use the **writer** (`_db`)
- **Reads** (`executeReader`) automatically **acquire a reader** from the pool
- `closeReader()` automatically **releases the reader** back to the pool
- All `getColumn*`, `readRow`, `isColumnNull`, `getColumnCount`, `getColumnName`, `getColumnType` use the active reader
- `getLastInsertedId` always uses the writer
- **Contention handling**: if all readers are busy, retries up to 10 times with 2ms delays (yielding to event loop), then falls back to the writer

---

## 7. Public API — `DbasSqlite`

### Lifecycle
| Method | Description |
|--------|-------------|
| `getInstance({dbName})` | Singleton per database name |
| `openDb({readerPoolSize})` | Opens database with connection pool |
| `isOpened()` | Check if connection is open |
| `closeDb()` | Closes pool/connection, removes from cache |
| `databaseExists()` | Checks if database file exists |
| `dropDb()` | Deletes database + journal files |
| `getAppDatabasePath({dbName})` | Resolves full path (platform-aware) |

### Database Content
| Method | Description |
|--------|-------------|
| `attachDb(bytes)` | Write database from byte list |
| `attachStreamDb(stream)` | Write database from byte stream |
| `streamCopyDb(destDbName)` | Stream-copy current database to a new name |
| `getContent()` | Read database as raw bytes |

### SQL Execution
| Method | Description |
|--------|-------------|
| `executeSql(sql, {params, nameParams})` | Execute DML/DDL, returns affected rows |
| `executeReader(sql, {params, nameParams})` | Prepare SELECT for row-by-row reading |
| `readRow()` | Advance to next row (`true` = has data) |
| `closeReader()` | Close prepared statement early |

### Column Accessors
Each has a nullable variant (`getColumnNullable*`):
- `getColumnText`, `getColumnInt`, `getColumnDouble`, `getColumnBool`
- `getColumnDecimal`, `getColumnDateTime`, `getColumnTime`
- `getColumnEnum<T>`, `getColumnBlob`
- `getColumnName`, `getColumnType`, `getColumnCount`
- `isColumnNull`, `getLastInsertedId`

### Transactions
| Method | Description |
|--------|-------------|
| `beginTransaction()` | Begin (idempotent if already active) |
| `commit()` | Commit (rolls back on failure) |
| `rollback()` | Rollback (idempotent if no transaction) |
| `transaction(action)` | Auto commit/rollback wrapper |
| `isInTransaction` | Check if transaction is active |

---

## 8. Parameter Binding

Supports both positional and named parameters:

```dart
// Positional (1-based internally)
await db.executeSql('INSERT INTO t (a, b) VALUES (?, ?)', params: ['Alice', 30]);

// Named (auto-prefixed with ':' if needed)
await db.executeSql('INSERT INTO t (a) VALUES (:name)', nameParams: {'name': 'Alice'});
```

Supported types: `null`, `bool`, `int`, `double`, `Decimal`, `String`, `Uint8List`, `Enum`.

---

## 9. Testing

### Running Tests
```bash
flutter test                                           # All tests
flutter test test/dbas_sqlite_test.dart         # Specific test file
```

### Test Mode
- Detected via `FLUTTER_TEST` environment variable (`DbasSqlitePlatformUtil.isTest()`)
- Test databases stored in `test/db/` directory
- Native library paths resolved relative to project root (handles running from `example/` subdirectory)

---

## 10. Native Library Paths

| Platform | Production | Test |
|----------|-----------|------|
| Android | `dbas_sqlite.so` (bundled via jniLibs) | — |
| iOS / macOS | `DynamicLibrary.process()` (xcframework) | dylib from `macos/libs/` |
| Windows | `dbas_sqlite.dll` | `windows/libs/{arch}/dbas_sqlite.dll` |
| Linux | `dbas_sqlite.so` | `linux/libs/dbas_sqlite.so` |
| Web | `dbas_sqlite.js` (WASM + JS wrapper) | — |

---

## 11. Contribution Guidelines

### Adding a New Native Function
1. Add to C header (`dbas_sqlite.h`) and implementation (`dbas_sqlite.cpp`)
2. Add to JS wrapper (`dbas_sqlite_wrapper.js`) for web
3. Add to `DbasSqliteNativeInterface` (abstract method)
4. Add to `DbasSqliteNativeAppBase` (abstract native method + shared implementation with marshalling)
5. Add to `DbasSqliteNativeApp` FFI (late field + lookupFunction + native delegate)
6. Add to `DbasSqliteNativeApp` IO/AOT (@Native declaration + native delegate)
7. Add to `DbasSqliteNativeWeb` (JS extension + implementation)
8. Add to both stub files (UnsupportedError)
9. Add to `DbasSqlitePlatform` (pass-through)
10. Add to `DbasSqlite` (public API)

### Naming Conventions
- **UpperCamelCase** — classes and types
- **lowerCamelCase** — variables, parameters, functions, methods
- **lowercase_with_underscores** (snake_case) — file and directory names
- Native C functions use **PascalCase** (e.g., `OpenDb`, `ExecuteSql`)
- JS wrapper methods use **camelCase** (e.g., `openDb`, `executeSql`)

### Change Philosophy
- **Small changes first.** Never do big refactors unless explicitly approved.
- **Reuse existing infrastructure.** Search for existing patterns before introducing new ones.
- All layers must stay in sync — a change in the native interface requires updates across all implementations and stubs.
