// Per-row column cache populated by `readRowAndCache` after each
// successful step of a prepared statement. Owned by `DbasSqliteReader`
// (one cache per active reader).
//
// Pure Dart — no platform-specific imports. The same model is used by
// both the native FFI path and the web pool path.

int toIntSafe(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is BigInt) return v.toInt();
  // JS BigInt may arrive as a string after dartify() in some environments
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double toDoubleSafe(dynamic v) =>
    v is double ? v : (v is num ? v.toDouble() : 0.0);

/// Cached column data for a single column in the current row.
class ColumnData {
  final int type;
  final bool isNull;
  final dynamic value;

  ColumnData({required this.type, required this.isNull, this.value});

  factory ColumnData.fromMap(Map<String, dynamic> map) {
    return ColumnData(
      type: toIntSafe(map['type']),
      isNull: map['isNull'] == true,
      value: map['value'],
    );
  }
}

/// Cached row data for one prepared statement's current step.
///
/// Per-stmt counters (`affectedRows`, `lastInsertedId`) and per-stmt
/// `lastError` are NOT stored here in v2.4.0 — they live on
/// `DbasSqliteStatement`, populated from the C lib's
/// `GetStmtAffectedRows` / `GetStmtLastInsertedId` / `GetLastStmtError`
/// at execute / reader-close time. Keeping them off the row cache
/// avoids confusion about which "affectedRows" is current when
/// multiple concurrent statements are stepping on the same connection.
class RowData {
  List<ColumnData>? columns;
  int columnCount = 0;
  List<String> columnNames = [];

  void updateFromPrepare(Map result) {
    columns = null;
    columnCount = toIntSafe(result['columnCount']);
    columnNames = (result['columnNames'] as List?)?.cast<String>() ?? [];
  }

  void updateFromReadRow(Map result) {
    // Only update columnCount when the worker emitted it. The worker
    // omits this field on error rcs to avoid poisoning the cache with
    // the stale-handle sentinel (-1) returned by sqlite3_column_count
    // on a torn-down statement; on those paths we keep the prepare-
    // time count.
    if (result.containsKey('columnCount') && result['columnCount'] != null) {
      columnCount = toIntSafe(result['columnCount']);
    }
    if (result['columns'] is List) {
      columns = (result['columns'] as List)
          .map((c) => ColumnData.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList();
    } else {
      columns = null;
    }
  }

  void clear() {
    columns = null;
    columnCount = 0;
    columnNames = [];
  }
}
