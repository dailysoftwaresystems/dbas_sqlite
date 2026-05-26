import 'dart:js_interop';

import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';

/// JS `Number(value)` — converts BigInt, strings, etc. to a JS Number.
/// Used to safely extract int64 values from the worker that may arrive as
/// a JS BigInt (Emscripten `long long` / SQLite INTEGER outside int32).
@JS('Number')
external JSNumber _jsNumber(JSAny? value);

/// Convert a JS value (Number, BigInt, or null) to a Dart `int`.
/// Routes through JS `Number()` so a BigInt from an Emscripten
/// `long long` return collapses to the 53-bit-safe Dart-on-web int range.
int jsAnyToInt(JSAny? v) {
  if (v == null || v.isUndefinedOrNull) return 0;
  try {
    return _jsNumber(v).toDartDouble.toInt();
  } catch (_) {
    return 0;
  }
}

/// Inspect a raw JS value pulled out of a worker `readRow` row payload and
/// produce a typed [ColumnData]. The classification mirrors what the
/// native FFI `readRowAndCache` produces, so a row looks identical to Dart
/// regardless of platform or which web pool (single-worker or multi-worker
/// reader pool) produced it:
///
///   - `bigint` JS values (SQLite INTEGER outside int32 range) → INTEGER,
///     materialised via JS `Number(bigint)` (exact within 2^53, which is
///     also Dart-on-web's safe `int` range; truncates beyond).
///   - `number` JS values: integral and within the safe int range →
///     INTEGER; otherwise → FLOAT. A SQLite FLOAT whose value happens to be
///     exactly integral collapses to INTEGER here — an unavoidable JS-side
///     loss without an extra getColumnType round-trip.
///   - `string` → TEXT.
///   - `Uint8Array` / `ArrayBuffer` → BLOB.
///   - `null` / `undefined` → NULL.
///
/// This is the single canonical implementation shared by
/// `DbasSqliteWebPool` (single worker) and `DbasSqliteWebReaderPool`
/// (multi-worker createPool client).
ColumnData classifyJsColumnValue(JSAny? raw) {
  if (raw == null || raw.isUndefinedOrNull) {
    return ColumnData(type: 5, isNull: true);
  }
  if (raw.typeofEquals('bigint')) {
    final n = _jsNumber(raw).toDartDouble;
    return ColumnData(type: 1, isNull: false, value: n.toInt());
  }
  if (raw.typeofEquals('number')) {
    final n = (raw as JSNumber).toDartDouble;
    if (n.isFinite &&
        n.truncateToDouble() == n &&
        n.abs() <= 9007199254740992.0 /* 2^53 — Dart-on-web safe int */) {
      return ColumnData(type: 1, isNull: false, value: n.toInt());
    }
    return ColumnData(type: 2, isNull: false, value: n);
  }
  if (raw.typeofEquals('string')) {
    return ColumnData(type: 3, isNull: false, value: (raw as JSString).toDart);
  }
  if (raw.isA<JSUint8Array>()) {
    return ColumnData(
        type: 4, isNull: false, value: (raw as JSUint8Array).toDart);
  }
  if (raw.isA<JSArrayBuffer>()) {
    return ColumnData(
        type: 4,
        isNull: false,
        value: (raw as JSArrayBuffer).toDart.asUint8List());
  }
  // Defensive — the worker only emits the typed forms above. Surface an
  // unexpected type as TEXT rather than NULL so the caller can at least
  // see the value.
  return ColumnData(
      type: 3, isNull: false, value: 'unsupported:${raw.runtimeType}');
}
