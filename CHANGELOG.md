# Changelog

All notable changes to this project will be documented in this file.

## 2.5.0 - 2026-05-05

### Added

- **`DbasSqliteStatement.executeScalar({params, nameParams})`** — runs the
  prepared statement as a SELECT and returns the first column of the first
  row as a `dynamic` (typed by SQLite column kind: `int`, `double`,
  `String`, `Uint8List`). Returns `null` when the query produces no rows
  or the first column is SQL NULL. Closes both the reader and the
  statement before returning, so the statement becomes single-use. Same
  input parameters and connection routing as `executeReader`.

### Changed

- **In-transaction read routing is now automatic.** `executeReader` and
  `executeScalar` route through a pool reader (native) or `pool.query`
  (web) until the first `executeSql` runs in the current transaction;
  after that, subsequent in-tx reads switch to the writer connection so
  they observe the transaction's uncommitted writes (read-your-writes).
  Previously, in-tx reads always used the writer connection on native,
  serialising parallel pre-write validation behind the single writer.
  Now `Future.wait([executeReader, executeReader, ...])` issued before
  any write in a transaction runs concurrently against the pool. After
  any `executeSql`, the routing flips automatically; on `commit` /
  `rollback` it resets. No caller-side flag needed.

- **Web in-transaction reads no longer throw.** Previously, calling
  `executeReader` inside a transaction on web threw `UnsupportedError`
  because the bundled JS worker can't return SELECT rows through the
  writer-only `pool.exec` channel. The library now routes web reads
  through `pool.query` regardless of transaction state — the web pool
  fronts a single worker holding the writer connection, so `pool.query`
  observes in-flight transactional state automatically.

## 2.4.4 - 2026-05-05

Re-publish of 2.4.1. Earlier release-pipeline runs (2.4.1 – 2.4.3) were
blocked by GitHub App configuration, pub.dev OIDC wiring, and a tag-pattern
mismatch on pub.dev's automated-publishing config. Package contents are
identical to what 2.4.1 was meant to ship.

## 2.4.1 - 2026-05-05

First public pub.dev release under the verified publisher
[dailysoftwaresystems.com](https://pub.dev/publishers/dailysoftwaresystems.com).
Functionally identical to 2.4.0 — this release exists to ship the
build / packaging / governance fixes needed to publish.

### Changed

- **License**: relicensed from proprietary to **Apache 2.0**, matching
  the sibling `DBAS.SQLite` native lib. The Apache license includes an
  explicit patent grant, which is appropriate for a plugin that ships
  prebuilt native binaries via FFI.
- **README install snippet** updated to the pub.dev syntax
  (`dbas_sqlite: ^2.4.1`) instead of the git URL.

### Fixed

- **macOS desktop link failure**: the macOS podspec did not declare
  `s.libraries = 'c++'`, so consumer apps failed to link with
  `Undefined symbols: std::__1::*, ___cxa_throw,
  ___gxx_personality_v0`. Added the libc++ link declaration; iOS was
  already correct.
- **Windows desktop DLL bundling**: the `<package_name>_bundled_libraries`
  CMake variable still used the pre-rename name, so Flutter no longer
  saw the bundle declaration and the runner kept loading a stale DLL
  that didn't export `GetSqliteVersion`. Renamed to match the new
  package name.
- **Android Gradle compile**: replaced the `org.yaml.snakeyaml.Yaml`
  pubspec parse in `android/build.gradle` with a regex match — newer
  Gradle versions no longer ship snakeyaml on the default classpath.
- **AGP 9 forward-compat**: added `android.newDsl=false` to
  `example/android/gradle.properties`. Flutter apps that depend on
  plugins are not yet supported on AGP 9
  ([flutter/flutter#181383](https://github.com/flutter/flutter/issues/181383)) —
  this flag preserves the old DSL parsing so the build keeps working
  when AGP 9 lands. Remove it once Flutter completes its AGP 9
  migration.

### Added

- **`Pipeline` GitHub Actions workflow** (`.github/workflows/ci.yml`):
  PR runs `flutter analyze` + native tests + web integration tests;
  push-to-main with a bumped `version:` creates a GitHub release;
  tag push triggers OIDC publish to pub.dev.
- **`SECURITY.md`** — disclosure policy pointing security reports to
  `security@dailysoftwaresystems.com`.
- **`CODEOWNERS`** — every PR requires review from the DBAS dev team.

### Internal

- Plugin renamed across native folders: `dbas_sqlite_flutter_plugin` C++
  classes → `dbas_sqlite_plugin`, Kotlin `DbasSqliteFlutterPlugin` →
  `DbasSqlitePlugin`, Swift `DbasSqliteFlutterPlugin` →
  `DbasSqlitePlugin`, podspec files renamed, Android namespace
  `com.dailysoftwaresystems.dbas.sqlite.flutter` →
  `com.dailysoftwaresystems.dbas.sqlite`. No public Dart API change —
  the package name was already `dbas_sqlite` in 2.4.0.

## 2.4.0 - 2026-05-05

### Breaking Changes

- **Package renamed from `dbas_sqlite_flutter` to `dbas_sqlite`**: update your imports and pubspec dependency. The library export path stays the same — `package:dbas_sqlite/dbas_sqlite.dart`.
- **`db.executeSql(...)`, `db.executeReader(...)` and `db.getLastInsertedId()` removed**. Replaced by an explicit `DbasSqliteStatement` returned from `db.prepareQuery(sql)`. The statement owns parameter binding and execution; `getAffectedRows` / `getLastInsertedId` / `getLastError` move from the database to the statement (per-statement, race-free under concurrent inserts).
- `DbasSqliteReader` column accessors are unchanged from v2.3.x — only the path that produces a reader is new.

### Added

- **`DbasSqliteStatement`**: prepared statement object with fluent positional and named bind methods, `executeSql` / `executeReader` execution modes, per-statement `getAffectedRows` / `getLastInsertedId` / `getLastError`, and `close`. The bind buffer survives a failed execute so the caller can fix one slot and retry.
- **Multiple statements + readers per database**: the upgraded native lib lets multiple prepared statements live on a single connection; on Dart, two statements with overlapping `executeReader` calls each get their own pool slot and run in parallel.
- **Multi-isolate FFI worker pool**: replaces the single worker isolate. Worker count auto-floors to `max(workerPoolSize, readerPoolSize + 2)` so blocking pool acquires can never starve concurrent releases. Dead workers are removed from the dispatch rotation; dispatch is prefer-free over round-robin.
- **`PoolAcquireReaderBlocking` integration**: `executeReader` blocks up to `DbasSqlite.kPoolAcquireTimeoutMs` (default 30 s) for a free pool slot instead of silently falling back to the writer. On timeout, throws `TimeoutException` with a clear message.
- **New utility methods on `DbasSqlite`**: `getSqliteVersion`, `getTotalChanges`, `getDbFileName`, `setBusyTimeout`, `enableWal`.
- **Web in-transaction reads** route through `pool.exec` (writer worker, EXCLUSIVE MRSW fence) so reads observe in-flight transactional state.
- **Web pool dead-state surfacing**: when the JS pool can't return rows for an in-transaction SELECT (current bundled worker), the Dart side throws a clear `UnsupportedError` instead of silently returning empty.
- **Opaque FFI structs**: `DbasSqliteDbStruct` and `DbasSqlitePoolStruct` are now `Opaque {}`. The native C lib has changed layout across versions; treating the structs as opaque eliminates the silent-misread risk and aligns with the C header's stated ABI policy.
- **15 new tests** covering: counter cache after reader auto-close, column metadata before first row, bind error rc surfacing, bind buffer preservation on failure, `setBusyTimeout` termination + busy-reader contract, multi-statement concurrency, statement reuse, per-statement state isolation, and forgotten-statement cleanup on `closeDb`.

### Changed

- **`prepareQuery`** at the platform layer now returns `({int handle, int columnCount, List<String> columnNames})` so column metadata is available to the reader BEFORE the first `readRow` call.
- **Per-stmt counters are read BEFORE finalize** in the reader's onClose closure. Reading them after finalize would always return -1 (stale-handle sentinel).
- **Bind methods at the platform layer return `Future<int>`**; the FFI variant awaits the worker dispatch so bind errors (SQLITE_RANGE / SQLITE_TOOBIG / SQLITE_NOMEM / stale handle) propagate to the caller instead of being silently swallowed.
- **`closeDb` cleanup discipline**: tracked statements are closed first, then the pool is force-drained via `ClosePool` (defensive), then on the single-connection path `CloseDb` is called and any returned `SQLITE_BUSY` raises a loud `StateError` instead of silent leak.
- **`rollback`** now wraps a failed `ROLLBACK` in a `StateError` and rethrows so callers know the C-side autocommit state may be inconsistent — instead of silently clearing `_isInTransaction`.
- **`dropDb`** now attempts every deletion (`.db`, `-wal`, `-shm`, `-journal`) and aggregates failures into a single `FileSystemException` so partial cleanup is impossible.
- **`DbasSqliteReader.close()`** caches its close future so concurrent close calls (auto-close on `DONE` + explicit close) all observe the same completion instead of one returning early while cleanup is still mid-flight.
- **`DbasSqliteReader.readRow()`** error-path reads `getLastStmtError(handle)` (per-stmt) instead of `getLastDbError(conn)` (connection-scoped) — fixes a v2.3.x latent bug where errors from one statement's step could be masked by another's.
- **Web `enableWal`** now actively verifies via `PRAGMA journal_mode` instead of a silent no-op.

### Removed

- **`setWriteMode` / `beginTransactionLease` / `endTransactionLease`** indirection on `DbasSqliteNativeInterface` and its forwarders. Direct routing through `pool.exec` / `pool.query` makes them obsolete.
- **`DbasSqliteNativeApp` IO/AOT variant** (`dbas_sqlite_native_app_io.dart`): the conditional export selector always picked the FFI variant on every platform that has `dart.library.ffi`, which is every Flutter target except web. The IO/AOT variant was dead code; removed.
- **Old `lib/src/native/dbas_sqlite_row_cache.dart`**: relocated to `lib/src/dbas_sqlite_row_cache.dart`. The cache is now an owned-by-reader concern, not a native-internal concern. Per-stmt counter / lastError fields removed from `RowData` since they live on `DbasSqliteStatement`.

### Migration Guide

```dart
// Before (2.3.x)
import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';

final affected = await db.executeSql(
  'INSERT INTO users (name) VALUES (?)',
  params: ['Alice'],
);
final id = db.getLastInsertedId();

final reader = await db.executeReader(
  'SELECT * FROM users WHERE id > ?', params: [0],
);
while (await reader.readRow()) { ... }
await reader.close();

// After (2.4.0)
import 'package:dbas_sqlite/dbas_sqlite.dart';

final insertStmt = await db.prepareQuery('INSERT INTO users (name) VALUES (?)');
try {
  final affected = await insertStmt.executeSql(params: ['Alice']);
  final id = insertStmt.getLastInsertedId();
} finally {
  await insertStmt.close();
}

final selectStmt = await db.prepareQuery('SELECT * FROM users WHERE id > ?');
try {
  final reader = await selectStmt.executeReader(params: [0]);
  try {
    while (await reader.readRow()) { ... }
  } finally {
    await reader.close();
  }
} finally {
  await selectStmt.close();
}
```

A statement can be reused with different params per execute — the bind buffer is replayed against a fresh native handle on each call:

```dart
final stmt = await db.prepareQuery('INSERT INTO users (name) VALUES (?)');
try {
  for (final name in ['Alice', 'Bob', 'Carol']) {
    await stmt.executeSql(params: [name]);
  }
} finally {
  await stmt.close();
}
```

## 2.3.0 - 2026-04-13

### Breaking Changes

- **`executeReader` now returns `DbasSqliteReader`**: Instead of storing reader state on the `DbasSqlite` instance, `executeReader` returns an independent `DbasSqliteReader` object. All column access methods (`getColumnText`, `getColumnInt`, `readRow`, `isColumnNull`, etc.) are now on the reader, not on `DbasSqlite`.
- **`closeReader()` removed from `DbasSqlite`**: Use `reader.close()` on the returned `DbasSqliteReader` instead.
- **`readRow()` removed from `DbasSqlite`**: Use `reader.readRow()` on the returned `DbasSqliteReader` instead.
- **All `getColumn*` methods removed from `DbasSqlite`**: Use the corresponding methods on `DbasSqliteReader` instead.
- **Readers must be explicitly closed**: The old auto-cleanup (`_closePendingReader`) no longer exists. Readers that don't exhaust all rows must be closed with `reader.close()` before the connection can be reused. `readRow()` still auto-closes when it returns `false`.

### Added

- **`DbasSqliteReader` class**: Independent reader object returned by `executeReader`. Each reader owns its own database connection (from the pool or writer fallback) and prepared statement. Multiple readers can coexist simultaneously, enabling parallel reads.
- **`getColumnValue(index)`** on `DbasSqliteReader`: Returns the typed value of a column based on its SQLite type (int, double, text, blob, or null).
- **Active reader tracking**: `DbasSqlite` now tracks all open readers. `closeDb()` automatically closes every active reader before shutting down the pool/connection, preventing use-after-free on lingering readers.
- Exported `DbasSqliteReader` from the package barrel file.

### Changed

- **Pool reader acquisition is non-blocking**: `executeReader` now tries to acquire a pool reader without waiting. If all readers are busy, it falls back to the writer connection immediately instead of blocking.
- **Reader lock removed**: The serializing reader lock (`_acquireReaderLock`/`_releaseReaderLock`) is no longer used by `executeReader`, since each reader independently manages its own pool connection lifecycle.
- **`closeDb()` closes active readers**: All open `DbasSqliteReader` instances are closed before the database connection is shut down, ensuring pool connections and writer locks are properly released.

### Migration Guide

```dart
// Before (2.2.x)
await db.executeReader('SELECT * FROM users');
while (await db.readRow()) {
  print(db.getColumnText(0));
}
await db.closeReader();

// After (2.3.0)
final reader = await db.executeReader('SELECT * FROM users');
while (await reader.readRow()) {
  print(reader.getColumnText(0));
}
await reader.close();
```

Multiple parallel readers are now possible:

```dart
final r1 = await db.executeReader('SELECT * FROM orders');
final r2 = await db.executeReader('SELECT * FROM products');
// Both active simultaneously, each on their own pool connection
while (await r1.readRow()) { /* ... */ }
while (await r2.readRow()) { /* ... */ }
await r1.close();
await r2.close();
```

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
