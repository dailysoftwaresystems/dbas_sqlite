import 'dart:typed_data';

import 'package:dbas_sqlite/src/dbas_sqlite_column_type.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_db.dart'
    if (dart.library.js_interop) 'package:dbas_sqlite/src/stub/dbas_sqlite_db_stub.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_platform.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';
import 'package:dbas_sqlite/src/exceptions/dbas_sqlite_exception.dart';
import 'package:decimal/decimal.dart';

/// An independent reader for a single prepared SELECT statement.
///
/// Each [DbasSqliteReader] is bound to one statement handle on one
/// connection (a pool reader, or the writer if inside a transaction).
/// Multiple readers can coexist simultaneously across different
/// statements.
///
/// Use [readRow] to iterate; the column accessors read from the
/// per-reader [RowData] cache populated on each step. Call [close]
/// when done — or let [readRow] auto-close when there are no more
/// rows.
///
/// ```dart
/// final stmt = await db.prepareQuery('SELECT * FROM users WHERE age > ?');
/// final reader = await stmt.executeReader(params: [18]);
/// while (await reader.readRow()) {
///   print(reader.getColumnText(0));
/// }
/// await reader.close();
/// ```
class DbasSqliteReader {
  final DbasSqliteDb _conn;
  final int _handle;
  final DbasSqlitePlatform _platform;
  final Future<void> Function() _onClose;
  final RowData _rowCache = RowData();

  bool _closed = false;
  Future<void>? _closeFuture;

  /// Internal constructor used by [DbasSqliteStatement.executeReader].
  /// Consumers should not call this directly.
  ///
  /// [initialColumnCount] / [initialColumnNames] populate the per-
  /// reader [RowData] cache with metadata captured at prepare time.
  /// This makes [getColumnCount] / [getColumnName] return correct
  /// values BEFORE the first [readRow] call.
  DbasSqliteReader.internal({
    required DbasSqliteDb conn,
    required int handle,
    required DbasSqlitePlatform platform,
    required Future<void> Function() onClose,
    int initialColumnCount = 0,
    List<String> initialColumnNames = const [],
  })  : _conn = conn,
        _handle = handle,
        _platform = platform,
        _onClose = onClose {
    _rowCache.columnCount = initialColumnCount;
    _rowCache.columnNames = initialColumnNames;
  }

  /// Whether this reader has been closed.
  bool get isClosed => _closed;

  /// Advances to the next row of the current result set.
  ///
  /// Returns `true` if a row is available, `false` when all rows have
  /// been read. The reader is automatically closed when there are no
  /// more rows.
  ///
  /// Throws an [Exception] if the query execution fails.
  Future<bool> readRow() async {
    if (_closed) return false;

    final readResult = await _platform.readRowAndCache(_conn, _handle, _rowCache);
    if (!_isSuccessRc(readResult)) {
      String? error = _platform.getLastStmtError(_conn, _handle);
      await close();
      if (error == null && readResult == sqliteMisuse) {
        error = 'Misuse: possibly missing or invalid bind.';
      }
      error ??= 'Unknown error ($readResult).';
      throw DbasSqliteException(
        DbasSqliteErrorCode.readRowFailed,
        readResult,
        'It was not possible to run the query ($readResult): $error',
      );
    }

    final hasRow = readResult == sqliteRow;
    if (!hasRow) await close();
    return hasRow;
  }

  /// Reads up to [amount] rows by repeatedly calling [readRow],
  /// snapshotting each row as a `Map<String, ColumnData>` keyed by
  /// column name. Each [ColumnData] preserves the SQLite type, the
  /// raw value, and the null flag for the column.
  ///
  /// Returns a record with:
  ///   * `rows`: between 0 and [amount] entries;
  ///   * `hasMore`: the boolean result of the last [readRow] call —
  ///     `true` if [amount] rows were read and more may still follow,
  ///     `false` if the result set was exhausted before reaching
  ///     [amount].
  ///
  /// Returns an empty list with `hasMore: false` immediately when
  /// [amount] is non-positive.
  Future<({List<Map<String, ColumnData>> rows, bool hasMore})> readRows(
      [int amount = 50]) async {
    final rows = <Map<String, ColumnData>>[];
    if (amount <= 0) return (rows: rows, hasMore: false);
    bool hasMore = false;
    for (int i = 0; i < amount; i++) {
      hasMore = await readRow();
      if (!hasMore) break;
      final cols = _rowCache.columns;
      if (cols == null) continue;
      final row = <String, ColumnData>{};
      for (int c = 0; c < cols.length; c++) {
        row[getColumnName(c)] = cols[c];
      }
      rows.add(row);
    }
    return (rows: rows, hasMore: hasMore);
  }

  // sqlite3_step never returns SQLITE_OK per the C contract; the
  // success values are SQLITE_ROW (more rows) and SQLITE_DONE (end of
  // result set). Anything else is an error.
  bool _isSuccessRc(int rc) => rc == sqliteRow || rc == sqliteDone;

  // ── Column accessors ─────────────────────────────────────────────────

  bool isColumnNull(int idx) => _column(idx)?.isNull ?? true;

  String getColumnText(int idx) => _column(idx)?.value?.toString() ?? '';

  String? getColumnNullableText(int idx) =>
      isColumnNull(idx) ? null : getColumnText(idx);

  bool getColumnBool(int idx) => getColumnInt(idx) == 1;
  bool? getColumnNullableBool(int idx) =>
      isColumnNull(idx) ? null : getColumnBool(idx);

  int getColumnInt(int idx) => toIntSafe(_column(idx)?.value);
  int? getColumnNullableInt(int idx) =>
      isColumnNull(idx) ? null : getColumnInt(idx);

  Decimal getColumnDecimal(int idx) {
    if (isColumnNull(idx)) return Decimal.zero;
    final text = _column(idx)?.value?.toString() ?? '';
    final v = Decimal.tryParse(text);
    if (v == null) {
      throw DbasSqliteException(
        DbasSqliteErrorCode.invalidDecimalFormat,
        null,
        'getColumnDecimal: cannot parse column $idx value as Decimal: "$text"',
      );
    }
    return v;
  }

  Decimal? getColumnNullableDecimal(int idx) =>
      isColumnNull(idx) ? null : getColumnDecimal(idx);

  double getColumnDouble(int idx) => toDoubleSafe(_column(idx)?.value);
  double? getColumnNullableDouble(int idx) =>
      isColumnNull(idx) ? null : getColumnDouble(idx);

  DateTime getColumnDateTime(int idx) =>
      DateTime.parse(_column(idx)?.value?.toString() ?? '');

  DateTime? getColumnNullableDateTime(int idx) =>
      isColumnNull(idx) ? null : getColumnDateTime(idx);

  Duration getColumnTime(int idx) {
    final raw = _column(idx)?.value?.toString() ?? '';
    final parts = raw.split(':');
    if (parts.length < 2) {
      throw DbasSqliteException(
        DbasSqliteErrorCode.invalidTimeFormat,
        null,
        'getColumnTime: column $idx value "$raw" is not in HH:MM or HH:MM:SS[.mmm] format',
      );
    }

    int parsePart(String s, String label) {
      final v = int.tryParse(s);
      if (v == null) {
        throw DbasSqliteException(
          DbasSqliteErrorCode.invalidTimeComponent,
          null,
          'getColumnTime: column $idx value "$raw" has invalid $label component "$s"',
        );
      }
      return v;
    }

    final hours = parsePart(parts[0], 'hours');
    final minutes = parsePart(parts[1], 'minutes');

    int seconds = 0;
    int milliseconds = 0;
    if (parts.length > 2) {
      final secParts = parts[2].split('.').where((s) => s.trim().isNotEmpty).toList();
      seconds = parsePart(secParts.first, 'seconds');
      if (secParts.length > 1) {
        milliseconds = parsePart(
          secParts.last.padRight(3, '0').substring(0, 3),
          'milliseconds',
        );
      }
    }

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  Duration? getColumnNullableTime(int idx) =>
      isColumnNull(idx) ? null : getColumnTime(idx);

  T getColumnEnum<T extends Enum>(int idx, List<T> values) {
    final intValue = getColumnInt(idx);
    if (intValue < 0 || intValue >= values.length) {
      throw DbasSqliteException(
        DbasSqliteErrorCode.invalidEnumIndex,
        null,
        'No enum value found for index $intValue in ${T.toString()}',
      );
    }
    return values[intValue];
  }

  T? getColumnNullableEnum<T extends Enum>(int idx, List<T> values) =>
      isColumnNull(idx) ? null : getColumnEnum<T>(idx, values);

  Uint8List getColumnBlob(int idx) {
    final value = _column(idx)?.value;
    if (value is Uint8List) return value;
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return Uint8List(0);
  }

  Uint8List? getColumnNullableBlob(int idx) =>
      isColumnNull(idx) ? null : getColumnBlob(idx);

  String getColumnName(int columnIndex) {
    final names = _columnNames();
    return columnIndex < names.length ? names[columnIndex] : '';
  }

  SqliteColumnType getColumnType(int idx) =>
      SqliteColumnType.fromInt(_column(idx)?.type ?? 5);

  int getColumnCount() => _rowCache.columnCount;

  /// Returns the typed value of the column at [idx] based on its
  /// SQLite type. Returns `null` for NULL columns.
  dynamic getColumnValue(int idx) {
    switch (getColumnType(idx)) {
      case SqliteColumnType.integer:
        return getColumnInt(idx);
      case SqliteColumnType.double:
        return getColumnDouble(idx);
      case SqliteColumnType.blob:
        return getColumnBlob(idx);
      case SqliteColumnType.nullType:
        return null;
      default:
        return getColumnText(idx);
    }
  }

  ColumnData? _column(int idx) {
    final cols = _rowCache.columns;
    if (cols == null || idx >= cols.length) return null;
    return cols[idx];
  }

  List<String> _columnNames() => _rowCache.columnNames;

  // ── Lifecycle ────────────────────────────────────────────────────────

  /// Closes this reader, releasing its connection back to the pool.
  ///
  /// Idempotent — concurrent calls all observe the same completion
  /// future, so a second caller waits for the first call's cleanup
  /// to finish rather than returning instantly while resources are
  /// still mid-tear-down. Auto-called when [readRow] returns `false`.
  ///
  /// The `_closed = true` flag is set synchronously before the first
  /// `await` so the active-reader guard on the parent statement
  /// observes the closing state immediately.
  Future<void> close() {
    return _closeFuture ??= _doClose();
  }

  Future<void> _doClose() async {
    _closed = true;
    await _onClose();
  }
}
