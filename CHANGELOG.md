# Changelog

All notable changes to this project will be documented in this file.

## 2.2.0 - 2026-04-11

### Breaking Changes

- **Unified writer lock**: The async writer lock now applies on both web and native (previously web used a separate lease mechanism). Concurrent `executeSql` calls on web are now properly serialized instead of interleaving at `await` points. This fixes data corruption from concurrent writes but means web writes are now queued, matching native behavior.
- **Web `executeSql` errors propagate**: `DbasSqliteNativeWeb.executeSql` no longer catches exceptions and returns `-1`. Errors from `BEGIN TRANSACTION`, `COMMIT`, and `ROLLBACK` now propagate to callers instead of being silently swallowed.
- **Web `databaseExists` propagates infrastructure errors**: Previously returned `false` for any error (including OPFS unavailable, worker crash). Now uses the worker's `exists` action and lets infrastructure failures propagate.

### Added

- **Background isolate FFI worker**: All heavy native FFI operations (`executeSql`, `prepareQuery`, `readRow`, `openDb`, `closeDb`, `createPool`, `closePool`) now run on a dedicated background isolate via `DbasSqliteIsolateWorker`. Bind operations remain on the main isolate for synchronous access. This prevents FFI calls from blocking the UI thread.
- **Row data cache** (`RowData`/`ColumnData`): Shared between native and web paths. After `readRow`, all column values are cached in Dart memory for synchronous access — no FFI round-trips for `getColumn*` calls.
- **True streaming web attach** (`attachStreamBegin`/`attachStreamChunk`/`attachStreamEnd`): Database imports on web now stream chunk-by-chunk to the worker with ACK-based backpressure. The complete database is never buffered in Dart memory — critical for 500 MB+ databases.
- **Streaming web export**: `getContent()` on web now uses the `exportStream` protocol, handling both Transferable Streams (Chrome/Firefox) and chunked postMessage fallback (Safari) with ACK-based backpressure.
- **BigInt handling for `lastInsertId`**: Emscripten `long long` returns (JS BigInt) are now correctly converted to Dart `int` via JS `Number()` interop.
- **`List<int>` blob binding**: `executeSql` and `executeReader` now accept plain `List<int>` in addition to `Uint8List` for blob parameters.
- **C-level connection pool with mutex**: The native C library pool (`CreatePool`/`PoolAcquireReader`/`PoolReleaseReader`) now has `pthread_mutex_t` (POSIX) / `CRITICAL_SECTION` (Windows) protection for thread-safe reader acquire/release.
- **`transaction()` rollback error reporting**: If both the action and rollback fail, a `StateError` is thrown containing both error messages instead of silently discarding the rollback failure.
- 88 native unit tests, 25 web integration tests.

### Changed

- **Web pool architecture**: Replaced the old multi-slot web pool with a per-database `DbasSqliteWebPool` backed by a single Web Worker. Each database gets its own worker with OPFS persistence.
- **Web worker protocol**: Updated to match DBAS.SQLite 3.1.x worker — `exec`, `query`, `batch`, `drop`, `streamCopy`, `attachStreamBegin`/`Chunk`/`End`, `exportStream`, `exists`, `close`.
- **`close()` ordering**: `DbasSqliteWebPool.close()` now sends the `close` command to the worker before setting `_closed = true`, ensuring the worker gets a chance to flush WAL data and release OPFS locks.
- **Platform delegate re-creation**: `DbasSqlitePlatform.createPool` and `openDb` now lazily re-create the delegate after `dropDb` removes it, fixing null pointer crashes on the drop → open cycle.
- **`importScripts` URL**: The `libUrl` sent to the web worker is now relative to the worker script location (`dbas_sqlite.js`) instead of the page root, fixing doubled-path errors.

### Fixed

- **Concurrent writes on web**: Three or more concurrent `executeSql` calls no longer corrupt shared buffered state (`_pendingSql`, `_isWriteQuery`). The unified writer lock serializes them.
- **`getLastInsertedId` returning 0 on web**: The Emscripten `long long` return value (JS BigInt) is now correctly converted to Dart `int`.
- **Blob binding for `List<int>`**: `List<int>.generate(...)` and other non-`Uint8List` integer lists are now accepted as blob parameters.
- **`close()` not sending worker shutdown**: The worker now receives the `close` action before termination.
- **`postMessage` errors leaking completers**: If `postMessage` throws (e.g. `DataCloneError`), the registered handler/completer is cleaned up and completed with an error instead of hanging forever.
- **`attachStreamAbort` wrong ID**: The abort message now uses the original session ID for correct worker-side correlation.
- **`_readStreamToBytes` reader lock leak**: The `ReadableStream` reader lock is now released in a `finally` block on both success and error paths.
- **Unknown ReadableStream chunk types**: `_readStreamToBytes` now throws `StateError` on unrecognized chunk types instead of silently dropping bytes.
- **`exportContentStream` hang**: Added 120-second timeout to prevent indefinite hangs if the worker stops responding.
- **Isolate `ReceivePort` stream errors**: Added `onError` handler that fails all pending requests instead of leaving them hanging.

### Removed

- **`DbasSqliteConnectionPool`**: Replaced by the C-level pool managed through `DbasSqliteNativeInterface`.
- **Web transaction lease methods**: `beginTransactionLease`/`endTransactionLease` are now no-ops — transactions use the unified writer lock.

## 2.1.2 - 2026-04-09

* **Web streamed attach**: `attachStreamDb` now sends chunks individually to the Web Worker via a begin/chunk/end protocol instead of buffering the entire file in Dart memory
* Renamed database directory from `data` to `dbas_data` across all platforms
* Improved error handling: cleanup failures during stream attach are now logged instead of silently swallowed
* Updated `attachStreamDb` doc comment to reflect the new OPFS-backed streaming implementation

## 2.1.1 - 2026-04-07

* Adjust pipes

## 2.1.0 - 2026-04-07

* Adjust pipes

## 2.0.10 - 2026-04-06

* Adjust pipes

## 2.0.9 - 2026-04-06

* Fixed `executeSql` and `executeReader` only catching SQLite error codes -1 and 1 from `prepareQuery` — all non-zero codes (e.g. SQLITE_BUSY, SQLITE_NOMEM) are now properly detected, preventing `readRow` from operating on a NULL statement
* Fixed `_bindParameters` only catching error codes -1 and 1 — all non-zero bind results (e.g. SQLITE_RANGE for out-of-bounds index) are now caught
* Fixed writer-lock deadlock when `executeReader` or `executeSql` is called while a previous reader session is still open (e.g. caller read partial rows without calling `closeReader`); pending readers are now automatically closed before acquiring locks
* Fixed `executeSql` not finalizing the prepared statement when `getAffectedRows` throws — `closeReader` is now guaranteed via try-finally
* Error messages from `prepareQuery` and `_bindParameters` failures now include the SQLite error code for easier debugging
* `getLastDbError` is now captured before `closeReader` on prepare failures to prevent potential loss of error context

## 2.0.7 - 2026-04-06

* Unified `readRow` response handling between `executeSql` and `readRow` into a shared `_readRowAndValidate` method
* Replaced magic number `20` with `_sqliteMisuse` constant

## 2.0.6 - 2026-04-06

* Named parameter binding now silently skips parameters not found in the prepared statement, matching C#/SQLite behavior
* Extra named parameters no longer throw — only actual bind errors are raised
* Added `throwOnMissingNamedParams` option to throw on unknown named parameters (defaults to `false`)

## 2.0.3 - 2026-04-04

* Updated minimum platform versions: Android API 35, iOS 16.0, macOS 13.0 (Ventura)
* Updated Android compileSdk to 35, NDK r29
* Fixed CocoaPods base configuration warnings on macOS
* Fixed `--project-root` flag in run scripts causing Flutter crash
* Fixed glob patterns in `sync_sqlite_lib.sh`

## 2.0.1 - 2026-04-03

* **Connection Pool (WAL mode)**: `openDb()` now creates a pool with 1 writer + N readers (default 4), configurable via `readerPoolSize` parameter
* Pool is fully automatic and transparent -- reads use pool readers, writes use the writer, no API changes needed
* Falls back to single connection if pool creation fails or `readerPoolSize = 0`
* **Thread safety**: Writer mutex serializes all write operations (executeSql, transactions). Reader mutex serializes read sessions. Writer and reader locks are independent, allowing concurrent reads and writes via WAL mode
* Transactions hold the writer lock for their full duration; reads within a transaction use the writer connection to see uncommitted data
* **Web Worker architecture**: WASM module now runs inside a dedicated Web Worker (required for OPFS `createSyncAccessHandle`). Bind calls are buffered and flushed to the worker on `readRow`. Column data is pre-fetched and cached for sync access
* **New**: `streamCopyDb(destDbName)` - Stream-copy the current database to a new name with automatic cleanup of destination WAL/SHM files
* **New**: `attachStreamDb(stream)` - Attach a database from a byte stream
* **New**: Connection pool support wired through the full native stack (C FFI, IO/AOT, Web, stubs)
* **New**: `DbasSqlitePoolStruct` FFI struct mapping the C `SQLitePool` struct
* Updated native C library with pool functions: `CreatePool`, `PoolGetWriter`, `PoolAcquireReader`, `PoolReleaseReader`, `ClosePool`
* Updated JS wrapper with pool support and OPFS persistence
* `closeDb()` properly cleans up pool, releases all locks, and unblocks any waiters
* `closeReader()` releases the correct lock (reader lock for pool readers, writer lock for fallback)
* Added `isOpened()` guards after lock acquisition to handle `closeDb` during pending operations
* 55 unit tests covering pool, thread safety, concurrent operations, transactions, and all data types

## 1.6.2 - 2026-03-12

* `C SQLite lib ReadRow` capture error messages inside last error

## 1.6.1 - 2026-03-11

* `commit()` now performs automatic rollback if the COMMIT fails
* Added `syncWebDb: true` to `beginTransaction()`, `commit()` and `rollback()` for web persistence

## 1.6.0 - 2026-03-11

* Added Transaction API: `beginTransaction()`, `commit()`, `rollback()`
* Added `transaction()` helper with automatic commit and rollback on error
* Added `isInTransaction` getter to check active transaction state
* `closeDb()` now automatically rolls back any pending transaction before closing
* Fixed typo in `_bindParameters` error message (extra `}`)

## 1.5.1 - 2026-03-11

* Podspec versions now automatically read from `pubspec.yaml`
* Updated README installation version reference

## 1.5.0 - 2026-03-11

* Refactored native layer with Template Method pattern (`DbasSqliteNativeAppBase`)
* Added FFI implementation (`dbas_sqlite_native_app_ffi.dart`) with `DynamicLibrary` loading
* Added IO/AOT implementation (`dbas_sqlite_native_app_io.dart`) with `@Native` annotations
* Introduced platform selector (`dbas_sqlite_native_app_selector.dart`) with conditional exports
* Simplified `closeDb` implementation
* Adjusted pipes and build configuration

## 1.4.8 - 2026-03-11

* Simplified `closeDb` flow

## 1.4.7 - 2026-03-11

* Fixed memory leaks in `dbas_sqlite_native_app_io.dart`

## 1.4.6 - 2026-03-11

* Internal adjustments and fixes

## 1.4.5 - 2026-03-11

* Fixed reader resource leaks

## 1.4.4 - 2026-03-10

* Internal improvements

## 1.4.3 - 2026-03-10

* Removed unused imports

## 1.4.2 - 2026-03-10

* Adjusted `dropDb` behavior
* Removed unused imports

## 1.4.1 - 2026-03-10

* Enhanced web platform support
* Updated versions and dependencies
* Updated example project iOS version
* Updated Flutter plugins

## 1.4.0 - 2026-03-10

* **Upgraded SQLite to version 3.52.0**
* Updated all native binaries for all platforms

## 1.3.1 - 2026-02-28

* Added `getColumnTime()` to read `Duration` values from columns
* Added `getColumnNullableTime()` nullable variant

## 1.3.0 - 2025-11-07

* **Upgraded SQLite to version 3.51.0**
* Updated all native binaries for all platforms

## 1.2.12 - 2025-11-06

* Enhanced `bool` binding support — `true`/`false` mapped to `1`/`0`

## 1.2.11 - 2025-11-05

* Enhanced error messages for better debugging

## 1.2.10 - 2025-11-05

* Enhanced `isOpened()` reliability

## 1.2.9 - 2025-11-05

* Added existence check before `dropDb` to prevent errors on non-existent databases

## 1.2.8 - 2025-11-05

* Automatically close database before dropping it

## 1.2.7 - 2025-11-05

* Added `closeReader()` as a public method

## 1.2.6 - 2025-11-05

* Reader now auto-closes when all rows have been read (`readRow` returns `false`)

## 1.2.5 - 2025-11-05

* Fixed `closeReader` behavior
* Fixed `getContent` to properly read database file bytes

## 1.2.4 - 2025-11-05

* Fixed error handling order in SQL execution

## 1.2.3 - 2025-11-05

* Enhanced error reporting for failed `readRow` operations
* Added misuse detection (error code 20) with descriptive message

## 1.2.2 - 2025-11-05

* Enhanced `getLastDbError` handling

## 1.2.1 - 2025-11-05

* Fixed `getLastDbError` null pointer handling

## 1.2.0 - 2025-11-05

* Fixed parameter binding — both positional and named parameters
* Added `executeSql` overload with `params` and `nameParams` support
* Added `executeReader` overload with `params` and `nameParams` support

## 1.1.7 - 2025-10-25

* Added `getContent()` to read raw database file bytes

## 1.1.6 - 2025-10-24

* Fixed `getColumnName` return value handling

## 1.1.5 - 2025-10-24

* Added `getColumnName(index)` to retrieve column names from query results

## 1.1.4 - 2025-10-20

* Synced native libraries across all platforms

## 1.1.3 - 2025-10-20

* Added `dropDb()` to delete database files (including WAL and SHM)

## 1.1.2 - 2025-09-03

* Added `getLastInsertedId()` to retrieve the last auto-increment row ID

## 1.1.1 - 2025-09-01

* Fixed naming conventions

## 1.1.0 - 2025-09-01

* Added `attachDb(bytes)` to create/replace a database from raw bytes
* Added `databaseExists()` to check if the database file exists
* Added support for multiple database instances via `getInstance(dbName:)`

## 1.0.6 - 2025-08-13

* Added `attachDb` option for importing databases from byte arrays

## 1.0.5 - 2025-08-08

* Fixed public exports

## 1.0.4 - 2025-08-08

* Added `getColumnDateTime()` and `getColumnNullableDateTime()` for DateTime columns
* Added `getColumnEnum()` and `getColumnNullableEnum()` for enum columns
* Added `getColumnBool()` and `getColumnNullableBool()` for boolean columns
* Added `getColumnDecimal()` and `getColumnNullableDecimal()` for Decimal columns
* Added nullable variants for all column getters

## 1.0.3 - 2025-08-08

* Added `GetColumnName` feature at native level

## 1.0.2 - 2025-08-07

* Enhanced native library bundling for all platforms

## 1.0.1 - 2025-08-07

* Enhanced CMakeLists for Windows and Linux builds
* Improved automatic DLL/SO copy in post-build steps

## 1.0.0 - 2025-08-06

* 🎉 **First stable release**
* Cross-platform support: Android, iOS, macOS, Linux, Windows, Web
* Core SQLite operations: `openDb`, `closeDb`, `executeSql`, `prepareQuery`, `readRow`
* Parameter binding by index (1-based) and by name (`:param`, `@param`, `$param`)
* Column data retrieval: text, int, float, double, blob, null check, column type, column count
* `getAffectedRows()` and `getLastDbError()`
* Web support via JavaScript SQLite with IndexedDB persistence
* Native FFI integration for mobile and desktop platforms
* xcframework for iOS and macOS
* Automatic native library bundling via CMake (Windows, Linux) and podspec (iOS, macOS)
* CI/CD pipeline
* Example app with basic usage
* Unit tests for core operations

## 0.x.x - 2025-07-26 to 2025-08-06

* Initial development and platform bring-up
* WIP implementations for all platforms
* SQLite FFI layer development
* Test infrastructure setup
