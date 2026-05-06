import 'dart:io';
import 'package:dbas_sqlite/src/helpers/dbas_sqlite_platform_util.dart';
import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'package:dbas_sqlite/src/native/dbas_sqlite_native_app_selector.dart';
import 'package:dbas_sqlite/src/native/stub/dbas_sqlite_native_web_stub.dart'
    if (dart.library.js_interop) 'package:dbas_sqlite/src/native/dbas_sqlite_native_web.dart';

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

  static void removeInstance({String dbName = 'dbas.db'}) {
    _instance.remove(dbName);
  }

  static DbasSqliteNativeInterface _getPlatform({String dbName = 'dbas.db'}) {
    if (kIsWeb) {
      return DbasSqliteNativeWeb(dbName);
    }
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isWindows) {
      return DbasSqliteNativeApp(dbName);
    }
    throw UnsupportedError("Platform not supported: ${Platform.operatingSystem}");
  }

  Future<void> initialize();

  String get dbName => _dbName;

  bool get isTest => DbasSqlitePlatformUtil.isTest();

  Future<void> prepareLibIfNeeded() async {
    if (!kIsWeb || isTest) {
      return;
    }

    late String libAsset;
    late String libAssetName;
    if (kIsWeb) {
      libAssetName = 'dbas_sqlite.js';
      libAsset = path.join('dbas_sqlite', 'libs', libAssetName);
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

    libAsset = 'packages/dbas_sqlite/${libAsset.replaceAll('\\', '/')}';
    final buffer = await rootBundle.load(libAsset);
    await dllFile.writeAsBytes(buffer.buffer.asUint8List());
  }

  String _resolveTestBaseDir(String platformSubPath) {
    final current = Directory.current.path;
    final candidate = path.join(current, platformSubPath);
    if (File(candidate).existsSync()) {
      return current;
    }
    final parent = path.dirname(current);
    return parent;
  }

  Future<String> getLibraryPath() async {
    if (Platform.isIOS || (Platform.isMacOS && !isTest)) {
      return '';
    } else if (Platform.isMacOS) {
      String arch = Platform.version.contains('arm64') ||
              Platform.version.toLowerCase().contains('arm64')
          ? 'a64'
          : 'x86';
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
        libPath = 'dbas_sqlite.dll';
      }
    } else if (Platform.isLinux) {
      if (isTest) {
        final relativePath = path.join('linux', 'libs', 'dbas_sqlite.so');
        final baseDir = _resolveTestBaseDir(relativePath);
        libPath = path.join(baseDir, relativePath);
      } else {
        libPath = 'dbas_sqlite.so';
      }
    } else if (kIsWeb) {
      libPath = isTest
          ? path.join(Directory.current.path, 'web', 'libs', 'dbas_sqlite.js')
          : path.join('libs', 'dbas_sqlite.js');
      if (!isTest) {
        libPath = path.join((await getApplicationSupportDirectory()).path, libPath);
      }
    } else {
      throw UnsupportedError('Platform ${Platform.operatingSystem} not supported.');
    }

    return libPath.replaceAll('\\', '/');
  }

  // ── Library-scoped ──────────────────────────────────────────────────
  /// Cached at openDb time on every platform. Sync return on Dart side.
  String getSqliteVersion();

  /// Diagnostic — not exposed on the public API.
  int getAbiVersion();

  // ── Connection lifecycle ────────────────────────────────────────────
  Future<int> openDb(String path);
  bool isOpened(int dbPtr);
  Future<bool> databaseExists(String fileName);
  /// Eager input — caller hands over the full database bytes in
  /// memory. The platform writes them out to its file backend (FFI
  /// `writeAsBytes` on native, chunked OPFS write on web). For
  /// memory-friendly attach use [attachStreamDb] with a real source
  /// stream instead; this convenience overload exists for the common
  /// "I already have the bytes" case.
  Future attachDb(String fileName, List<int> content);

  /// Streaming input — chunks are written incrementally as they
  /// arrive. Native pipes them through `File.openWrite()`; web sends
  /// each chunk via the worker's chunked-attach protocol with
  /// per-chunk ACK backpressure.
  Future attachStreamDb(String fileName, Stream<List<int>> stream);

  /// Eager output — returns the full database content as a single
  /// byte buffer. The buffer is materialised in Dart memory before
  /// the future completes; for large databases prefer [streamCopyDb]
  /// (file-to-file copy that never enters Dart memory).
  Future<List<int>> getContent(String fileName);

  Future<void> streamCopyDb(String sourceFileName, String destFileName);
  Future<void> dropDb(String fileName);

  /// One-shot SQL (DDL/DML) without bindings. Used by
  /// `BEGIN`/`COMMIT`/`ROLLBACK`/`VACUUM`/`PRAGMA wal_checkpoint`.
  Future<int> executeSql(int dbPtr, String sql);

  /// Returns the C lib's rc from `CloseDb`. `checkpoint == true`
  /// runs `wal_checkpoint(TRUNCATE)` before the close. Throws on
  /// unexpected rc; returns SQLITE_OK or SQLITE_BUSY for the caller
  /// to act on.
  Future<int> closeDb(int dbPtr, {bool checkpoint = false});

  String? getLastDbError(int dbPtr);
  int getAffectedRows(int dbPtr);
  int getLastInsertedId(int dbPtr);
  int getTotalChanges(int dbPtr);
  String? getDbFileName(int dbPtr);
  Future<int> setBusyTimeout(int dbPtr, int ms);
  Future<int> enableWal(int dbPtr);

  // ── Statement lifecycle ─────────────────────────────────────────────
  /// Prepares a SQL statement on [dbPtr]. Returns the new
  /// [SQLiteStmtHandle] (non-zero, 0 == [sqliteInvalidStmtHandle] on
  /// failure) plus the statement's column metadata.
  ///
  /// Column metadata is captured at prepare time because it's stable
  /// for the lifetime of the statement, and callers commonly need
  /// it (e.g. [DbasSqliteReader.getColumnCount]) BEFORE the first
  /// [readRowAndCache] step.
  Future<({int handle, int columnCount, List<String> columnNames})>
      prepareQuery(int dbPtr, String sql);

  /// Finalises a prepared statement. Idempotent.
  Future<int> finalizeStmt(int dbPtr, int handle);

  /// Steps the statement and, on `SQLITE_ROW`, populates [cache]
  /// from native column data. Returns the step rc.
  Future<int> readRowAndCache(int dbPtr, int handle, RowData cache);

  /// Statement-scoped error message. `null` on no error or stale handle.
  String? getLastStmtError(int dbPtr, int handle);

  /// Captured at step time on `SQLITE_ROW` / `SQLITE_DONE`. Returns
  /// `-1` if the stmt has never been successfully stepped or the
  /// handle is stale.
  int getStmtAffectedRows(int dbPtr, int handle);
  int getStmtLastInsertedId(int dbPtr, int handle);

  // ── Bindings (positional) ───────────────────────────────────────────
  // All bind* methods return Future<int> so the FFI worker variant can
  // dispatch through an isolate without losing the C-side rc. Callers
  // (notably DbasSqliteStatement._replayBindsNative) MUST await the
  // result — the rc surfaces SQLITE_RANGE / SQLITE_TOOBIG / SQLITE_NOMEM
  // / stale-handle errors that would otherwise be silently swallowed.
  Future<int> bindNull(int dbPtr, int handle, int index);
  Future<int> bindInt(int dbPtr, int handle, int index, int value);
  Future<int> bindInt64(int dbPtr, int handle, int index, int value);
  Future<int> bindFloat(int dbPtr, int handle, int index, double value);
  Future<int> bindDouble(int dbPtr, int handle, int index, double value);
  Future<int> bindText(int dbPtr, int handle, int index, String value);
  Future<int> bindBlob(int dbPtr, int handle, int index, List<int> value);

  // ── Bindings (named) ────────────────────────────────────────────────
  Future<int> bindNameNull(int dbPtr, int handle, String name);
  Future<int> bindNameInt(int dbPtr, int handle, String name, int value);
  Future<int> bindNameInt64(int dbPtr, int handle, String name, int value);
  Future<int> bindNameFloat(int dbPtr, int handle, String name, double value);
  Future<int> bindNameDouble(int dbPtr, int handle, String name, double value);
  Future<int> bindNameText(int dbPtr, int handle, String name, String value);
  Future<int> bindNameBlob(int dbPtr, int handle, String name, List<int> value);

  // ── Column accessors ────────────────────────────────────────────────
  // These exist on the interface for the native FFI implementation,
  // which calls them per-column inside `readRowAndCache` to populate
  // the per-reader [RowData] cache. Web's `readRowAndCache` populates
  // the cache directly from the worker's row payload, so these
  // methods are unreachable on web (the implementation throws).
  bool isNull(int dbPtr, int handle, int colIndex);
  String getColumnText(int dbPtr, int handle, int colIndex);
  int getColumnInt(int dbPtr, int handle, int colIndex);
  int getColumnInt64(int dbPtr, int handle, int colIndex);
  double getColumnFloat(int dbPtr, int handle, int colIndex);
  double getColumnDouble(int dbPtr, int handle, int colIndex);
  List<int> getColumnBlob(int dbPtr, int handle, int columnIndex);
  int getColumnBytes(int dbPtr, int handle, int columnIndex);
  String getColumnName(int dbPtr, int handle, int columnIndex);
  int getColumnType(int dbPtr, int handle, int colIndex);
  int getColumnCount(int dbPtr, int handle);

  // ── Connection pool ─────────────────────────────────────────────────
  Future<int> createPool(String path, int readerCount);
  int poolGetWriter(int poolPtr);
  int poolAcquireReader(int poolPtr);
  Future<int> poolAcquireReaderBlocking(int poolPtr, int timeoutMs);
  void poolReleaseReader(int poolPtr, int readerPtr);
  Future<void> closePool(int poolPtr);

  /// Global pool size configuration (set before first getInstance call).
  ///
  /// Used as a lower bound on the FFI worker isolate count. The library
  /// auto-bumps to `max(workerPoolSize, readerPoolSize + 2)` at openDb
  /// time so blocking-acquire calls never starve releases.
  static int workerPoolSize = 4;
}
