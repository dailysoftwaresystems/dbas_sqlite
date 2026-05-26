import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';

/// The live read/write connection surface the web platform shim
/// ([DbasSqliteNativeWeb]) drives for normal database traffic.
///
/// Two implementations back it, chosen at pool-creation time by whether
/// `SharedArrayBuffer` (cross-origin isolation) is available:
///
///   - `DbasSqliteWebReaderPool` — the multi-worker `createPool` client
///     (1 writer + N readers, SAB-coordinated). Reads dispatch to reader
///     connections and writes to the writer connection, so a long-lived
///     read cursor can never block a write the way a single shared
///     connection did. This is the path that fixes the login `SQLITE_BUSY`.
///   - the single-worker fallback (an adapter over `DbasSqliteWebPool`)
///     for browsers without `SharedArrayBuffer`. One connection serves
///     everything — functionally identical to the pre-pool behaviour,
///     including its write-while-read limitation — so the app still runs
///     without COOP/COEP, just without true read/write concurrency.
///
/// Statements are addressed by an opaque [cursor] token (a pool-level
/// cursor id in the multi-worker case, the worker's raw statement handle
/// in the single-worker case). The shim stores it on its per-statement
/// state and echoes it back on every follow-up call; it never inspects it.
///
/// File operations (attach / export / drop / streamCopy) are deliberately
/// NOT on this interface — they need exclusive whole-file access and keep
/// running against a transient single-worker `DbasSqliteWebPool`, exactly
/// as before.
abstract interface class WebLivePool {
  /// Monotonic diagnostic id for lifecycle correlation across instances.
  int get poolId;

  /// True once [close] has been called (or the underlying worker died).
  bool get isClosed;

  /// Run a no-result write / system statement (BEGIN/COMMIT/PRAGMA/DDL)
  /// on the writer connection. Returns `{affectedRows, lastInsertId}`.
  Future<Map<String, dynamic>> exec(String sql);

  /// Eager read for tiny internal probes (`SELECT sqlite_version()`,
  /// `PRAGMA journal_mode`). User-facing SELECTs use the streaming path.
  Future<List<Map<String, dynamic>>> query(String sql);

  /// Prepare a statement and return an opaque [cursor] plus column
  /// metadata captured at prepare time.
  ///
  /// [writer] selects the connection role: `true` pins the writer
  /// connection (parameterized writes, and read-your-writes SELECTs that
  /// must see an open transaction's uncommitted changes); `false` routes
  /// to a reader connection. The single-worker fallback ignores it (one
  /// connection serves both).
  Future<({Object cursor, int columnCount, List<String> columnNames})>
      streamPrepare(bool writer, String sql);

  /// Bind one parameter ([param] is a 1-based positional `int` or a named
  /// placeholder `String`). Completes normally on success; throws a
  /// [DbasSqliteWebWorkerError] carrying the SQLite rc on a non-OK bind
  /// (e.g. `SQLITE_RANGE` for a named param absent from the SQL), so the
  /// statement layer's `_replayBinds` can apply its per-rc skip/throw
  /// policy exactly as on native.
  Future<void> streamBind(Object cursor, Object param, Object? value);

  /// Step [cursor] once. `rc == 100` (ROW) carries one [ColumnData] per
  /// column in prepare order; `rc == 101` (DONE) carries `null` columns.
  Future<({int rc, List<ColumnData>? columns})> streamReadRow(
      Object cursor, List<String> columnNames);

  /// Step [cursor] up to [maxRows] times in one round-trip. `hasMore`
  /// is false once the worker observed DONE.
  Future<({List<List<ColumnData>> rows, bool hasMore})> streamReadRows(
      Object cursor, List<String> columnNames, int maxRows);

  /// `sqlite3_changes()` for [cursor] (valid only after a successful step).
  Future<int> streamAffectedRows(Object cursor);

  /// `sqlite3_last_insert_rowid()` for [cursor] (valid only after a step).
  Future<int> streamLastInsertedId(Object cursor);

  /// Finalize [cursor], releasing the worker statement and its fence.
  /// Idempotent and tolerant of unknown/already-finalized cursors.
  Future<void> streamFinalize(Object cursor);

  /// Tear down the pool (all workers) and release resources.
  Future<void> close();
}
