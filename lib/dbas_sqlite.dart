import 'dart:async';
import 'dart:ffi';

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

  Future<int> executeSql(String sql, {List<Object?>? parameters}) async {
    int prepared = await DbasSqlitePlatform.instance.prepareQuery(_dbPtr!, sql);
    if (prepared == 1) {
      throw Exception(["It was not possible to prepare the query: ${DbasSqlitePlatform.instance.getLastDbError(_dbPtr!)}"]);
    }

    _bindParameters(parameters);
    readRow();
    return DbasSqlitePlatform.instance.getAffectedRows(_dbPtr!);
  }

  Future<int> executeReader(String sql, {List<Object?>? parameters}) async {
    int prepared = await DbasSqlitePlatform.instance.prepareQuery(_dbPtr!, sql);
    if (prepared == 1) {
      throw Exception(["It was not possible to prepare the query: ${DbasSqlitePlatform.instance.getLastDbError(_dbPtr!)}"]);
    }

    _bindParameters(parameters);

    return 1;
  }

  bool readRow() {
    int result = DbasSqlitePlatform.instance.readRow(_dbPtr!);
    if (result == -1) {
      throw Exception(["It was not possible to run the query: ${DbasSqlitePlatform.instance.getLastDbError(_dbPtr!)}"]);
    }
    return result == 1;
  }

  Future<void> closeDb() async {
    await DbasSqlitePlatform.instance.closeDb(_dbPtr!);
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
        } else {
          throw UnsupportedError('Unsupported type to SQLite bind: ${value.runtimeType}');
        }
      }
    }
  }
}
