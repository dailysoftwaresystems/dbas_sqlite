import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_platform_interface.dart';
import 'package:decimal/decimal.dart';

class DbasSqlite {
  static DbasSqlite? _instance;
  Pointer<DbasSqliteDb>? _dbPtr;

  static Future<DbasSqlite> getInstance() async {
    if (DbasSqlite._instance == null) {
      await DbasSqlitePlatform.instance.initialize();
      _instance = DbasSqlite();
    }

    return _instance!;
  }

  Future<void> openDb(String fileName) async {
    _dbPtr = await DbasSqlitePlatform.instance.openDb(fileName);
  }

  bool isOpened() {
    return _dbPtr != null;
  }

  Future<int> executeSql(String sql, {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    int prepared = await DbasSqlitePlatform.instance.prepareQuery(_dbPtr!, sql);
    if (prepared == 1) {
      throw Exception(["It was not possible to prepare the query: ${DbasSqlitePlatform.instance.getLastDbError(_dbPtr!)}"]);
    }

    _bindParameters(params);
    _bindNameParameters(nameParams);

    if (readRow()) {
      return DbasSqlitePlatform.instance.getAffectedRows(_dbPtr!);
    } else {
      return 0;
    }
  }

  Future<int> executeReader(String sql, {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    int prepared = await DbasSqlitePlatform.instance.prepareQuery(_dbPtr!, sql);
    if (prepared == 1) {
      throw Exception(["It was not possible to prepare the query: ${DbasSqlitePlatform.instance.getLastDbError(_dbPtr!)}"]);
    }

    _bindParameters(params);
    _bindNameParameters(nameParams);

    return 1;
  }

  bool readRow() {
    int result = DbasSqlitePlatform.instance.readRow(_dbPtr!);
    if (result == -1) {
      throw Exception(["It was not possible to run the query: ${DbasSqlitePlatform.instance.getLastDbError(_dbPtr!)}"]);
    }
    return result == 1;
  }

  void _bindParameters(List<Object?>? parameters) {
    if (parameters != null && parameters.isNotEmpty) {
      for (int i = 0; i < parameters.length; i++) {
        final index = i + 1; // SQLite index are based on starting 1
        final value = parameters[i];

        if (value == null) {
          DbasSqlitePlatform.instance.bindNull(_dbPtr!, index);
        } else if (value is int) {
          DbasSqlitePlatform.instance.bindInt(_dbPtr!, index, value);
        } else if (value is double) {
          DbasSqlitePlatform.instance.bindDouble(_dbPtr!, index, value);
        } else if (value is Decimal) {
          DbasSqlitePlatform.instance.bindDouble(_dbPtr!, index, value as double);
        } else if (value is String) {
          DbasSqlitePlatform.instance.bindText(_dbPtr!, index, value);
        } else if (value is Uint8List) {
          DbasSqlitePlatform.instance.bindBlob(_dbPtr!, index, value);
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
          DbasSqlitePlatform.instance.bindNameNull(_dbPtr!, paramName);
        } else if (value is int) {
          DbasSqlitePlatform.instance.bindNameInt(_dbPtr!, paramName, value);
        } else if (value is double) {
          DbasSqlitePlatform.instance.bindNameDouble(_dbPtr!, paramName, value);
        } else if (value is Decimal) {
          DbasSqlitePlatform.instance.bindNameDecimal(_dbPtr!, paramName, value);
        } else if (value is String) {
          DbasSqlitePlatform.instance.bindNameText(_dbPtr!, paramName, value);
        } else if (value is Uint8List) {
          DbasSqlitePlatform.instance.bindNameBlob(_dbPtr!, paramName, value);
        } else {
          throw UnsupportedError('Unsupported type to SQLite named bind: ${value.runtimeType}');
        }
      });
    }
  }


  Future<void> closeDb() async {
    await DbasSqlitePlatform.instance.closeDb(_dbPtr!);
    _dbPtr = null;
  }
}
