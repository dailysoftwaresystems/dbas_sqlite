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
  static DbasSqlite? _instance;
  final DbasSqlitePlatform _platform;
  DbasSqliteDb? _db;

  DbasSqlite._dbasSqlite(this._platform);

  static Future<DbasSqlite> getInstance({String dbName = 'dbas.db'}) async {
    _instance ??= DbasSqlite._dbasSqlite(await DbasSqlitePlatform.getInstance(dbName: dbName));
    return _instance!;
  }

  Future<String> getAppDatabasePath({String? dbName}) async {
    dbName ??= _platform.dbName;

    if (_platform.isTest) {
      String dbPath = path.join(Directory.current.path, 'test', 'db');
      Directory dbDir = Directory(dbPath);
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      return path.join(dbPath, dbName);
    }

    if (kIsWeb) {
      return '/data/$dbName';
    }

    final directory = await getApplicationSupportDirectory();
    final dirPath = '${directory.path}/data/$dbName'.replaceAll('\\', '/');
    await Directory(path.dirname(dirPath)).create(recursive: true);
    return dirPath;
  }

  Future<void> openDb(String fileName) async {
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
    if (prepared == 1) {
      throw Exception(["It was not possible to prepare the query: ${_platform.getLastDbError(_db!)}"]);
    }

    _bindParameters(params);
    _bindNameParameters(nameParams);

    int result = 0;
    if (readRow()) {
      result = _platform.getAffectedRows(_db!);
    }

    _platform.closeReader(_db!);
    return result;
  }

  Future<int> executeReader(String sql, {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before executing SQL commands.');
    }

    int prepared = await _platform.prepareQuery(_db!, sql);
    if (prepared == 1) {
      throw Exception(["It was not possible to prepare the query: ${_platform.getLastDbError(_db!)}"]);
    }

    _bindParameters(params);
    _bindNameParameters(nameParams);

    return 1;
  }

  bool readRow() {
    int result = _platform.readRow(_db!);
    if (result == -1) {
      throw Exception(["It was not possible to run the query: ${_platform.getLastDbError(_db!)}"]);
    }

    return result == 1;
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

    return _platform.getColumnText(_db!, idx);
  }

  int getColumnInt(int idx) {
    return _platform.getColumnInt(_db!, idx);
  }

  Decimal getColumnDecimal(int idx) {
    if (isColumnNull(idx)) {
      return Decimal.zero;
    }
    final doubleValue = _platform.getColumnDouble(_db!, idx);
    return Decimal.parse(doubleValue.toString());
  }

  double getColumnDouble(int idx) {
    return _platform.getColumnDouble(_db!, idx);
  }

  Uint8List getColumnBlob(int idx) {
    return _platform.getColumnBlob(_db!, idx);
  }

  SqliteColumnType getColumnType(int idx) {
    return SqliteColumnType.fromInt( _platform.getColumnType(_db!, idx));
  }

  int getColumnCount() {
    return _platform.getColumnCount(_db!);
  }

  void _bindParameters(List<Object?>? parameters) {
    if (parameters != null && parameters.isNotEmpty) {
      for (int i = 0; i < parameters.length; i++) {
        final index = i + 1; // SQLite index are based on starting 1
        final value = parameters[i];

        if (value == null) {
          _platform.bindNull(_db!, index);
        } else if (value is int) {
          _platform.bindInt(_db!, index, value);
        } else if (value is double) {
          _platform.bindDouble(_db!, index, value);
        } else if (value is Decimal) {
          _platform.bindDouble(_db!, index, value as double);
        } else if (value is String) {
          _platform.bindText(_db!, index, value);
        } else if (value is Uint8List) {
          _platform.bindBlob(_db!, index, value);
        } else {
          throw UnsupportedError('Unsupported type to SQLite bind: ${value.runtimeType}');
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

        if (value == null) {
          _platform.bindNameNull(_db!, paramName);
        } else if (value is int) {
          _platform.bindNameInt(_db!, paramName, value);
        } else if (value is double) {
          _platform.bindNameDouble(_db!, paramName, value);
        } else if (value is Decimal) {
          _platform.bindNameDecimal(_db!, paramName, value);
        } else if (value is String) {
          _platform.bindNameText(_db!, paramName, value);
        } else if (value is Uint8List) {
          _platform.bindNameBlob(_db!, paramName, value);
        } else {
          throw UnsupportedError('Unsupported type to SQLite named bind: ${value.runtimeType}');
        }
      });
    }
  }

  Future<void> closeDb() async {
    await _platform.closeDb(_db!);
    _db = null;
  }
}