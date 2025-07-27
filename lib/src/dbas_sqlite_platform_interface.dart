import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:decimal/decimal.dart';

import 'dbas_sqlite_app_interface.dart';
import 'dbas_sqlite_db.dart';
import 'dbas_sqlite_web_interface.dart';

abstract class DbasSqlitePlatform {
  static DbasSqlitePlatform instance = _getPlatform();

  static DbasSqlitePlatform _getPlatform() {
    if (Platform.isAndroid) return DbasSqliteAndroid();
    if (Platform.isIOS) return DbasSqliteIOS();
    if (Platform.isMacOS) return DbasSqliteMacOS();
    if (Platform.isLinux) return DbasSqliteLinux();
    if (Platform.isWindows) return DbasSqliteWindows();
    if (kIsWeb) return DbasSqliteWeb();
    throw UnsupportedError("Platform not ${Platform.version} found");
  }

  static final basePath = path.join(Directory.current.path, 'native_libs');
  Future<void> initialize();

  Future<Pointer<DbasSqliteDb>> openDb(String fileName);
  Future<int> executeSql(Pointer<DbasSqliteDb> dbPtr, String sql);
  Future<int> prepareQuery(Pointer<DbasSqliteDb> dbPtr, String sql);

  void bindNull(Pointer<DbasSqliteDb> dbPtr, int index);
  void bindInt(Pointer<DbasSqliteDb> dbPtr, int index, int value);
  void bindDouble(Pointer<DbasSqliteDb> dbPtr, int index, double value);
  void bindText(Pointer<DbasSqliteDb> dbPtr, int index, String value);
  void bindBlob(Pointer<DbasSqliteDb> dbPtr, int index, Uint8List value);

  Future<int> readRow(Pointer<DbasSqliteDb> dbPtr);
  String getColumnText(Pointer<DbasSqliteDb> dbPtr, int index);
  int getColumnInt(Pointer<DbasSqliteDb> dbPtr, int index);
  Decimal getColumnDecimal(Pointer<DbasSqliteDb> dbPtr, int index);
  double getColumnDouble(Pointer<DbasSqliteDb> dbPtr, int index);
  int getColumnCount(Pointer<DbasSqliteDb> dbPtr);

  String getLastDbError(Pointer<DbasSqliteDb> dbPtr);

  void closeReader(Pointer<DbasSqliteDb> dbPtr);
  void closeDb(Pointer<DbasSqliteDb> dbPtr);
}