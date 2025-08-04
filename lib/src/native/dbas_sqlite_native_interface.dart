import 'dart:ffi';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_app_selector.dart';
import 'package:dbas_sqlite_flutter/src/native/stub/dbas_sqlite_native_web_stub.dart'
if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_web.dart';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../dbas_sqlite_db.dart';

abstract class DbasSqliteNativeInterface {
  static final DbasSqliteNativeInterface instance = _getPlatform();

  static DbasSqliteNativeInterface _getPlatform() {
    if (kIsWeb) {
      return DbasSqliteNativeWeb();
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return DbasSqliteNativeApp();
    }
    throw UnsupportedError("Platform not supported: ${Platform.operatingSystem}");
  }

  Future<void> initialize();

  Future<void> prepareLibIfNeeded() async {
    if (!Platform.isLinux && !Platform.isWindows && !kIsWeb) {
      return;
    }

    late String libAsset;
    late String libAssetName;
    if (Platform.isWindows) {
      final arch = sizeOf<IntPtr>() == 8 ? 'x64' : 'x86';
      libAssetName = 'dbas_sqlite.dll';
      libAsset = path.join('windows', 'libs', arch, libAssetName);
    } else if (Platform.isLinux) {
      libAssetName = 'dbas_sqlite.so';
      libAsset = path.join('libs', libAssetName);
    } else if (kIsWeb) {
      libAssetName = 'dbas_sqlite.js';
      libAsset = path.join('dbas_sqlite_flutter', 'libs', libAssetName);
    }

    final dir = await getApplicationSupportDirectory();
    final libDir = '${dir.path}/libs';
    if (!await Directory(libDir).exists()) {
      await Directory(libDir).create(recursive: true);
    }

    final libPath = '$libDir/$libAssetName';
    final dllFile = File(libPath);
    if (await dllFile.exists()) {
      await dllFile.delete();
    }

    libAsset = 'packages/dbas_sqlite_flutter/${libAsset.replaceAll('\\', '/')}';
    final buffer = await rootBundle.load(libAsset);
    await dllFile.writeAsBytes(buffer.buffer.asUint8List());
  }

  Future<String> getLibraryPath() async {
    if (Platform.isIOS || Platform.isMacOS) {
      return '';
    }

    if (Platform.isAndroid) {
      return 'dbas_sqlite.so';
    } else if (Platform.isWindows) {
      final dir = await getApplicationSupportDirectory();
      return path.join(dir.path, 'libs', 'dbas_sqlite.dll');
    } else if (Platform.isLinux) {
      final dir = await getApplicationSupportDirectory();
      return path.join(dir.path, 'libs', 'dbas_sqlite.so');
    } else if (kIsWeb) {
      final dir = await getApplicationSupportDirectory();
      return path.join(dir.path, 'libs', 'dbas_sqlite.js');
    } else {
      throw UnsupportedError('Platform ${Platform.operatingSystem} not supported.');
    }
  }

  Pointer<DbasSqliteDbStruct> openDb(Pointer<Utf8> path);
  bool isOpened(Pointer<DbasSqliteDbStruct> dbPtr);

  int executeSql(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);
  int prepareQuery(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> sql);

  void bindNull(Pointer<DbasSqliteDbStruct> dbPtr, int index);
  void bindInt(Pointer<DbasSqliteDbStruct> dbPtr, int index, int value);
  void bindFloat(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);
  void bindDouble(Pointer<DbasSqliteDbStruct> dbPtr, int index, double value);
  void bindText(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Utf8> value);
  void bindBlob(Pointer<DbasSqliteDbStruct> dbPtr, int index, Pointer<Uint8> value);

  void bindNameNull(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name);
  void bindNameInt(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, int value);
  void bindNameFloat(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);
  void bindNameDouble(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, double value);
  void bindNameText(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Utf8> value);
  void bindNameBlob(Pointer<DbasSqliteDbStruct> dbPtr, Pointer<Utf8> name, Pointer<Uint8> value);

  int readRow(Pointer<DbasSqliteDbStruct> dbPtr);
  int isNull(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);

  Pointer<Utf8> getColumnText(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  int getColumnInt(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  double getColumnFloat(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  double getColumnDouble(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  Pointer<Uint8> getColumnBlob(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);
  int getColumnBytes(Pointer<DbasSqliteDbStruct> dbPtr, int columnIndex);
  int getColumnType(Pointer<DbasSqliteDbStruct> dbPtr, int colIndex);
  int getColumnCount(Pointer<DbasSqliteDbStruct> dbPtr);

  Pointer<Utf8> getLastDbError(Pointer<DbasSqliteDbStruct> dbPtr);
  int getAffectedRows(Pointer<DbasSqliteDbStruct> dbPtr);
  int getLastInsertedId(Pointer<DbasSqliteDbStruct> dbPtr);

  void closeReader(Pointer<DbasSqliteDbStruct> dbPtr);
  void closeDb(Pointer<DbasSqliteDbStruct> dbPtr);
}