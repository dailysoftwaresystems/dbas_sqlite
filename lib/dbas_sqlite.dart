import 'dart:async';
import 'dart:ffi';

import 'package:dbas_sqlite_flutter/src/sqlite_parameter.dart';

import 'src/dbas_sqlite_interface.dart';

class DbasSqlite {
  static DbasSqlite? instance;

  static Future<DbasSqlite> getInstance() async {
    if (DbasSqlite.instance == null) {
      await DbasSqlitePlatform.instance.initialize();
      instance = DbasSqlite();
    }

    return instance as DbasSqlite;
  }

  Future<void> executeSql(String sql, List<Object?> parameters) async {
    await DbasSqlitePlatform.instance.prepareQuery(sql);
  }

  void bindParameters(Pointer<Void> stmt, List<Object?> params) {
    for (int i = 0; i < params.length; i++) {
      final index = i + 1; // SQLite index are based on starting 1
      final value = params[i];

      if (value == null) {
        bindNull(stmt, index);
      } else if (value is int) {
        bindInt(stmt, index, value);
      } else if (value is double) {
        bindDouble(stmt, index, value);
      } else if (value is String) {
        bindText(stmt, index, value);
      } else {
        throw UnsupportedError('Unsupported type to SQLite bind: ${value.runtimeType}');
      }
    }
  }
}
