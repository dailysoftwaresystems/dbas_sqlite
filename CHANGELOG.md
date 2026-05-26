# Changelog

All notable changes to this project will be documented in this file.

## 2.8.1 - 2026-05-26

### Fixed

- **Segfault during `closeDb()` on a pool with parked reader-slot
  waiters.** When the database was closed while one reader held the
  only slot and others were parked, the held reader's `onClose`
  released the slot and granted a parked waiter, which then raced into
  the native pool's blocking acquire on one worker isolate while
  `closeDb` dispatched `ClosePool` on another — tearing down the pool's
  lock/condvar underneath the parked acquire (observed as a SIGSEGV in
  test finalization on CI). `closeDb()` now latches a closing flag and
  drains both the writer-lock and reader-slot wait queues **before**
  sweeping statements, and `_acquireReaderSlot` / `_acquireWriterLock`
  reject synchronously with
  `DbasSqliteErrorCode.readerSlotWaitCancelled` /
  `writerLockWaitCancelled` once a close is in flight, so no caller can
  enter the native pool during teardown. (Native `ClosePool` is
  hardened in lockstep to drain in-flight acquires and checked-out
  readers before destroying the pool.)

### Changed

- **Pool reader acquisition now reports a specific status instead of a
  bare null.** A failed `poolAcquireReaderBlocking` distinguishes
  `closing` (terminal — the pool is tearing down) from `timeout`
  (transient — no reader freed in the window) and `invalid` (the pool
  is gone), mirroring the native `PoolLastAcquireStatus()` accessor. A
  reader acquire that loses the race to a concurrent close now surfaces
  as `readerSlotWaitCancelled` rather than being misreported as
  `executeReaderPoolAcquireTimeout`.

## 2.8.0 - 2026-05-25

### Added

- **Web: true read/write concurrency via a multi-worker connection
  pool.** `openDb()` on web now drives the native `createPool`
  coordinator — 1 writer + N reader Web Workers, each with its own
  SQLite connection, coordinated through a `SharedArrayBuffer`-backed
  WAL SHM. Reads dispatch to reader connections and writes to the writer
  connection, exactly like the native FFI pool, so a long-lived read
  cursor can no longer block a write. The `createPool` host is
  instantiated on the main thread (the pool's workers are therefore not
  nested workers — widest browser support, one IPC hop).
- **`coi-serviceworker.js`** is now shipped with the package (built and
  minified from the native web source) and placed at the example web
  root by `scripts/sqlite/sync_sqlite_lib.(ps1|sh)`. It makes a page
  cross-origin isolated without server header config — see *Web Setup*
  in the README.

### Fixed

- **Web: `BEGIN TRANSACTION failed: [SQLITE_BUSY] Cannot write while a
  read statement is open on this worker; finalize first`.** Every web DB
  operation previously ran through a single Web Worker (one SQLite
  connection), so a background read holding a cursor open (e.g. ApiQueue
  session resolution) made a concurrent `BEGIN` (e.g. the login
  migrator) fail with `SQLITE_BUSY`. Reads and writes now use separate
  pooled connections, so the collision is structurally impossible.
  Writes additionally hold the EXCLUSIVE cross-handle fence while
  read-only statements (including read-your-writes SELECTs on the writer
  connection) hold SHARED — decided by the newly exposed native
  `sqlite3_stmt_readonly` — so there is no torn-page / autocheckpoint
  window either.

### Changed

- **Web now requires cross-origin isolation** (`crossOriginIsolated ===
  true`) to get the concurrent pool, because `SharedArrayBuffer` is only
  available in that context. Serve the document with
  `Cross-Origin-Opener-Policy: same-origin` +
  `Cross-Origin-Embedder-Policy: require-corp`, or use the bundled
  `coi-serviceworker.js`. When the page is **not** cross-origin isolated
  the plugin logs the reason (channel `dbas_sqlite.lifecycle`) and falls
  back to the legacy single-worker connection — the app keeps running
  but loses read/write concurrency (and the write-while-read limitation
  returns). No public API changed.
- Requires the matching rebuilt native web bundle (`dbas_sqlite.js` +
  `dbas_sqlite_worker.js`) in `web/libs/`: it adds the `createPool`
  `dbName` main-thread-host option and the `GetStmtReadonly` export. Run
  `scripts/sqlite/sync_sqlite_lib.(ps1|sh)` to refresh the vendored
  bundle and drop `coi-serviceworker.js` at the example web root.

## 2.7.5 - 2026-05-23

### Fixed

- **Web: `databaseExists` was a creating probe, breaking native
  parity** — the implementation routed through the worker
  (`DbasSqliteWebPool.create()` → `pool.send('exists')`), which forced
  an `init` round-trip. `init` calls the WASM lib's
  `initPersistentFS`, which both opens the SQLite DB (create-or-open)
  and walks `openOpfsHandles` calling `opfsDir.getFileHandle(name,
  {create: true})` for the four SQLite files (`name.db`, `-journal`,
  `-wal`, `-shm`). Net effect: every `databaseExists` invocation
  materialised the file in OPFS, and the very next `exists` action
  returned `true`. Native FFI's `databaseExists` is a no-side-effect
  `File(path).existsSync()` — calling it on a non-existent file
  leaves it non-existent. The web behaviour broke any consumer that
  used `databaseExists` as a "first-time bootstrap?" gate, e.g.
  `SessionLifecycle._defaultSessionWriter` upserting a row before the
  migrator created the schema. Symptom seen in consumers: "no such
  table: dbas_Session" on first-ever login.

### Changed

- **Web: `databaseExists` now probes OPFS directly from Dart** via
  `navigator.storage.getDirectory().getDirectoryHandle("dbas_data",
  {create: false}).getFileHandle("<dbName>", {create: false})`. The
  WASM lib is not involved, no worker is spun up, no file is created
  — matching native FFI's "is the file on disk?" semantics 1:1. A
  live `_pool` short-circuits to `true` (file is loaded by
  definition) so the hot path stays cheap.

## 2.7.4 - 2026-05-23

### Fixed

- **Web: `executeSqlStepFailed [SQLITE_BIND_RANGE]` when a named bind
  isn't present in the prepared SQL** — `DbasSqliteStatement.bindNameParameters`
  documents that missing named params are silently skipped to match
  `Microsoft.Data.Sqlite`, and `_replayBinds` implements that skip per
  rc on every native FFI bind. On web the contract was broken because
  the shim's `bindName*` methods buffered Dart-side and always returned
  `sqliteOk`; the real bind happened later in `readRowAndCache` via one
  batched `bindParams` call against the worker. The WASM `bindParams`
  is all-or-nothing, so a single missing named slot threw
  `SQLITE_RANGE` for the entire batch and surfaced as
  `executeSqlStepFailed` instead of being skipped. Consumers whose
  query builder emits a named param that doesn't appear in the SQL
  (e.g. a recursive-join column auto-added by a higher-level ORM) hit
  the failure on every read; downstream the failing read could cascade
  into "no such table" errors when a migration ledger probe couldn't
  complete and the schema wasn't created.

### Changed

- **Web: per-call bind round-trips, eager rc** — `DbasSqliteNativeWeb`'s
  positional and named `bind*` methods now each make ONE worker
  round-trip via the new `DbasSqliteWebPool.bindParam` (singular)
  action and return the SQLite rc the worker reported, exactly mirroring
  native FFI's per-call `sqlite3_bind_*` semantics. The statement
  layer's `_replayBinds` therefore sees the same per-bind rcs on both
  platforms (including `SQLITE_RANGE` on missing named params, which it
  silently skips or throws based on `throwOnMissingNamedParams`). The
  Dart-side bind buffer in `_WebStmtState` (`setPositional` / `setNamed`
  / `mergedParams` / `bindsFlushed`) and the buffered flush block at
  the top of `readRowAndCache` are gone — the binds are already on the
  worker by the time the first row is fetched.
- **Web: `DbasSqliteWebPool.bindParam` (singular) added** — wraps the
  worker's `bindParam` action so the platform shim can bind one slot
  at a time and surface per-call rcs.

## 2.7.3 - 2026-05-23

### Fixed

- **Web: `StateError: Pool is closed for "<dbName>"` after a probe call**
  — `DbasSqliteNativeWeb.databaseExists` / `attachDb` / `attachStreamDb` /
  `getContent` / `dropDb` all called `DbasSqliteWebPool.create()` for a
  supposedly throwaway pool and then `pool.close()`d it. `create()` is a
  get-or-create against a process-global `_pools` map keyed by `dbName`,
  so when a long-lived pool was already running for that DB, every probe
  returned that live pool — and the trailing `close()` tore it down.
  Subsequent `prepareQuery` / `executeSql` against the same `DbasSqlite`
  instance then blew up because `DbasSqlite.openDb` is now idempotent
  (skips when `isOpened()` reports true) and the platform shim's stale
  `_dbOpened` flag was still `true` even though the underlying pool was
  dead. Symptom seen in consumers: a `selectFirst` / `executeReader`
  shortly after any caller that exercised one of those five probes
  threw `DbasSqliteException(executeReaderPrepareFailed)` wrapping
  `StateError: Pool is closed for "<dbName>"`.

### Changed

- **Web: `DbasSqliteNativeWeb.isOpened` now derives from the underlying
  pool's liveness** (`_pool != null && !_pool.isClosed`) instead of a
  separately-maintained `_dbOpened` flag. Single source of truth means
  the shim cannot lie about open-state after a probe-side close, so the
  idempotent `DbasSqlite.openDb()` contract stays honest. The probe
  methods that previously closed a shared pool by mistake now reuse the
  live pool (read-only probes: `databaseExists`) or fully tear down via
  a new `_teardownLivePool()` helper before running against a transient
  pool (destructive probes: `attachDb` / `attachStreamDb` / `getContent`
  / `dropDb`). `closeDb` / `closePool` share the same teardown helper so
  state-reset is centralised.
- **Web: `DbasSqliteWebPool.isClosed` getter added** so the platform
  shim can detect externally-torn-down pools and trigger a fresh
  `create` on the next operation.
- **Web: `_ensurePool` now clears `_stmts` when overwriting a
  stale-closed pool**, symmetrically with `_teardownLivePool`. Without
  this, cached prepared-statement handles bound to the dead worker's
  WASM heap would leak into the fresh worker and be rejected with
  `UNKNOWN_HANDLE` on next use.
- **Web: `_withTempPool` finally-block now preserves the original
  error.** If the action throws and the cleanup `pool.close()` also
  throws, the close failure is logged via `dart:developer` instead of
  masking the root cause.
- **Web: `databaseExists` retries via a transient pool if the live
  pool is closed mid-probe**, so callers never see a raw `StateError`
  bubble out of the platform shim from a concurrent teardown race.
- **Tests: regression integration test added** to
  `example/integration_test/dbas_sqlite_web_test.dart` (`databaseExists
  on a live pool does not tear it down`) covering the exact pre-fix
  symptom.

## 2.7.2 - 2026-05-22

### Fixed

- **Windows integration-test build (MSB3073 on Flutter 3.44)** — the C++
  unit-test target's `gtest_discover_tests` was running at POST_BUILD,
  invoking `dbas_sqlite_test.exe` before its DLL search path was set up
  and exiting 1. Switched to `DISCOVERY_MODE PRE_TEST` so discovery
  defers to `ctest` time; `flutter drive` / `flutter build windows` no
  longer trip the discovery step at all. Matches the current Flutter
  plugin template.
- **`example/ios/Runner.xcodeproj/project.pbxproj` simulator slice
  typo** — header search paths referenced
  `ios-arm64_x86_x64-simulator` (extra `x`); the actual xcframework
  slice is `ios-arm64_x86_64-simulator`. Fixed in 3 build configs (6
  occurrences total).
- **Lint: `prefer_initializing_formals`** in
  `lib/src/dbas_sqlite_reader.dart` — the `DbasSqliteReader.internal`
  constructor now uses `required this._conn` / `_handle` / `_platform`
  / `_onClose` instead of an init list.

### Changed

- **README title** — renamed from `DBAS.SQLite.Flutter` to
  `dbas_sqlite` to match the pub package and GitHub repo. The 2.7.1
  note about "keeping the old display name as human-facing branding"
  is superseded by this change; a one-line "previously published as
  `dbas_sqlite_flutter` …" pointer is added in its place for
  long-tail upgraders.
- **Defensive xcframework slice-name fix in
  `scripts/sqlite/sync_sqlite_lib.{sh,ps1}`** — after copying the
  upstream `dbas_sqlite.xcframework` into `ios/dbas_sqlite/` and
  `macos/dbas_sqlite/`, the scripts now rename any slice directory
  containing `_x86_x64` to `_x86_64`. Today's upstream ships the
  correct name, so the loop is a no-op; the fix prevents a future
  upstream typo from breaking podspec / SPM `.binaryTarget` /
  header-search paths.
- **Stale name cleanup** — three remaining references to the old
  `DBAS.SQLite.Flutter` / `dbas_sqlite_flutter` names that don't
  affect any consumer-visible surface:
  - `.github/CODEOWNERS` header comment.
  - `.idea/DBAS.SQLite.Flutter.iml` → `.idea/dbas_sqlite.iml`,
    `.idea/modules.xml` updated to match.
  - `example/ios/Runner.xcodeproj/project.pbxproj` —
    `dbas_sqlite_flutter.framework` `PBXFileReference` and its
    `Frameworks` group child removed (pre-2.0 pub name, no longer
    produced), plus 3
    `${PODS_CONFIGURATION_BUILD_DIR}/dbas_sqlite_flutter/...` and 3
    `${PODS_CONFIGURATION_BUILD_DIR}/integration_test/...` header
    search paths removed (post pod-deintegrate dead refs). The
    active `dbas_sqlite.xcframework` entries already supersede them.

  Historical `CHANGELOG` entries, `README` body content describing
  prior names, and the `.claude/skills/dbas-sqlite-flutter/` skill
  descriptor are left unchanged.

## 2.7.1 - 2026-05-22

### Added

- **Swift Package Manager manifests** — `ios/dbas_sqlite/Package.swift`
  and `macos/dbas_sqlite/Package.swift`, completing the SPM scaffolding
  shipped in 2.7.0. Both declare a `FlutterFramework` package
  dependency and a `.binaryTarget` pointing at the in-tree
  `dbas_sqlite.xcframework`; the `-all_load` linker flag preserves the
  static-xcframework workaround previously provided by the example
  app's `Podfile` post_install.

  Plan in `.plans/spm-followup.md` was overridden — Flutter
  [#186934](https://github.com/flutter/flutter/pull/186934) is still
  open upstream. The plugin-identity mismatch the PR fixes is
  side-stepped here by renaming the repo and source root to
  `dbas_sqlite` (matching the declared `Package(name:)`). Local
  development and direct git consumers build cleanly; pub.dev
  consumers whose pub-cache extraction directory carries a
  `dbas_sqlite-<version>` suffix may still hit the
  `unable to override package` error until the upstream fix lands.

### Changed

- **Minimum Flutter / Dart** — `environment.flutter` bumped to
  `>=3.44.0` and `environment.sdk` to `^3.12.0`. CI's pinned
  `flutter-version` follows.
- **Example app migrated to SPM-only** — `pod deintegrate` ran for
  both `example/ios` and `example/macos`; `Podfile`, `Podfile.lock`,
  the `Pods` reference in each `Runner.xcworkspace`, and the
  `Pods/.../Pods-Runner.{debug,release}.xcconfig` includes in the
  `Flutter/*.xcconfig` files are gone. The post_install
  `-force_load` workaround now lives in `Package.swift`'s
  `linkerSettings`. CocoaPods consumers of the plugin itself are
  unaffected — both podspecs still pass `pod lib lint`.
- **Repository rename follow-up** — `homepage:` in both pubspecs,
  the security-advisory URL in `SECURITY.md`, and the GitHub App
  token's `repositories:` field in the release workflow all
  switched from `DBAS.SQLite.Flutter` to `dbas_sqlite`. README
  title and Claude skill descriptor still carry the old display
  name (kept intentionally — those are human-facing branding, not
  GitHub-API surface).
- Refreshed `example/pubspec.lock` (transitive `meta`, `test_api`
  bumps Flutter 3.44.0 allows) and the Flutter-generated SPM
  integration entries in `example/{ios,macos}/Runner.xcodeproj`.

## 2.7.0 - 2026-05-22

### Added

- **`DbasSqliteException`** — single exception type thrown by the
  public API of `DbasSqlite`, `DbasSqliteStatement`, and
  `DbasSqliteReader`. Fields:
  - `DbasSqliteErrorCode code` — stable per-throw-site identifier
    (40+ values, 1:1 with throw sites; useful for telemetry IDs and
    test assertions).
  - `int? sqliteCode` — SQLite **primary** result code (e.g. `19` for
    `SQLITE_CONSTRAINT`, `5` for `SQLITE_BUSY`). `null` for `.dart`
    factory throws.
  - `int? sqliteUniqueCode` — SQLite **extended** result code (e.g.
    `2067` for `SQLITE_CONSTRAINT_UNIQUE`, `787` for
    `SQLITE_CONSTRAINT_FOREIGNKEY`). `null` when the platform didn't
    queue an extended rc or for `.dart` factory throws.
  - `String message` — human-readable description.
  - `Object? cause` + `StackTrace? causeStackTrace` — non-null when
    this exception wraps an underlying failure (the
    rollback-after-failed-transaction path and the rollback's own
    catch branch).

  Factories:
  - `DbasSqliteException.dart(code, message, {cause, causeStackTrace})`
    — Dart-side condition (closed DB, format/range errors, timeouts,
    queue cancellations). Both rcs are `null`.
  - `DbasSqliteException.sqlite(code, message, {required int sqliteCode,
    int? sqliteUniqueCode, cause, causeStackTrace})` — native SQLite
    failure.

  Two derived enums help consumers branch:
  - **`DbasSqliteErrorCategory`** (coarse) — `notOpened`,
    `busyOrCancelled`, `prepareFailed`, `executeFailed`,
    `bindFailed`, `transactionFailed`, `readerStateFailed`,
    `decodeFailed`, `internal`. Available as `code.category` or
    `exception.category`.
  - **`DbasSqliteSubCategory`** (fine, SQLite-aware) — derived from
    `sqliteUniqueCode ?? sqliteCode`, so extended codes win over their
    primary counterparts: `databaseBusy` (SQLITE_BUSY=5),
    `tableLocked` (SQLITE_LOCKED=6),
    `duplicatedData` (SQLITE_CONSTRAINT_UNIQUE=2067, `_PRIMARYKEY`=1555,
    `_ROWID`=2579 — covers UNIQUE column constraints, UNIQUE
    indexes, and PRIMARY KEY duplicates), `foreignKeyViolation` (787),
    `notNullViolation` (1299), `checkViolation` (275),
    `corruptDatabase`, `diskFull`, `readOnlyDatabase`,
    `valueTooLarge`, `rangeError`, and ~20 more. Available as
    `exception.subCategory`.

  Both codes flow end-to-end on both platforms:
  - **Native** — the bundled C lib's `GetExtendedErrorCode` FFI entry
    point feeds the platform's `getUniqueErrorCode`; the primary is
    derived as `extended & 0xFF` via `getErrorCode`.
  - **Web** — the worker's `postErr` envelope carries `rc` /
    `extendedRc`; `DbasSqliteWebPool` constructs an internal
    `DbasSqliteWebWorkerError` from them, and the web shim caches
    them in fields read by `getErrorCode` / `getUniqueErrorCode`.

- **`DbasSqliteStatement.getLastErrorCode()` and
  `getLastUniqueErrorCode()`** — int-valued accessors parallel to the
  existing `getLastError()` string accessor. Populated by both
  `executeSql` (from the thrown exception's codes) and `executeReader`
  (from the connection's error state at reader-close time). Useful
  for callers that route exceptions through a generic handler and
  later inspect the statement for telemetry without rethrowing.

- **`DbasSqlite.openDb()` is now idempotent.** A second call on an
  already-open instance is a no-op. Calling with a different
  `readerPoolSize` throws `DbasSqliteException` with code
  `openDbReopenWithDifferentPoolSize` — pool resizing isn't
  supported; close the database first.

### Changed (breaking)

- Every previously-exposed `StateError`, `Exception`,
  `TimeoutException`, `FormatException`, `ArgumentError`, and
  `UnsupportedError` thrown by `DbasSqlite`, `DbasSqliteStatement`,
  and `DbasSqliteReader` is now a `DbasSqliteException`. Code that
  caught a specific type (e.g. `on TimeoutException catch`,
  `on FormatException catch`) will no longer match — catch
  `DbasSqliteException` (or any supertype like `Exception`) and
  branch on `e.code`, `e.category`, or `e.subCategory`.

  - `getColumnDecimal` / `getColumnTime` previously threw
    `FormatException`; now `DbasSqliteException` with
    `invalidDecimalFormat` / `invalidTimeFormat` /
    `invalidTimeComponent`.
  - `getColumnEnum` previously threw `ArgumentError`; now
    `invalidEnumIndex`.
  - The two `bindXxx` paths that hit an unsupported type previously
    threw `UnsupportedError`; now `unsupportedPositionalBindType`
    / `unsupportedNamedBindType`.
  - The pool-saturated reader-acquire previously threw
    `TimeoutException`; now `readerSlotWaitTimeout` (Dart-side
    semaphore wait) or `executeReaderPoolAcquireTimeout` (C-side
    pool wait).
  - All "database is not opened" / "statement is closed" guards
    previously threw `StateError`; now various `…DatabaseNotOpened`
    and `statementClosed` codes.

### Fixed

- **`closeDb()` no longer aborts teardown when `rollback()` fails.**
  Previously a failed in-flight ROLLBACK skipped statement cleanup,
  queue cancellation, and pool close, leaving the cache and OS
  resources dangling. The rollback failure is now logged via
  `dart:developer` and teardown continues.

- **`rollback()`, `commit()`, and `transaction()` preserve the
  underlying error.** When ROLLBACK fails (or when both
  `action`/`commit` and the subsequent rollback fail), the inner
  exception is now attached as `DbasSqliteException.cause` with its
  stack trace on `causeStackTrace`. When the inner failure is itself
  a `DbasSqliteException`, both its `sqliteCode` and
  `sqliteUniqueCode` are lifted onto the outer exception so
  programmatic recovery on `subCategory` keeps working across the
  wrap. `commit()` now mirrors `transaction()`'s behaviour: if the
  implicit rollback after a commit failure also fails, the rollback
  error is logged and the original COMMIT exception is rethrown
  (previously the rollback error masked the commit error).

## 2.6.0 - 2026-05-07

### Added

- **`DbasSqliteReader.readRows([int amount = 50])`** — batch row reader
  that advances up to `amount` rows in a single call and returns a
  record `({List<Map<String, ColumnData>> rows, bool hasMore})`. Each
  row is a column-name → `ColumnData` map, preserving the SQLite
  type, raw value, and null flag for downstream typed access. The
  `hasMore` flag carries the boolean result of the last `readRow`
  call, so callers can drive paginated reads without an extra step
  to probe for end-of-set:

  ```dart
  final reader = await stmt.executeReader();
  while (true) {
    final (:rows, :hasMore) = await reader.readRows();
    for (final row in rows) {
      final col = row['name']!;
      // col.value, col.isNull, SqliteColumnType.fromInt(col.type)
    }
    if (!hasMore) break;
  }
  ```

  Returns an empty list with `hasMore: false` immediately when
  `amount <= 0`. Pure Dart wrapper over `readRow` — no native
  interface, platform, or stub changes. Snapshots each row from the
  per-reader `RowData` cache before the next step overwrites it, so
  intermediate rows are preserved even though the cache itself is
  not retained.

- **`ColumnData` exported from the public barrel** (`lib/dbas_sqlite.dart`)
  so consumers of `readRows` can reference the row-cell type
  directly. Previously internal-only.

## 2.5.3 - 2026-05-07

### Fixed

- **CI: pub.dev publish job triggered Node.js 20 deprecation warning.**
  The reusable workflow `dart-lang/setup-dart/.github/workflows/publish.yml@v1`
  internally pinned an older `setup-dart` SHA still running on Node.js 20,
  which GitHub will force off on June 2, 2026. Pinned the reusable
  workflow past the `@v1` tag to commit `cb71272` (2026-04-01), which
  bumps the inner pin to `setup-dart` v1.7.2 (Node.js 24). No release
  behavior change; clears the deprecation warning and avoids breakage
  when Node.js 20 is removed from runners.

## 2.5.2 - 2026-05-07

### Fixed

- **Windows / Linux / macOS build broke for consumers of the published
  package.** The platform `CMakeLists.txt` files had a `POST_BUILD`
  `copy_if_different` step pointing at `../native_libs/sqlite/<os>/.../dbas_sqlite.<ext>`,
  but `native_libs/` is excluded from the published tarball by
  `.pubignore` (it is the local staging tree that duplicates the
  platform-folder binaries). The copy therefore failed at consumer
  build time with `MSB3073` on Windows and equivalent CMake errors on
  Linux/macOS. Repointed the source path to the platform-folder copy
  that is actually shipped (`<platform>/libs/...`), which was already
  the value used by `dbas_sqlite_bundled_libraries`.

## 2.5.1 - 2026-05-07

### Fixed

- **Worker-pool / reader-pool deadlock under fan-out parallel reads.**
  A `Future.wait` of N `executeReader` calls (where N exceeded the
  reader-pool size) could deadlock the entire pool until the 30 s
  C-side timeout fired. Each `executeReader` dispatched
  `pool_acquire_reader_blocking` to a worker isolate; once every
  worker was parked inside the C blocking acquire, no worker remained
  to process `prepareQuery` / `finalizeStmt` for the in-flight reads,
  so no read could finish, no reader could be released, and every
  acquire timed out together. Reproduces with the default
  `readerPoolSize: 4` and any caller that fans out 6+ pre-write reads
  in parallel (e.g. an FK-graph dependency walker).

  Fix: gate entry to `poolAcquireReaderBlocking` through a Dart-level
  FIFO semaphore sized to the reader pool. Excess callers wait in
  Dart microtasks instead of occupying a worker isolate, so at least
  two workers (the auto-bumped `readerPoolSize + 2` headroom) remain
  free for the non-blocking read steps. Once a reader is released,
  the C handle is returned to the C pool BEFORE the Dart slot is
  signalled — so the next semaphore-granted caller's C-side acquire
  finds a free reader immediately. The C-side timeout becomes a
  safety net rather than the primary contention bound.

  No public API change; behaviour is automatic. Single-connection
  mode (`readerPoolSize: 0`) is unaffected — it goes through the
  writer lock, not the pool.

- **pub.dev Web platform-support and WASM compatibility scoring.**
  The public API chain (`dbas_sqlite.dart` → `DbasSqliteStatement` →
  `DbasSqliteReader` → `DbasSqlitePlatform` →
  `DbasSqliteNativeInterface`) was unconditionally importing
  `package:path_provider/path_provider.dart`, `dart:io`, and
  `package:flutter/services.dart` even though the call sites were
  already runtime-gated by `kIsWeb`. pub.dev's static analyser walks
  every unconditional import, so the web build graph reached
  `path_provider` (which doesn't declare Web support) and
  `dart:io` (incompatible with WASM), costing both Platform-support
  points and the WASM badge.

  Fix: the path-resolving and test-detection helpers move behind
  conditional-import selectors in `lib/src/helpers/paths/` and
  `lib/src/helpers/test_mode/`; FFI-only routines
  (`getLibraryPath`, `_resolveTestBaseDir`) move from the abstract
  `DbasSqliteNativeInterface` down into `DbasSqliteNativeAppBase`
  (FFI-only, never loaded on web); the dead-code
  `prepareLibIfNeeded` is removed entirely. The web build graph no
  longer reaches `path_provider` or `dart:io`.

  No public API change.

## 2.5.0 - 2026-05-06

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
  `executeScalar` route through a pool reader (native) or the writer
  worker (web) until the first `executeSql` runs in the current
  transaction; after that, subsequent in-tx reads switch to the writer
  connection so they observe the transaction's uncommitted writes
  (read-your-writes). Previously, in-tx reads always used the writer
  connection on native, serialising parallel pre-write validation behind
  the single writer. Now `Future.wait([executeReader, executeReader,
  ...])` issued before any write in a transaction runs concurrently
  against the pool. After any `executeSql`, the routing flips
  automatically; on `commit` / `rollback` it resets. No caller-side flag
  needed.

- **Web in-transaction reads no longer throw.** Previously, calling
  `executeReader` inside a transaction on web threw `UnsupportedError`
  because the bundled JS worker can't return SELECT rows through the
  writer-only `pool.exec` channel. The library now routes web reads
  through the writer worker regardless of transaction state — the web
  pool fronts a single worker holding the writer connection, so SELECTs
  observe in-flight transactional state automatically.

- **Web SELECT path is now streaming.** `executeReader` / `executeScalar`
  on web no longer materialise the entire result set in the worker
  before the first row reaches Dart. The platform layer uses the
  worker bundle's per-statement RPC so reads stream one chunk at a
  time across the worker boundary — matching the native FFI behaviour
  exactly. `executeScalar` over a 10k-row table now issues a single
  `readRow` round-trip instead of fetching all 10k rows.

- **Web platform implementation unified with native.** Web now
  implements the full per-stmt platform interface (`prepareQuery` /
  `bind*` / `readRowAndCache` / `finalizeStmt` / `getStmt*`).
  `DbasSqliteStatement` and `DbasSqliteReader` no longer have any
  `kIsWeb` branches — both platforms run the exact same Dart code
  path; only the platform-delegate implementation differs.

  - On web, `bind*` calls buffer Dart-side and flush via one
    `bindParams` round-trip on the first step, matching the worker's
    batch-bind shape.
  - The first row fetch uses the worker's single-row `readRow` action
    so `executeScalar` issues exactly one row's worth of work and no
    waste; subsequent fetches use the chunked `readRows` action with a
    50-row chunk so a 10k-row scan is ~200 round-trips instead of the
    ~10000 a per-row pipeline would require (worker bundle v4.5.0).
  - Per-stmt counters (`getStmtAffectedRows` / `getStmtLastInsertedId`)
    are eagerly captured on every `SQLITE_DONE` step (covering plain
    DML, `INSERT … RETURNING`, and SELECT readers alike), so the
    synchronous platform getters return correct values without extra
    round-trips at read time.
  - Statements that mix `?N` (positional) and `:name` (named) markers
    are bound via two `bindParams` worker calls (one per shape);
    SQLite's bind slots are independent so the calls accumulate,
    matching native FFI's per-slot bind semantics.

  Internally, the `WebQueryBuffer` / `WebRowStream` shims, the
  `executeStatementWrite` / `executeStatementRead` entry points, and
  the `_executeSqlWeb` / `_executeReaderWeb` branches in
  `DbasSqliteStatement` are all gone. Public API surface is unchanged.

### Fixed

- **Empty SELECT result sets now expose column metadata on web.** The
  pre-2.5.0 web path could only recover column names from row 0, so
  `getColumnCount()` / `getColumnName(i)` returned `0` / `''` for an
  empty result. The streaming path captures column metadata from
  `prepareQuery`, so the metadata is populated before the first
  `readRow()` step regardless of whether any rows match.

- **Large SQLite `INTEGER` values on web round-trip as Dart `int`.**
  Values outside the int32 range (which the worker emits as JS BigInt)
  are now classified as `INTEGER` (type 1) and materialised through JS
  `Number(bigint)` into a Dart `int`, matching `getColumnInt(idx)` on
  native. Previously these would surface as TEXT (type 3) because the
  Dart-side type-detection branch fell through. Values within the
  53-bit Dart-on-web safe integer range are exact; values beyond that
  are truncated, which matches Dart's own `int` precision on web.

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
