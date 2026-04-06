import 'dart:async';
import 'dart:js_interop';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import 'dbas_sqlite_native_interface.dart';

class _ColumnData {
  final int type;
  final bool isNull;
  final dynamic value;

  _ColumnData({required this.type, required this.isNull, this.value});

  factory _ColumnData.fromMap(Map<String, dynamic> map) {
    return _ColumnData(
      type: _toInt(map['type']),
      isNull: map['isNull'] == true,
      value: map['value'],
    );
  }

  static int _toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
}

class _RowData {
  List<_ColumnData>? columns;
  int columnCount = 0;
  List<String> columnNames = [];
  int affectedRows = 0;
  int lastInsertedId = 0;
  String? lastError;

  void updateFromPrepare(Map result) {
    columnCount = _toInt(result['columnCount']);
    columnNames = (result['columnNames'] as List?)?.cast<String>() ?? [];
    lastError = _parseError(result['lastError']);
  }

  void updateFromReadRow(Map result) {
    columnCount = _toInt(result['columnCount']);
    affectedRows = _toInt(result['affectedRows']);
    lastInsertedId = _toInt(result['lastInsertedId']);
    lastError = _parseError(result['lastError']);

    if (result['columns'] is List) {
      columns = (result['columns'] as List)
          .map((c) => _ColumnData.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList();
    } else {
      columns = null;
    }
  }

  void updateFromExecuteSql(Map result) {
    affectedRows = _toInt(result['affectedRows']);
    lastInsertedId = _toInt(result['lastInsertedId']);
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

  static int _toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

  static String? _parseError(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    if (str.startsWith('Unknown error:') || str == 'null') return null;
    return str;
  }
}

class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  web.Worker? _worker;
  bool _initialized = false;

  int _nextRequestId = 0;
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  final _RowData _row = _RowData();
  final List<Map<String, dynamic>> _pendingBinds = [];

  bool _dbOpened = false;
  int? _cachedWriterPtr;

  DbasSqliteNativeWeb(super.dbName);

  static void registerWith(Registrar registrar) {}

  // ── Worker communication ──────────────────────────────────────────────

  Future<dynamic> _send(String method, [Map<String, dynamic>? args]) async {
    final id = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;
    _worker!.postMessage(<String, dynamic>{
      'id': id, 'method': method, 'args': args ?? {},
    }.jsify());
    return completer.future;
  }

  void _onMessage(web.MessageEvent event) {
    final data = (event.data as JSObject).dartify();
    if (data is! Map) return;

    final id = data['id'];
    if (id == null) return;

    final completer = _pendingRequests.remove(id);
    if (completer == null) return;

    if (data.containsKey('error') && data['error'] != null) {
      completer.completeError(Exception(data['error'].toString()));
    } else {
      completer.complete(data['result']);
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    if (_initialized && _worker != null) return;

    try {
      _worker = web.Worker('libs/dbas_sqlite_worker.js'.toJS);
      _worker!.onmessage = ((web.MessageEvent e) => _onMessage(e)).toJS;
      await _send('initialize', {'dbName': dbName});
      _initialized = true;
    } catch (e) {
      throw Exception('Failed to initialize DbasSqliteNativeWeb: $e');
    }
  }

  @override
  Future<int> openDb(String path) async {
    final result = await _send('openDb');
    final dbPtr = _toInt(result);
    _dbOpened = dbPtr != 0;
    return dbPtr;
  }

  @override
  Future<bool> databaseExists(String fileName) async {
    return await _send('databaseExists') == true;
  }

  @override
  bool isOpened(int dbPtr) => _dbOpened;

  @override
  Future<void> closeDb(int dbPtr) async {
    await _send('closeDb', {'dbPtr': dbPtr});
    _dbOpened = false;
    _row.clear();
    _pendingBinds.clear();
  }

  // ── File operations ───────────────────────────────────────────────────

  @override
  Future attachDb(String fileName, List<int> content) async {
    await _send('attachDb', {'content': content});
  }

  @override
  Future attachStreamDb(String fileName, Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    await _send('attachDb', {'content': bytes});
  }

  @override
  Future<List<int>> getContent(String fileName) async {
    final result = await _send('getContent');
    if (result is List) {
      return result.cast<num>().map((e) => e.toInt()).toList();
    }
    return [];
  }

  @override
  Future<void> streamCopyDb(String sourceFileName, String destFileName) async {
    String destName = destFileName;
    if (destFileName.contains('/')) destName = destFileName.split('/').last;
    await _send('streamCopyDb', {'destName': destName});
  }

  @override
  Future dropDb(String fileName) async {
    await _send('dropDb');
  }

  // ── SQL execution ─────────────────────────────────────────────────────

  @override
  Future<int> executeSql(int dbPtr, String sql) async {
    final result = await _send('executeSql', {'dbPtr': dbPtr, 'sql': sql});
    if (result is Map) {
      _row.updateFromExecuteSql(result);
      return _toInt(result['rc']);
    }
    return _toInt(result);
  }

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async {
    final result = await _send('prepareQuery', {'dbPtr': dbPtr, 'sql': sql});
    if (result is Map) {
      _row.updateFromPrepare(result);
      return _toInt(result['rc']);
    }
    return _toInt(result);
  }

  // ── Parameter binding (buffered) ──────────────────────────────────────

  @override
  int bindNull(int dbPtr, int index) {
    _pendingBinds.add({'method': 'bindNull', 'index': index});
    return 0;
  }

  @override
  int bindInt(int dbPtr, int index, int value) {
    _pendingBinds.add({'method': 'bindInt', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindFloat(int dbPtr, int index, double value) {
    _pendingBinds.add({'method': 'bindFloat', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindDouble(int dbPtr, int index, double value) {
    _pendingBinds.add({'method': 'bindDouble', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindText(int dbPtr, int index, String value) {
    _pendingBinds.add({'method': 'bindText', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindBlob(int dbPtr, int index, List<int> value) {
    _pendingBinds.add({'method': 'bindBlob', 'index': index, 'value': value});
    return 0;
  }

  @override
  int bindNameNull(int dbPtr, String name) {
    _pendingBinds.add({'method': 'bindNameNull', 'name': name});
    return 0;
  }

  @override
  int bindNameInt(int dbPtr, String name, int value) {
    _pendingBinds.add({'method': 'bindNameInt', 'name': name, 'value': value});
    return 0;
  }

  @override
  int bindNameFloat(int dbPtr, String name, double value) {
    _pendingBinds.add({'method': 'bindNameFloat', 'name': name, 'value': value});
    return 0;
  }

  @override
  int bindNameDouble(int dbPtr, String name, double value) {
    _pendingBinds.add({'method': 'bindNameDouble', 'name': name, 'value': value});
    return 0;
  }

  @override
  int bindNameText(int dbPtr, String name, String value) {
    _pendingBinds.add({'method': 'bindNameText', 'name': name, 'value': value});
    return 0;
  }

  @override
  int bindNameBlob(int dbPtr, String name, List<int> value) {
    _pendingBinds.add({'method': 'bindNameBlob', 'name': name, 'value': value});
    return 0;
  }

  // ── Row reading (flushes buffered binds, caches row) ──────────────────

  @override
  Future<int> readRow(int dbPtr) async {
    final args = <String, dynamic>{'dbPtr': dbPtr};
    if (_pendingBinds.isNotEmpty) {
      args['binds'] = List<Map<String, dynamic>>.from(_pendingBinds);
      _pendingBinds.clear();
    }

    final result = await _send('readRow', args);
    if (result is Map) {
      _row.updateFromReadRow(result);
      return _toInt(result['status']);
    }
    return _toInt(result);
  }

  // ── Column accessors (from _row cache) ────────────────────────────────

  @override
  bool isNull(int dbPtr, int colIndex) =>
      _row.columns?[colIndex].isNull ?? true;

  @override
  String getColumnText(int dbPtr, int colIndex) =>
      _row.columns?[colIndex].value?.toString() ?? '';

  @override
  int getColumnInt(int dbPtr, int colIndex) =>
      _toInt(_row.columns?[colIndex].value);

  @override
  double getColumnFloat(int dbPtr, int colIndex) =>
      _toDouble(_row.columns?[colIndex].value);

  @override
  double getColumnDouble(int dbPtr, int colIndex) =>
      _toDouble(_row.columns?[colIndex].value);

  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) {
    final value = _row.columns?[columnIndex].value;
    if (value is List) return value.cast<num>().map((e) => e.toInt()).toList();
    return [];
  }

  @override
  int getColumnBytes(int dbPtr, int columnIndex) =>
      getColumnBlob(dbPtr, columnIndex).length;

  @override
  String getColumnName(int dbPtr, int colIndex) =>
      colIndex < _row.columnNames.length ? _row.columnNames[colIndex] : '';

  @override
  int getColumnType(int dbPtr, int colIndex) =>
      _row.columns?[colIndex].type ?? 5;

  @override
  int getColumnCount(int dbPtr) => _row.columnCount;

  // ── State accessors (from _row cache) ─────────────────────────────────

  @override
  String? getLastDbError(int dbPtr) => _row.lastError;

  @override
  int getAffectedRows(int dbPtr) => _row.affectedRows;

  @override
  int getLastInsertedId(int dbPtr) => _row.lastInsertedId;

  // ── Reader management ─────────────────────────────────────────────────

  @override
  Future closeReader(int dbPtr) async {
    await _send('closeReader', {'dbPtr': dbPtr});
    _row.columns = null;
  }

  // ── Connection Pool ───────────────────────────────────────────────────

  @override
  Future<int> createPool(String path, int readerCount) async {
    final result = await _send('createPool', {'size': readerCount});
    if (result is Map) {
      final poolPtr = _toInt(result['poolPtr']);
      _cachedWriterPtr = _toInt(result['writerPtr']);
      if (poolPtr != 0) _dbOpened = true;
      return poolPtr;
    }
    return 0;
  }

  @override
  int poolGetWriter(int poolPtr) => _cachedWriterPtr ?? 0;

  @override
  int poolAcquireReader(int poolPtr) => 0;

  @override
  void poolReleaseReader(int poolPtr, int readerPtr) {}

  @override
  Future<void> closePool(int poolPtr) async {
    await _send('closePool', {'poolPtr': poolPtr});
    _cachedWriterPtr = null;
    _dbOpened = false;
    _row.clear();
    _pendingBinds.clear();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static int _toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
  static double _toDouble(dynamic v) => v is double ? v : (v is num ? v.toDouble() : 0.0);
}
