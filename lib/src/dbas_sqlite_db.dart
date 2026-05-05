import 'dart:ffi';

/// Lightweight Dart-side handle for an open SQLite connection.
///
/// Pairs a database name with the raw native pointer address so the
/// platform dispatcher can route per-call work to the correct
/// [DbasSqliteNativeInterface] delegate.
class DbasSqliteDb {
  final String name;
  final int ptr;
  DbasSqliteDb(this.name, this.ptr);
}

// ── Opaque FFI structs ──────────────────────────────────────────────
//
// The native header (`dbas_sqlite.h`) explicitly tells consumers to
// treat `SQLiteDb` and `SQLitePool` as opaque and access state through
// accessor functions. The struct layout has changed between versions
// and is expected to keep changing; mirroring the layout in Dart is
// load-bearing for nothing and a source of silent struct-misread bugs
// when the native side adds fields. Using `extends Opaque {}` gives
// us a typed pointer for ABI safety with zero layout assumptions.

final class DbasSqliteDbStruct extends Opaque {}

final class DbasSqlitePoolStruct extends Opaque {}

// ── SQLite return-code constants ────────────────────────────────────

const int sqliteOk = 0;
const int sqliteBusy = 5;
const int sqliteRange = 25;
const int sqliteMisuse = 21;
const int sqliteRow = 100;
const int sqliteDone = 101;

/// Sentinel for an invalid / never-allocated [SQLiteStmtHandle].
///
/// `PrepareQuery` returns this on failure; per-stmt accessors return
/// it via the C lib's stale-handle guard. Callers MUST check against
/// this value before treating a returned handle as live.
const int sqliteInvalidStmtHandle = 0;
