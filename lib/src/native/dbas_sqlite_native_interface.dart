import 'dart:io';
import 'package:dbas_sqlite_flutter/src/helpers/dbas_sqlite_platform_util.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_app_selector.dart';
import 'package:dbas_sqlite_flutter/src/native/stub/dbas_sqlite_native_web_stub.dart'
if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_web.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

abstract class DbasSqliteNativeInterface {
  static final Map<String, DbasSqliteNativeInterface> _instance = {};
  final String _dbName;

  DbasSqliteNativeInterface(this._dbName);

  static DbasSqliteNativeInterface getInstance({String dbName = 'dbas.db'}) {
    if (_instance.containsKey(dbName)) {
      return _instance[dbName]!;
    }

    _instance[dbName] = _getPlatform(dbName: dbName);
    return _instance[dbName]!;
  }

  static DbasSqliteNativeInterface _getPlatform({String dbName = 'dbas.db'}) {
    if (kIsWeb) {
      return DbasSqliteNativeWeb(dbName);
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return DbasSqliteNativeApp(dbName);
    }
    throw UnsupportedError("Platform not supported: ${Platform.operatingSystem}");
  }

  Future<void> initialize();

  String get dbName => _dbName;

  bool get isTest => DbasSqlitePlatformUtil.isTest();

  Future<void> prepareLibIfNeeded() async {
    // Only web needs to load libraries from assets
    if (!kIsWeb || isTest) {
      return;
    }

    late String libAsset;
    late String libAssetName;
    if (kIsWeb) {
      libAssetName = 'dbas_sqlite.js';
      libAsset = path.join('dbas_sqlite_flutter', 'libs', libAssetName);
    }

    final dir = isTest ? Directory.current : await getApplicationSupportDirectory();
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

  /// Returns the base directory for resolving native library paths in test mode.
  ///
  /// If the current directory contains the platform libs (e.g. `windows/libs/`),
  /// it is used directly. Otherwise, the parent directory is checked, which
  /// handles the case where tests run from the `example/` subdirectory.
  String _resolveTestBaseDir(String platformSubPath) {
    final current = Directory.current.path;
    final candidate = path.join(current, platformSubPath);
    if (File(candidate).existsSync()) {
      return current;
    }

    // Fallback: try parent directory (e.g. running from example/)
    final parent = path.dirname(current);
    return parent;
  }

  Future<String> getLibraryPath() async {
    if (Platform.isIOS || (Platform.isMacOS && !isTest)) {
      return '';
    } else if (Platform.isMacOS) {
      String arch = Platform.version.contains('arm64') || Platform.version.toLowerCase().contains('arm64') ? 'a64' : 'x86';
      final relativePath = path.join('macos', 'libs', arch, 'dbas_sqlite.dylib');
      final baseDir = isTest ? _resolveTestBaseDir(relativePath) : Directory.current.path;
      return path.join(baseDir, relativePath);
    }

    late String libPath;
    if (Platform.isAndroid) {
      return 'dbas_sqlite.so';
    } else if (Platform.isWindows) {
      if (isTest) {
        String arch = Platform.version.contains('_x64') ? 'x64' : 'x86';
        final relativePath = path.join('windows', 'libs', arch, 'dbas_sqlite.dll');
        final baseDir = _resolveTestBaseDir(relativePath);
        libPath = path.join(baseDir, relativePath);
      } else {
        // For production Windows builds, the DLL should be bundled with the app
        libPath = 'dbas_sqlite.dll';
      }
    } else if (Platform.isLinux) {
      if (isTest) {
        final relativePath = path.join('linux', 'libs', 'dbas_sqlite.so');
        final baseDir = _resolveTestBaseDir(relativePath);
        libPath = path.join(baseDir, relativePath);
      } else {
        // For production Linux builds, the SO should be bundled with the app
        libPath = 'dbas_sqlite.so';
      }
    } else if (kIsWeb) {
      libPath = isTest ? path.join(Directory.current.path, 'web', 'libs', 'dbas_sqlite.js') : path.join('libs', 'dbas_sqlite.js');
      if (!isTest) {
        libPath = path.join((await getApplicationSupportDirectory()).path, libPath);
      }
    } else {
      throw UnsupportedError('Platform ${Platform.operatingSystem} not supported.');
    }

    return libPath.replaceAll('\\', '/');
  }

  Future<int> openDb(String path);
  bool isOpened(int dbPtr);
  Future<bool> databaseExists(String fileName);
  Future attachDb(String fileName, List<int> content);
  Future attachStreamDb(String fileName, Stream<List<int>> stream);
  Future<List<int>> getContent(String fileName);
  Future<void> streamCopyDb(String sourceFileName, String destFileName);
  Future<void> dropDb(String fileName);

  Future<int> executeSql(int dbPtr, String sql);
  Future<int> prepareQuery(int dbPtr, String sql);

  int bindNull(int dbPtr, int index);
  int bindInt(int dbPtr, int index, int value);
  int bindFloat(int dbPtr, int index, double value);
  int bindDouble(int dbPtr, int index, double value);
  int bindText(int dbPtr, int index, String value);
  int bindBlob(int dbPtr, int index, List<int> value);

  int bindNameNull(int dbPtr, String name);
  int bindNameInt(int dbPtr, String name, int value);
  int bindNameFloat(int dbPtr, String name, double value);
  int bindNameDouble(int dbPtr, String name, double value);
  int bindNameText(int dbPtr, String name, String value);
  int bindNameBlob(int dbPtr, String name, List<int> value);

  Future<int> readRow(int dbPtr);
  bool isNull(int dbPtr, int colIndex);

  String getColumnText(int dbPtr, int colIndex);
  int getColumnInt(int dbPtr, int colIndex);
  double getColumnFloat(int dbPtr, int colIndex);
  double getColumnDouble(int dbPtr, int colIndex);
  List<int> getColumnBlob(int dbPtr, int columnIndex);
  int getColumnBytes(int dbPtr, int columnIndex);
  String getColumnName(int dbPtr, int columnIndex);
  int getColumnType(int dbPtr, int colIndex);
  int getColumnCount(int dbPtr);

  String? getLastDbError(int dbPtr);
  int getAffectedRows(int dbPtr);
  int getLastInsertedId(int dbPtr);

  Future closeReader(int dbPtr);
  Future closeDb(int dbPtr);

  // ── Connection Pool ───
  Future<int> createPool(String path, int readerCount);
  int poolGetWriter(int poolPtr);
  int poolAcquireReader(int poolPtr);
  void poolReleaseReader(int poolPtr, int readerPtr);
  Future<void> closePool(int poolPtr);
}