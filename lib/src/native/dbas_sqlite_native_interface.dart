import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_app_selector.dart';
import 'package:dbas_sqlite_flutter/src/native/stub/dbas_sqlite_native_web_stub.dart'
if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_web.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
      final arch = Platform.version.contains('_x64') ? 'x64' : 'x86';
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

    late String libPath;
    if (Platform.isAndroid) {
      return 'dbas_sqlite.so';
    } else if (Platform.isWindows) {
      libPath = path.join('libs', 'dbas_sqlite.dll');
    } else if (Platform.isLinux) {
      libPath = path.join('libs', 'dbas_sqlite.so');
    } else if (kIsWeb) {
      libPath = path.join('libs', 'dbas_sqlite.js');
    } else {
      throw UnsupportedError('Platform ${Platform.operatingSystem} not supported.');
    }

    final dir = await getApplicationSupportDirectory();
    return path.join(dir.path, libPath).replaceAll('\\', '/');
  }

  int openDb(String path);
  bool isOpened(int dbPtr);

  int executeSql(int dbPtr, String sql);
  int prepareQuery(int dbPtr, String sql);

  void bindNull(int stmt, int index);
  void bindInt(int stmt, int index, int value);
  void bindFloat(int stmt, int index, double value);
  void bindDouble(int stmt, int index, double value);
  void bindText(int stmt, int index, String value);
  void bindBlob(int stmt, int index, List<int> value);

  void bindNameNull(int stmt, String name);
  void bindNameInt(int stmt, String name, int value);
  void bindNameFloat(int stmt, String name, double value);
  void bindNameDouble(int stmt, String name, double value);
  void bindNameText(int stmt, String name, String value);
  void bindNameBlob(int stmt, String name, List<int> value);

  int readRow(int stmt);
  bool isNull(int stmt, int colIndex);

  String getColumnText(int stmt, int colIndex);
  int getColumnInt(int stmt, int colIndex);
  double getColumnFloat(int stmt, int colIndex);
  double getColumnDouble(int stmt, int colIndex);
  List<int> getColumnBlob(int stmt, int columnIndex);
  int getColumnBytes(int stmt, int columnIndex);
  int getColumnType(int stmt, int colIndex);
  int getColumnCount(int stmt);

  String getLastDbError(int dbPtr);
  int getAffectedRows(int dbPtr);
  int getLastInsertedId(int dbPtr);

  void closeReader(int stmt);
  void closeDb(int dbPtr);
}