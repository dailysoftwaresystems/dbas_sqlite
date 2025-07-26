import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'dbas_sqlite_native_web.dart';

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

  Future<int> executeSql(String sql);
  Future<int> prepareQuery(String sql);

  void bindNull(stmt, index);
  void bindInt(stmt, index);
  void bindDouble(stmt, index);
  void bindText(stmt, index);
  void bindBlob(stmt, index);

  Future<int> readRow();
}

abstract class DbasSqliteApp extends DbasSqlitePlatform {
  static DynamicLibrary? _sqlite;

  @override
  Future<void> initialize() async {
    if (DbasSqliteApp._sqlite == null) {
      await internalInitialize();
    }
  }

  Future<void> internalInitialize();

  @override
  Future<int> executeSql(String sql) {
    return Future.value(0);
  }

  @override
  Future<int> prepareQuery(String sql) {
    return Future.value(0);
  }
}

class DbasSqliteWeb extends DbasSqlitePlatform {
  static DbasSqliteNativeWeb? _sqlite;

  @override
  Future<void> initialize() async {
    if (DbasSqliteWeb._sqlite == null) {
      DbasSqliteWeb._sqlite = DbasSqliteNativeWeb();
      await DbasSqliteWeb._sqlite?.initialize();
    }
  }

  @override
  Future<int> executeSql(String sql) {
    return Future.value(0);
  }

  @override
  Future<int> prepareQuery(String sql) {
    return Future.value(0);
  }
}

class DbasSqliteAndroid extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.open('dbas_sqlite.so'));
  }
}

class DbasSqliteIOS extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.process());
  }
}

class DbasSqliteMacOS extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.process());
  }
}

class DbasSqliteLinux extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.open(path.join(DbasSqlitePlatform.basePath, 'linux', 'dbas_sqlite.so')));
  }
}

class DbasSqliteWindows extends DbasSqliteApp {
  @override
  Future<void> internalInitialize() async {
    DbasSqliteApp._sqlite = await Future.value(DynamicLibrary.open(path.join(DbasSqlitePlatform.basePath, 'windows', 'dbas_sqlite.so')));
  }
}