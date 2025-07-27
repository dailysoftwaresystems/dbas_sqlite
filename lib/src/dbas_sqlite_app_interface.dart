import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import 'dbas_sqlite_db.dart';
import 'dbas_sqlite_platform_interface.dart';

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
  Future<Pointer<DbasSqliteDb>> openDb(String fileName) async {
    final functionPtr = _sqlite!.lookupFunction<
        Pointer<DbasSqliteDb> Function(Pointer<Utf8>),
        Pointer<DbasSqliteDb> Function(Pointer<Utf8>)
    >('OpenDb');

    final sqlC = fileName.toNativeUtf8();
    final resultPtr = functionPtr(sqlC);
    calloc.free(sqlC);

    return resultPtr;
  }

  @override
  Future<int> executeSql(Pointer<DbasSqliteDb> dbPtr, String sql) async {
    final functionPtr = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>)
    >('ExecuteSql');

    final sqlC = sql.toNativeUtf8();
    final result = functionPtr(dbPtr, sqlC);
    calloc.free(sqlC);

    return result;
  }

  @override
  Future<int> prepareQuery(Pointer<DbasSqliteDb> dbPtr, String sql) async {
    final functionPtr = _sqlite!.lookupFunction<
        Int32 Function(Pointer<DbasSqliteDb>, Pointer<Utf8>),
        int Function(Pointer<DbasSqliteDb>, Pointer<Utf8>)
    >('PrepareQuery');

    final sqlC = sql.toNativeUtf8();
    final result = functionPtr(dbPtr, sqlC);
    calloc.free(sqlC);

    return result;
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