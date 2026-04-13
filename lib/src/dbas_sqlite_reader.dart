import 'dart:typed_data';

import 'package:dbas_sqlite_flutter/src/dbas_sqlite_column_type.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart'
  if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/stub/dbas_sqlite_db_stub.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_platform.dart';
import 'package:decimal/decimal.dart';

/// An independent reader for a single prepared SELECT statement.
///
/// Each [DbasSqliteReader] owns its own database connection (from the pool or
/// the writer fallback) and prepared statement. Multiple readers can coexist
/// simultaneously on the same [DbasSqlite] instance, enabling parallel reads.
///
/// Use [readRow] to iterate over results and the `getColumn*` methods to
/// retrieve column values. Call [close] when done — or let [readRow] auto-close
/// when there are no more rows.
///
/// ```dart
/// final reader = await db.executeReader('SELECT * FROM users WHERE age > ?', params: [18]);
/// while (await reader.readRow()) {
///   print(reader.getColumnText(0));
/// }
/// await reader.close();
/// ```
class DbasSqliteReader {
  static const _sqliteOk = 0;
  static const _sqliteMisuse = 20;
  static const _sqliteRow = 100;
  static const _sqliteDone = 101;
  static const _sqliteSuccessResults = [_sqliteOk, _sqliteRow, _sqliteDone];

  final DbasSqliteDb _conn;
  final DbasSqlitePlatform _platform;
  final Future<void> Function() _onClose;
  bool _closed = false;

  /// Creates a reader for the given connection.
  ///
  /// This constructor is intended for internal use by [DbasSqlite.executeReader].
  DbasSqliteReader(this._conn, this._platform, this._onClose);

  /// Whether this reader has been closed.
  bool get isClosed => _closed;

  /// Advances to the next row of the current result set.
  ///
  /// Returns `true` if a row is available, `false` when all rows have been
  /// read. The reader is automatically closed when there are no more rows.
  ///
  /// Throws an [Exception] if the query execution fails.
  Future<bool> readRow() async {
    if (_closed) return false;

    int readResult = await _platform.readRow(_conn);
    if (!_sqliteSuccessResults.contains(readResult)) {
      String? error = _platform.getLastDbError(_conn);
      await close();
      if (error == null && readResult == _sqliteMisuse) {
        error = 'Misuse: possibly missing or invalid bind.';
      }
      error ??= 'Unknown error ($readResult).';
      throw Exception("It was not possible to run the query ($readResult): $error");
    }

    bool hasRow = readResult == _sqliteRow;
    if (!hasRow) {
      await close();
    }
    return hasRow;
  }

  /// Returns `true` if the column at [idx] is NULL.
  bool isColumnNull(int idx) {
    return _platform.isNull(_conn, idx);
  }

  /// Returns the value of the column at [idx] as a [String].
  String getColumnText(int idx) {
    return _platform.getColumnText(_conn, idx);
  }

  /// Returns the value of the column at [idx] as a [String],
  /// or `null` if the column is NULL.
  String? getColumnNullableText(int idx) {
    if (isColumnNull(idx)) return null;
    return getColumnText(idx);
  }

  /// Returns the value of the column at [idx] as a [bool].
  ///
  /// Interprets `1` as `true` and any other integer as `false`.
  bool getColumnBool(int idx) {
    return _platform.getColumnInt(_conn, idx) == 1;
  }

  /// Returns the value of the column at [idx] as a [bool],
  /// or `null` if the column is NULL.
  bool? getColumnNullableBool(int idx) {
    if (isColumnNull(idx)) return null;
    return getColumnBool(idx);
  }

  /// Returns the value of the column at [idx] as an [int].
  int getColumnInt(int idx) {
    return _platform.getColumnInt(_conn, idx);
  }

  /// Returns the value of the column at [idx] as an [int],
  /// or `null` if the column is NULL.
  int? getColumnNullableInt(int idx) {
    if (isColumnNull(idx)) return null;
    return getColumnInt(idx);
  }

  /// Returns the value of the column at [idx] as a [Decimal].
  ///
  /// Returns [Decimal.zero] if the column is NULL.
  Decimal getColumnDecimal(int idx) {
    if (isColumnNull(idx)) return Decimal.zero;

    final textValue = _platform.getColumnText(_conn, idx);
    final result = Decimal.tryParse(textValue);
    if (result == null) {
      throw FormatException(
        'getColumnDecimal: cannot parse column $idx value as Decimal: "$textValue"',
      );
    }
    return result;
  }

  /// Returns the value of the column at [idx] as a [Decimal],
  /// or `null` if the column is NULL.
  Decimal? getColumnNullableDecimal(int idx) {
    if (isColumnNull(idx)) return null;
    return getColumnDecimal(idx);
  }

  /// Returns the value of the column at [idx] as a [double].
  double getColumnDouble(int idx) {
    return _platform.getColumnDouble(_conn, idx);
  }

  /// Returns the value of the column at [idx] as a [double],
  /// or `null` if the column is NULL.
  double? getColumnNullableDouble(int idx) {
    if (isColumnNull(idx)) return null;
    return getColumnDouble(idx);
  }

  /// Returns the value of the column at [idx] as a [DateTime].
  ///
  /// The column value must be a string parseable by [DateTime.parse].
  DateTime getColumnDateTime(int idx) {
    final value = _platform.getColumnText(_conn, idx);
    return DateTime.parse(value);
  }

  /// Returns the value of the column at [idx] as a [DateTime],
  /// or `null` if the column is NULL.
  DateTime? getColumnNullableDateTime(int idx) {
    if (isColumnNull(idx)) return null;
    return getColumnDateTime(idx);
  }

  /// Returns the value of the column at [idx] as a [Duration].
  ///
  /// Expects the column value in `HH:MM:SS` or `HH:MM:SS.mmm` format.
  Duration getColumnTime(int idx) {
    final raw = _platform.getColumnText(_conn, idx);
    final parts = raw.split(':');
    if (parts.length < 2) {
      throw FormatException(
        'getColumnTime: column $idx value "$raw" is not in HH:MM or HH:MM:SS[.mmm] format',
      );
    }

    int parsePart(String s, String label) {
      final v = int.tryParse(s);
      if (v == null) {
        throw FormatException(
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

  /// Returns the value of the column at [idx] as a [Duration],
  /// or `null` if the column is NULL.
  Duration? getColumnNullableTime(int idx) {
    if (isColumnNull(idx)) return null;
    return getColumnTime(idx);
  }

  /// Returns the value of the column at [idx] as an enum of type [T].
  ///
  /// The column integer value is used as the index into [values].
  ///
  /// Throws an [ArgumentError] if the integer value is out of range.
  T getColumnEnum<T extends Enum>(int idx, List<T> values) {
    final intValue = _platform.getColumnInt(_conn, idx);
    if (intValue < 0 || intValue >= values.length) {
      throw ArgumentError('No enum value found for index $intValue in ${T.toString()}');
    }
    return values[intValue];
  }

  /// Returns the value of the column at [idx] as an enum of type [T],
  /// or `null` if the column is NULL.
  T? getColumnNullableEnum<T extends Enum>(int idx, List<T> values) {
    if (isColumnNull(idx)) return null;
    return getColumnEnum<T>(idx, values);
  }

  /// Returns the value of the column at [idx] as a [Uint8List] (binary data).
  Uint8List getColumnBlob(int idx) {
    return _platform.getColumnBlob(_conn, idx);
  }

  /// Returns the value of the column at [idx] as a [Uint8List],
  /// or `null` if the column is NULL.
  Uint8List? getColumnNullableBlob(int idx) {
    if (isColumnNull(idx)) return null;
    return getColumnBlob(idx);
  }

  /// Returns the name of the column at [columnIndex] in the current result set.
  String getColumnName(int columnIndex) {
    return _platform.getColumnName(_conn, columnIndex);
  }

  /// Returns the [SqliteColumnType] of the column at [idx].
  SqliteColumnType getColumnType(int idx) {
    return SqliteColumnType.fromInt(_platform.getColumnType(_conn, idx));
  }

  /// Returns the number of columns in the current result set.
  int getColumnCount() {
    return _platform.getColumnCount(_conn);
  }

  /// Returns the typed value of the column at [idx] based on its SQLite type.
  ///
  /// Returns `null` for NULL columns, and the appropriate Dart type for
  /// integer, double, text, and blob columns.
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

  /// Closes this reader, releasing its database connection back to the pool.
  ///
  /// This is called automatically when [readRow] returns `false`, but can
  /// be called manually to release resources early (e.g. when breaking out
  /// of a read loop).
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _platform.closeReader(_conn);
    await _onClose();
  }
}
