import 'dart:io';
import 'dart:typed_data';
import 'package:dbas_sqlite_flutter/src/native/dbas_sqlite_native_interface.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart'
  if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/stub/dbas_sqlite_db_stub.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

final class DbasSqlitePlatform {
  static DbasSqlitePlatform? _instance;
  static final Map<String, DbasSqliteNativeInterface> _delegate = {};

  DbasSqlitePlatform._dbasSqlitePlatform();

  static Future<DbasSqlitePlatform> getInstance({String dbName = 'dbas.db'}) async {
    _getInterface(dbName: dbName);

    _instance ??= DbasSqlitePlatform._dbasSqlitePlatform();
    await _instance!.initialize(dbName);
    return _instance!;
  }

  static DbasSqliteNativeInterface _getInterface({String dbName = 'dbas.db'}) {
    if (!_delegate.containsKey(dbName)) {
      _delegate[dbName] = DbasSqliteNativeInterface.getInstance(dbName: dbName);
    }

    return _delegate[dbName]!;
  }

  bool isTest(String name) {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  }

  Future<void> initialize(String name) async => await _delegate[name]!.initialize();

  Future<DbasSqliteDb> openDb(String fileName) async {
    String dbName = _getDbName(fileName);
    final dbPtr = await _delegate[dbName]!.openDb(fileName);

    final isOpened = _delegate[dbName]!.isOpened(dbPtr);
    final lastError = isOpened ? null : _delegate[dbName]!.getLastDbError(dbPtr);

    if (dbPtr == 0 || !isOpened) {
      String lastErrorMessage = (lastError != null && lastError.isNotEmpty)
          ? lastError
          : 'Unknown error';
      throw Exception('Failed to open db in: $fileName. Reason: $lastErrorMessage');
    }

    return DbasSqliteDb(dbName, dbPtr);
  }

  Future dropDb(String fileName) async {
    final dbName = _getDbName(fileName);
    await _delegate[dbName]!.dropDb(fileName);
    _delegate.remove(dbName);
  }

  bool isOpened(DbasSqliteDb db) => _delegate[db.name]!.isOpened(db.ptr);

  String _getDbName(String fileName) {
    String dbName = fileName;
    if (fileName.contains('/')) {
      dbName = fileName.split('/').last;
    } else if (fileName.contains('\\')) {
      dbName = fileName.split('\\').last;
    }
    return dbName;
  }

  Future<bool> databaseExists(String fileName) async {
    String dbName = _getDbName(fileName);
    return await _delegate[dbName]!.databaseExists(fileName);
  }

  Future attachDb(String fileName, List<int> content) async {
    String dbName = _getDbName(fileName);
    await _delegate[dbName]!.attachDb(fileName, content);
  }

  Future<List<int>> getContent(String fileName) async {
    String dbName = _getDbName(fileName);
    return await _delegate[dbName]!.getContent(fileName);
  }

  Future<int> executeSql(DbasSqliteDb db, String sql, {bool syncWebDb = false}) async =>
      await _delegate[db.name]!.executeSql(db.ptr, sql, syncWebDb: syncWebDb);

  Future<int> prepareQuery(DbasSqliteDb db, String sql) async =>
      await _delegate[db.name]!.prepareQuery(db.ptr, sql);

  int bindNull(DbasSqliteDb db, int index) => _delegate[db.name]!.bindNull(db.ptr, index);
  int bindInt(DbasSqliteDb db, int index, int value) => _delegate[db.name]!.bindInt(db.ptr, index, value);
  int bindFloat(DbasSqliteDb db, int index, double value) => _delegate[db.name]!.bindFloat(db.ptr, index, value);
  int bindDouble(DbasSqliteDb db, int index, double value) => _delegate[db.name]!.bindDouble(db.ptr, index, value);
  int bindDecimal(DbasSqliteDb db, int index, Decimal value) => _delegate[db.name]!.bindDouble(db.ptr, index, double.parse(value.toString()));
  int bindText(DbasSqliteDb db, int index, String value) => _delegate[db.name]!.bindText(db.ptr, index, value);
  int bindBlob(DbasSqliteDb db, int index, Uint8List value) =>
      _delegate[db.name]!.bindBlob(db.ptr, index, Uint8List.fromList(value));

  int bindNameNull(DbasSqliteDb db, String name) => _delegate[db.name]!.bindNameNull(db.ptr, name);
  int bindNameInt(DbasSqliteDb db, String name, int value) => _delegate[db.name]!.bindNameInt(db.ptr, name, value);
  int bindNameFloat(DbasSqliteDb db, String name, double value) => _delegate[db.name]!.bindNameFloat(db.ptr, name, value);
  int bindNameDouble(DbasSqliteDb db, String name, double value) => _delegate[db.name]!.bindNameDouble(db.ptr, name, value);
  int bindNameDecimal(DbasSqliteDb db, String name, Decimal value) => _delegate[db.name]!.bindNameDouble(db.ptr, name, double.parse(value.toString()));
  int bindNameText(DbasSqliteDb db, String name, String value) => _delegate[db.name]!.bindNameText(db.ptr, name, value);
  int bindNameBlob(DbasSqliteDb db, String name, Uint8List value) =>
      _delegate[db.name]!.bindNameBlob(db.ptr, name, Uint8List.fromList(value));

  Future<int> readRow(DbasSqliteDb db, {bool syncWebDb = false}) async => await _delegate[db.name]!.readRow(db.ptr, syncWebDb: syncWebDb);
  bool isNull(DbasSqliteDb db, int colIndex) => _delegate[db.name]!.isNull(db.ptr, colIndex);

  String getColumnText(DbasSqliteDb db, int colIndex) => _delegate[db.name]!.getColumnText(db.ptr, colIndex);
  int getColumnInt(DbasSqliteDb db, int colIndex) => _delegate[db.name]!.getColumnInt(db.ptr, colIndex);
  double getColumnFloat(DbasSqliteDb db, int colIndex) => _delegate[db.name]!.getColumnFloat(db.ptr, colIndex);
  double getColumnDouble(DbasSqliteDb db, int colIndex) => _delegate[db.name]!.getColumnDouble(db.ptr, colIndex);
  Uint8List getColumnBlob(DbasSqliteDb db, int columnIndex) =>
      Uint8List.fromList(_delegate[db.name]!.getColumnBlob(db.ptr, columnIndex));

  int getColumnBytes(DbasSqliteDb db, int columnIndex) => _delegate[db.name]!.getColumnBytes(db.ptr, columnIndex);
  String getColumnName(DbasSqliteDb db, int colIndex) => _delegate[db.name]!.getColumnName(db.ptr, colIndex);
  int getColumnType(DbasSqliteDb db, int colIndex) => _delegate[db.name]!.getColumnType(db.ptr, colIndex);
  int getColumnCount(DbasSqliteDb db) => _delegate[db.name]!.getColumnCount(db.ptr);

  String? getLastDbError(DbasSqliteDb db) {
    return _delegate[db.name]!.getLastDbError(db.ptr);
  }
  int getAffectedRows(DbasSqliteDb db) => _delegate[db.name]!.getAffectedRows(db.ptr);
  int getLastInsertedId(DbasSqliteDb db) => _delegate[db.name]!.getLastInsertedId(db.ptr);

  Future closeReader(DbasSqliteDb db) async => await _delegate[db.name]!.closeReader(db.ptr);
  Future closeDb(DbasSqliteDb db) async {
    await _delegate[db.name]!.executeSql(db.ptr, 'PRAGMA wal_checkpoint(TRUNCATE);');
    await _delegate[db.name]!.closeDb(db.ptr);
  }
}
