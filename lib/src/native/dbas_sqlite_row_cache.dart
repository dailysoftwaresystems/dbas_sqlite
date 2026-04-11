// Shared row/column cache model used by both the web pool and the native
// isolate proxy. Pure Dart — no platform-specific imports.

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

/// Cached row data from the last readRow/prepareQuery/executeSql response.
class RowData {
  List<ColumnData>? columns;
  int columnCount = 0;
  List<String> columnNames = [];
  int affectedRows = 0;
  int lastInsertedId = 0;
  String? lastError;

  void updateFromPrepare(Map result) {
    columns = null;
    columnCount = toIntSafe(result['columnCount']);
    columnNames = (result['columnNames'] as List?)?.cast<String>() ?? [];
    lastError = _parseError(result['lastError']);
  }

  void updateFromReadRow(Map result) {
    columnCount = toIntSafe(result['columnCount']);
    affectedRows = toIntSafe(result['affectedRows']);
    lastInsertedId = toIntSafe(result['lastInsertedId']);
    lastError = _parseError(result['lastError']);

    if (result['columns'] is List) {
      columns = (result['columns'] as List)
          .map((c) => ColumnData.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList();
    } else {
      columns = null;
    }
  }

  void updateFromExecuteSql(Map result) {
    affectedRows = toIntSafe(result['affectedRows']);
    lastInsertedId = toIntSafe(result['lastInsertedId']);
    lastError = _parseError(result['lastError']);
  }

  void clear() {
    columns = null;
    columnCount = 0;
    columnNames = [];
    affectedRows = 0;
    lastInsertedId = 0;
    lastError = null;
  }

  static String? _parseError(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    if (str == 'null' || str.isEmpty) return null;
    return str;
  }
}
