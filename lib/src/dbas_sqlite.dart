import 'dart:io';
import 'dart:async';

import 'package:dbas_sqlite_flutter/src/dbas_sqlite_column_type.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart'
  if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/stub/dbas_sqlite_db_stub.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_platform.dart';
import 'package:decimal/decimal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

class DbasSqlite {
  static final _sqliteOk = 0;
  static final _sqliteRow = 100;
  static final _sqliteDone = 101;
  static final _sqliteSuccessResults = [_sqliteOk, _sqliteRow, _sqliteDone];

  static final String _webDbDir = 'data';
  static final Map<String, DbasSqlite> _instance = {};
  final DbasSqlitePlatform _platform;
  final String dbName;
  DbasSqliteDb? _db;

  DbasSqlite._dbasSqlite(this._platform, this.dbName);

  static Future<DbasSqlite> getInstance({String dbName = 'dbas.db'}) async {
    if (_instance.containsKey(dbName)) {
      return _instance[dbName]!;
    }

    _instance[dbName] = DbasSqlite._dbasSqlite(await DbasSqlitePlatform.getInstance(dbName: dbName), dbName);
    return _instance[dbName]!;
  }

  static Future<String> _getDbPath() async {
    if (kIsWeb) {
      return '/$_webDbDir';
    }

    final directory = await getApplicationSupportDirectory();
    final dirPath = '${directory.path}/data'.replaceAll('\\', '/');
    final dir = Directory(dirPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dirPath;
  }

  Future<bool> databaseExists() async {
    String fileName = kIsWeb ? dbName : await getAppDatabasePath(dbName: dbName);
    return await _platform.databaseExists(fileName);
  }

  /// Attaches a database from bytes and optionally opens it.
  /// If a database with the same name already exists and is opened, it will be closed
  /// and removed before attaching the new database.
  Future<DbasSqlite> attachDb(List<int> bytes, {bool openDb = true}) async {
    if (_instance.containsKey(dbName)) {
      if (_instance[dbName]!.isOpened()) {
        await _instance[dbName]!.closeDb();
      }

      _instance.remove(dbName);
    }

    String fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.attachDb(fileName, bytes);
    final instance = await getInstance(dbName: dbName);

    if (openDb) {
      await instance.openDb();
    }

    return instance;
  }

  Future<List<int>> getContent() async {
    String fileName = await getAppDatabasePath(dbName: dbName);
    return await _platform.getContent(fileName);
  }

  Future dropDb() async {
    String fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.dropDb(fileName);
  }

  Future<String> getAppDatabasePath({String? dbName}) async {
    dbName ??= this.dbName;

    if (_platform.isTest(dbName)) {
      String dbPath = path.join(Directory.current.path, 'test', 'db');
      Directory dbDir = Directory(dbPath);
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      return path.join(dbPath, dbName);
    }

    String dbPath = await _getDbPath();
    return '$dbPath/$dbName';
  }

  Future<void> openDb() async {
    String fileName = await getAppDatabasePath(dbName: dbName);
    _db = await _platform.openDb(fileName);
  }

  bool isOpened() {
    return _db != null && _platform.isOpened(_db!);
  }

  Future<int> executeSql(String sql, {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before executing SQL commands.');
    }

    int prepared = await _platform.prepareQuery(_db!, sql);
    if (prepared == -1 || prepared == 1) {
      String error = _platform.getLastDbError(_db!) ?? 'Unknown error ($prepared).';
      throw Exception(["It was not possible to prepare the query: $error"]);
    }

    _bindParameters(params);
    _bindNameParameters(nameParams);

    int result = 0;
    if (!await readRow()) {
      result = _platform.getAffectedRows(_db!);
    }

    await _platform.closeReader(_db!);
    return result;
  }

  Future<int> executeReader(String sql, {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before executing SQL commands.');
    }

    int prepared = await _platform.prepareQuery(_db!, sql);
    if (prepared == -1 || prepared == 1) {
      final error = _platform.getLastDbError(_db!) ?? 'Unknown error ($prepared).';
      throw Exception(["It was not possible to prepare the query: $error"]);
    }

    _bindParameters(params);
    _bindNameParameters(nameParams);

    return 1;
  }

  Future<bool> readRow() async {
    int result = await _platform.readRow(_db!);
    if (!_sqliteSuccessResults.contains(result)) {
      String? error = _platform.getLastDbError(_db!);
      await _platform.closeReader(_db!);
      if (error == null && result == 20) {
        error = 'Misuse: possibly missing or invalid bind.';
      }
      error ??= 'Unknown error ($result).';
      throw Exception(["It was not possible to run the query ($result): error"]);
    }

    return result == _sqliteRow;
  }

  bool isColumnNull(int idx) {
    return _platform.isNull(_db!, idx);
  }

  String getColumnText(int idx) {
    return _platform.getColumnText(_db!, idx);
  }

  String? getColumnNullableText(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnText(idx);
  }

  bool getColumnBool(int idx) {
    return _platform.getColumnInt(_db!, idx) == 1;
  }

  bool? getColumnNullableBool(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnBool(idx);
  }

  int getColumnInt(int idx) {
    return _platform.getColumnInt(_db!, idx);
  }

  int? getColumnNullableInt(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnInt(idx);
  }

  Decimal getColumnDecimal(int idx) {
    if (isColumnNull(idx)) {
      return Decimal.zero;
    }

    final doubleValue = _platform.getColumnDouble(_db!, idx);
    return Decimal.parse(doubleValue.toString());
  }

  Decimal? getColumnNullableDecimal(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnDecimal(idx);
  }

  double getColumnDouble(int idx) {
    return _platform.getColumnDouble(_db!, idx);
  }

  double? getColumnNullableDouble(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnDouble(idx);
  }

  DateTime getColumnDateTime(int idx) {
    final value = _platform.getColumnText(_db!, idx);
    return DateTime.parse(value);
  }

  DateTime? getColumnNullableDateTime(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnDateTime(idx);
  }

  T getColumnEnum<T extends Enum>(int idx, List<T> values) {
    final intValue = _platform.getColumnInt(_db!, idx);
    if (intValue < 0 || intValue >= values.length) {
      throw ArgumentError('No enum value found for index $intValue in ${T.toString()}');
    }
    return values[intValue];
  }

  T? getColumnNullableEnum<T extends Enum>(int idx, List<T> values) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnEnum<T>(idx, values);
  }

  Uint8List getColumnBlob(int idx) {
    return _platform.getColumnBlob(_db!, idx);
  }

  Uint8List? getColumnNullableBlob(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnBlob(idx);
  }

  String getColumnName(int columnIndex) {
    return _platform.getColumnName(_db!, columnIndex);
  }

  SqliteColumnType getColumnType(int idx) {
    return SqliteColumnType.fromInt( _platform.getColumnType(_db!, idx));
  }

  int getColumnCount() {
    return _platform.getColumnCount(_db!);
  }

  int getLastInsertedId() {
    return _platform.getLastInsertedId(_db!);
  }

  void _bindParameters(List<Object?>? parameters) {
    if (parameters != null && parameters.isNotEmpty) {
      for (int i = 0; i < parameters.length; i++) {
        final index = i + 1; // SQLite index are based on starting 1
        final value = parameters[i];

        int paramResult = -1;
        if (value == null) {
          paramResult = _platform.bindNull(_db!, index);
        } else if (value is int) {
          paramResult = _platform.bindInt(_db!, index, value);
        } else if (value is double) {
          paramResult = _platform.bindDouble(_db!, index, value);
        } else if (value is Decimal) {
          paramResult = _platform.bindDouble(_db!, index, value.toDouble());
        } else if (value is String) {
          paramResult = _platform.bindText(_db!, index, value);
        } else if (value is Uint8List) {
          paramResult = _platform.bindBlob(_db!, index, value);
        } else if (value is Enum) {
          paramResult = _platform.bindInt(_db!, index, value.index);
        } else {
          throw UnsupportedError('Unsupported type to SQLite bind: ${value.runtimeType}');
        }

        if (paramResult == -1 || paramResult == 1) {
          throw Exception(["It was not possible to bind the parameter: ${_platform.getLastDbError(_db!) ?? 'Unknown error ($paramResult)'}}"]);
        }
      }
    }
  }

  void _bindNameParameters(Map<String, Object?>? parameters) {
    if (parameters != null && parameters.isNotEmpty) {
      parameters.forEach((key, value) {
        final paramName = key.startsWith(':') || key.startsWith('@') || key.startsWith(r'$')
            ? key
            : ':$key';

        int paramResult = -1;
        if (value == null) {
          paramResult = _platform.bindNameNull(_db!, paramName);
        } else if (value is int) {
          paramResult = _platform.bindNameInt(_db!, paramName, value);
        } else if (value is double) {
          paramResult = _platform.bindNameDouble(_db!, paramName, value.toDouble());
        } else if (value is Decimal) {
          paramResult = _platform.bindNameDecimal(_db!, paramName, value);
        } else if (value is String) {
          paramResult = _platform.bindNameText(_db!, paramName, value);
        } else if (value is Uint8List) {
          paramResult = _platform.bindNameBlob(_db!, paramName, value);
        } else if (value is Enum) {
          paramResult = _platform.bindNameInt(_db!, paramName, value.index);
        } else {
          throw UnsupportedError('Unsupported type to SQLite named bind: ${value.runtimeType}');
        }

        if (paramResult == -1 || paramResult == 1) {
          throw Exception(["It was not possible to bind the parameter: ${_platform.getLastDbError(_db!) ?? 'Unknown error ($paramResult)'}"]);
        }
      });
    }
  }

  Future<void> closeDb() async {
    if (_instance.containsKey(dbName)) {
      _instance.remove(dbName);
    }
    await _platform.closeDb(_db!);
    _db = null;
  }
}
