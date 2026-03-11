import 'dart:io';

import 'package:dbas_sqlite_flutter/src/dbas_sqlite_column_type.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_db.dart'
  if (dart.library.js_interop) 'package:dbas_sqlite_flutter/src/stub/dbas_sqlite_db_stub.dart';
import 'package:dbas_sqlite_flutter/src/dbas_sqlite_platform.dart';
import 'package:dbas_sqlite_flutter/src/helpers/dbas_sqlite_platform_util.dart';
import 'package:decimal/decimal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';


/// A cross-platform SQLite database wrapper for Flutter.
///
/// Provides a unified API to interact with SQLite databases on Android, iOS,
/// macOS, Linux, Windows and Web platforms.
///
/// Uses a singleton pattern per database name, so calling [getInstance] with
/// the same [dbName] always returns the same instance.
///
/// ```dart
/// final db = await DbasSqlite.getInstance(dbName: 'myapp.db');
/// await db.openDb();
///
/// await db.executeSql(
///   'INSERT INTO users (name, email) VALUES (?, ?)',
///   params: ['John', 'john@example.com'],
/// );
///
/// await db.executeReader('SELECT * FROM users WHERE id > ?', params: [0]);
/// while (await db.readRow()) {
///   print(db.getColumnText(0));
/// }
///
/// await db.closeDb();
/// ```
class DbasSqlite {
  static final _sqliteOk = 0;
  static final _sqliteRow = 100;
  static final _sqliteDone = 101;
  static final _sqliteSuccessResults = [_sqliteOk, _sqliteRow, _sqliteDone];

  static final String _webDbDir = 'data';
  static final Map<String, DbasSqlite> _instance = {};
  final DbasSqlitePlatform _platform;
  final String dbName;
  DbasSqliteDb? _db;
  bool _isInTransaction = false;

  DbasSqlite._dbasSqlite(this._platform, this.dbName);

  /// Returns a singleton instance of [DbasSqlite] for the given [dbName].
  ///
  /// If an instance for [dbName] already exists, it is returned immediately.
  /// Otherwise, a new instance is created and cached.
  ///
  /// Defaults to `'dbas.db'` if no name is provided.
  static Future<DbasSqlite> getInstance({String dbName = 'dbas.db'}) async {
    if (_instance.containsKey(dbName)) {
      return _instance[dbName]!;
    }

    _instance[dbName] = DbasSqlite._dbasSqlite(await DbasSqlitePlatform.getInstance(dbName: dbName), dbName);
    return _instance[dbName]!;
  }

  static Future<String> _getDbPath() async {
    if (kIsWeb) {
      return '/$_webDbDir';
    }

    final directory = await getApplicationSupportDirectory();
    final dirPath = '${directory.path}/data'.replaceAll('\\', '/');
    final dir = Directory(dirPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dirPath;
  }

  /// Checks whether the database file exists on disk (or in IndexedDB on web).
  Future<bool> databaseExists() async {
    String fileName = kIsWeb ? dbName : await getAppDatabasePath(dbName: dbName);
    return await _platform.databaseExists(fileName);
  }

  /// Attaches a database from bytes and optionally opens it.
  ///
  /// If a database with the same name already exists and is opened, it will be
  /// closed and removed before attaching the new database.
  ///
  /// When [openDb] is `true` (the default), the database is automatically
  /// opened after being written to disk.
  ///
  /// Returns the [DbasSqlite] instance for the attached database.
  Future<DbasSqlite> attachDb(List<int> bytes, {bool openDb = true}) async {
    if (_instance.containsKey(dbName)) {
      if (_instance[dbName]!.isOpened()) {
        await _instance[dbName]!.closeDb();
      }

      _instance.remove(dbName);
    }

    String fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.attachDb(fileName, bytes);
    final instance = await getInstance(dbName: dbName);

    if (openDb) {
      await instance.openDb();
    }

    return instance;
  }

  /// Returns the raw bytes of the database file.
  ///
  /// Useful for backup, export or transferring the database to another device.
  Future<List<int>> getContent() async {
    String fileName = await getAppDatabasePath(dbName: dbName);
    return await _platform.getContent(fileName);
  }

  /// Deletes the database file, including WAL and SHM journal files.
  ///
  /// If the database is currently open, it will be closed first.
  /// Does nothing if the database file does not exist.
  Future<void> dropDb() async {
    if (!await databaseExists()) {
      return;
    }

    if (isOpened()) {
      await closeDb();
    }

    String fileName = await getAppDatabasePath(dbName: dbName);
    await _platform.dropDb(fileName);
  }

  /// Returns the full filesystem path for the database.
  ///
  /// If [dbName] is not provided, uses the instance's [dbName].
  ///
  /// In test mode (`FLUTTER_TEST`), the path points to `test/db/` in the
  /// project directory. On web, returns a virtual path. On other platforms,
  /// uses [getApplicationSupportDirectory].
  Future<String> getAppDatabasePath({String? dbName}) async {
    dbName ??= this.dbName;

    if (DbasSqlitePlatformUtil.isTest()) {
      String dbPath = path.join(Directory.current.path, 'test', 'db');
      Directory dbDir = Directory(dbPath);
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      return path.join(dbPath, dbName);
    }

    String dbPath = await _getDbPath();
    return '$dbPath/$dbName';
  }

  /// Opens the database connection.
  ///
  /// The database file path is resolved automatically via [getAppDatabasePath].
  /// After calling this method, [isOpened] returns `true`.
  ///
  /// Throws an [Exception] if the database cannot be opened.
  Future<void> openDb() async {
    String fileName = await getAppDatabasePath(dbName: dbName);
    _db = await _platform.openDb(fileName);
  }

  /// Returns `true` if the database connection is currently open.
  bool isOpened() {
    return _db != null && _platform.isOpened(_db!);
  }

  /// Executes a SQL statement (DDL or DML) and returns the number of affected rows.
  ///
  /// Supports both positional [params] and named [nameParams]:
  ///
  /// ```dart
  /// // Positional parameters (1-based internally)
  /// await db.executeSql(
  ///   'INSERT INTO users (name, age) VALUES (?, ?)',
  ///   params: ['Alice', 30],
  /// );
  ///
  /// // Named parameters (auto-prefixed with ':' if needed)
  /// await db.executeSql(
  ///   'INSERT INTO users (name, age) VALUES (:name, :age)',
  ///   nameParams: {'name': 'Alice', 'age': 30},
  /// );
  /// ```
  ///
  /// Set [syncWebDb] to `true` to persist changes to IndexedDB on web.
  ///
  /// Throws a [StateError] if the database is not opened.
  /// Throws an [Exception] if the query cannot be prepared or executed.
  Future<int> executeSql(String sql, {List<Object?>? params, Map<String, Object?>? nameParams, bool syncWebDb = false}) async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before executing SQL commands.');
    }

    int prepared = await _platform.prepareQuery(_db!, sql);
    if (prepared == -1 || prepared == 1) {
      await closeReader();
      String error = _platform.getLastDbError(_db!) ?? 'Unknown error ($prepared).';
      throw Exception("It was not possible to prepare the query: $error");
    }

    try {
      _bindParameters(params);
      _bindNameParameters(nameParams);
    } catch (_) {
      await closeReader();
      rethrow;
    }

    int result = 0;
    if (!await readRow(syncWebDb: syncWebDb)) {
      result = _platform.getAffectedRows(_db!);
    }

    await _platform.closeReader(_db!);
    return result;
  }

  /// Prepares and binds a SELECT query for row-by-row reading via [readRow].
  ///
  /// After calling this method, use [readRow] to iterate over results and
  /// the `getColumn*` methods to retrieve column values.
  ///
  /// ```dart
  /// await db.executeReader('SELECT * FROM users WHERE age > ?', params: [18]);
  /// while (await db.readRow()) {
  ///   print(db.getColumnText(0));
  /// }
  /// ```
  ///
  /// Supports both positional [params] and named [nameParams].
  ///
  /// Throws a [StateError] if the database is not opened.
  /// Throws an [Exception] if the query cannot be prepared.
  Future<int> executeReader(String sql, {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before executing SQL commands.');
    }

    int prepared = await _platform.prepareQuery(_db!, sql);
    if (prepared == -1 || prepared == 1) {
      await closeReader();
      final error = _platform.getLastDbError(_db!) ?? 'Unknown error ($prepared).';
      throw Exception("It was not possible to prepare the query: $error");
    }

    try {
      _bindParameters(params);
      _bindNameParameters(nameParams);
    } catch (_) {
      await closeReader();
      rethrow;
    }

    return 1;
  }

  /// Advances to the next row of the current result set.
  ///
  /// Returns `true` if a row is available, `false` when all rows have been
  /// read. The reader is automatically closed when there are no more rows.
  ///
  /// Set [syncWebDb] to `true` to persist any changes to IndexedDB on web.
  ///
  /// Throws an [Exception] if the query execution fails.
  Future<bool> readRow({bool syncWebDb = false}) async {
    int readResult = await _platform.readRow(_db!, syncWebDb: syncWebDb);
    if (!_sqliteSuccessResults.contains(readResult)) {
      String? error = _platform.getLastDbError(_db!);
      await closeReader();
      if (error == null && readResult == 20) {
        error = 'Misuse: possibly missing or invalid bind.';
      }
      error ??= 'Unknown error ($readResult).';
      throw Exception("It was not possible to run the query ($readResult): $error");
    }

    bool hasRow = readResult == _sqliteRow;
    if (!hasRow) {
      await closeReader();
    }
    return hasRow;
  }

  /// Returns `true` if the column at [idx] is NULL.
  bool isColumnNull(int idx) {
    return _platform.isNull(_db!, idx);
  }

  /// Returns the value of the column at [idx] as a [String].
  String getColumnText(int idx) {
    return _platform.getColumnText(_db!, idx);
  }

  /// Returns the value of the column at [idx] as a [String],
  /// or `null` if the column is NULL.
  String? getColumnNullableText(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnText(idx);
  }

  /// Returns the value of the column at [idx] as a [bool].
  ///
  /// Interprets `1` as `true` and any other integer as `false`.
  bool getColumnBool(int idx) {
    return _platform.getColumnInt(_db!, idx) == 1;
  }

  /// Returns the value of the column at [idx] as a [bool],
  /// or `null` if the column is NULL.
  bool? getColumnNullableBool(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnBool(idx);
  }

  /// Returns the value of the column at [idx] as an [int].
  int getColumnInt(int idx) {
    return _platform.getColumnInt(_db!, idx);
  }

  /// Returns the value of the column at [idx] as an [int],
  /// or `null` if the column is NULL.
  int? getColumnNullableInt(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnInt(idx);
  }

  /// Returns the value of the column at [idx] as a [Decimal].
  ///
  /// Returns [Decimal.zero] if the column is NULL.
  Decimal getColumnDecimal(int idx) {
    if (isColumnNull(idx)) {
      return Decimal.zero;
    }

    final textValue = _platform.getColumnText(_db!, idx);
    return Decimal.parse(textValue);
  }

  /// Returns the value of the column at [idx] as a [Decimal],
  /// or `null` if the column is NULL.
  Decimal? getColumnNullableDecimal(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnDecimal(idx);
  }

  /// Returns the value of the column at [idx] as a [double].
  double getColumnDouble(int idx) {
    return _platform.getColumnDouble(_db!, idx);
  }

  /// Returns the value of the column at [idx] as a [double],
  /// or `null` if the column is NULL.
  double? getColumnNullableDouble(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnDouble(idx);
  }

  /// Returns the value of the column at [idx] as a [DateTime].
  ///
  /// The column value must be a string parseable by [DateTime.parse].
  DateTime getColumnDateTime(int idx) {
    final value = _platform.getColumnText(_db!, idx);
    return DateTime.parse(value);
  }

  /// Returns the value of the column at [idx] as a [DateTime],
  /// or `null` if the column is NULL.
  DateTime? getColumnNullableDateTime(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnDateTime(idx);
  }

  /// Returns the value of the column at [idx] as a [Duration].
  ///
  /// Expects the column value in `HH:MM:SS` or `HH:MM:SS.mmm` format.
  Duration getColumnTime(int idx) {
    final parts = _platform.getColumnText(_db!, idx).split(':');
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final secondsMs = parts.length > 2 ? parts[2].split('.').where((i) => i.trim() != '').toList() : ['0'];

    return Duration(
      hours: int.tryParse(parts[0]) ?? 0,
      minutes: minute,
      seconds: int.tryParse(secondsMs.first) ?? 0,
      milliseconds: secondsMs.length > 1 ? int.tryParse(secondsMs.last.padRight(3, '0').substring(0, 3)) ?? 0 : 0,
    );
  }

  /// Returns the value of the column at [idx] as a [Duration],
  /// or `null` if the column is NULL.
  Duration? getColumnNullableTime(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnTime(idx);
  }

  /// Returns the value of the column at [idx] as an enum of type [T].
  ///
  /// The column integer value is used as the index into [values].
  ///
  /// Throws an [ArgumentError] if the integer value is out of range.
  T getColumnEnum<T extends Enum>(int idx, List<T> values) {
    final intValue = _platform.getColumnInt(_db!, idx);
    if (intValue < 0 || intValue >= values.length) {
      throw ArgumentError('No enum value found for index $intValue in ${T.toString()}');
    }
    return values[intValue];
  }

  /// Returns the value of the column at [idx] as an enum of type [T],
  /// or `null` if the column is NULL.
  T? getColumnNullableEnum<T extends Enum>(int idx, List<T> values) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnEnum<T>(idx, values);
  }

  /// Returns the value of the column at [idx] as a [Uint8List] (binary data).
  Uint8List getColumnBlob(int idx) {
    return _platform.getColumnBlob(_db!, idx);
  }

  /// Returns the value of the column at [idx] as a [Uint8List],
  /// or `null` if the column is NULL.
  Uint8List? getColumnNullableBlob(int idx) {
    if (isColumnNull(idx)) {
      return null;
    }

    return getColumnBlob(idx);
  }

  /// Returns the name of the column at [columnIndex] in the current result set.
  String getColumnName(int columnIndex) {
    return _platform.getColumnName(_db!, columnIndex);
  }

  /// Returns the [SqliteColumnType] of the column at [idx].
  SqliteColumnType getColumnType(int idx) {
    return SqliteColumnType.fromInt( _platform.getColumnType(_db!, idx));
  }

  /// Returns the number of columns in the current result set.
  int getColumnCount() {
    return _platform.getColumnCount(_db!);
  }

  /// Returns the row ID of the last successfully inserted row.
  int getLastInsertedId() {
    return _platform.getLastInsertedId(_db!);
  }

  void _bindParameters(List<Object?>? parameters) {
    if (parameters == null || parameters.isEmpty) {
      return;
    }

    for (int i = 0; i < parameters.length; i++) {
      final index = i + 1; // SQLite index are based on starting 1
      final value = parameters[i];

      int paramResult = -1;
      if (value == null) {
        paramResult = _platform.bindNull(_db!, index);
      } else if (value is bool) {
        paramResult = _platform.bindInt(_db!, index, value ? 1 : 0);
      } else if (value is int) {
        paramResult = _platform.bindInt(_db!, index, value);
      } else if (value is double) {
        paramResult = _platform.bindDouble(_db!, index, value);
      } else if (value is Decimal) {
        paramResult = _platform.bindDecimal(_db!, index, value);
      } else if (value is String) {
        paramResult = _platform.bindText(_db!, index, value);
      } else if (value is Uint8List) {
        paramResult = _platform.bindBlob(_db!, index, value);
      } else if (value is Enum) {
        paramResult = _platform.bindInt(_db!, index, value.index);
      } else {
        throw UnsupportedError('Unsupported type to SQLite bind: ${value.runtimeType}');
      }

      if (paramResult == -1 || paramResult == 1) {
        throw Exception("It was not possible to bind the parameter: ${_platform.getLastDbError(_db!) ?? 'Unknown error ($paramResult)'}");
      }
    }
  }

  void _bindNameParameters(Map<String, Object?>? parameters) {
    if (parameters == null || parameters.isEmpty) {
      return;
    }

    for (MapEntry<String, Object?> entry in parameters.entries) {
      String paramName = entry.key;
      Object? value = entry.value;

      if (!paramName.startsWith(':') && !paramName.startsWith('@') && !paramName.startsWith(r'$')) {
        paramName = ':$paramName';
      }

      int paramResult = -1;
      if (value == null) {
        paramResult = _platform.bindNameNull(_db!, paramName);
      } else if (value is bool) {
        paramResult = _platform.bindNameInt(_db!, paramName, value ? 1 : 0);
      } else if (value is int) {
        paramResult = _platform.bindNameInt(_db!, paramName, value);
      } else if (value is double) {
        paramResult = _platform.bindNameDouble(_db!, paramName, value.toDouble());
      } else if (value is Decimal) {
        paramResult = _platform.bindNameDecimal(_db!, paramName, value);
      } else if (value is String) {
        paramResult = _platform.bindNameText(_db!, paramName, value);
      } else if (value is Uint8List) {
        paramResult = _platform.bindNameBlob(_db!, paramName, value);
      } else if (value is Enum) {
        paramResult = _platform.bindNameInt(_db!, paramName, value.index);
      } else {
        throw UnsupportedError('Unsupported type to SQLite named bind: ${value.runtimeType}');
      }

      if (paramResult == -1 || paramResult == 1) {
        throw Exception("It was not possible to bind the named parameter: ${_platform.getLastDbError(_db!) ?? 'Unknown error ($paramResult)'}");
      }
    }
  }

  /// Closes the database connection and removes the instance from the cache.
  /// If a transaction is currently active, it will be automatically rolled
  /// back before closing to prevent silent data loss.
  ///
  /// After calling this method, [isOpened] returns `false` and a new call
  /// to [getInstance] with the same name will create a fresh instance.
  Future<void> closeDb() async {
    await rollback();

    if (_instance.containsKey(dbName)) {
      _instance.remove(dbName);
    }
    await _platform.closeDb(_db!);
    _db = null;
  }

  /// Closes the current prepared statement / reader.
  ///
  /// This is called automatically when [readRow] returns `false`, but can
  /// be called manually to release resources early (e.g. when breaking out
  /// of a read loop).
  Future<void> closeReader() async {
    if (_db == null) return;
    await _platform.closeReader(_db!);
  }

  /// Returns `true` if a transaction is currently active.
  ///
  /// A transaction is considered active after calling [beginTransaction]
  /// and before calling [commit] or [rollback].
  bool get isInTransaction => _isInTransaction;

  /// Begins a new database transaction.
  ///
  /// All subsequent SQL statements will be part of this transaction until
  /// [commit] or [rollback] is called.
  ///
  /// If a transaction is already active, this method does nothing.
  ///
  /// For automatic rollback on errors, prefer using [transaction] instead.
  ///
  /// ```dart
  /// await db.beginTransaction();
  /// try {
  ///   await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Alice']);
  ///   await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Bob']);
  ///   await db.commit();
  /// } catch (_) {
  ///   await db.rollback();
  ///   rethrow;
  /// }
  /// ```
  ///
  /// Throws a [StateError] if the database is not opened.
  Future<void> beginTransaction() async {
    if (!isOpened()) {
      throw StateError('Database is not opened. Please open the database before starting a transaction.');
    }
    if (_isInTransaction) {
      return;
    }
    await _platform.executeSql(_db!, 'BEGIN TRANSACTION');
    _isInTransaction = true;
  }

  /// Commits the current transaction, persisting all changes made since
  /// [beginTransaction] was called.
  ///
  /// If no transaction is active, this method does nothing.
  ///
  /// After calling this method, [isInTransaction] returns `false`.
  Future<void> commit() async {
    if (!_isInTransaction) {
      return;
    }
    try {
      await _platform.executeSql(_db!, 'COMMIT');
    } finally {
      _isInTransaction = false;
    }
  }

  /// Rolls back the current transaction, discarding all changes made since
  /// [beginTransaction] was called.
  ///
  /// If no transaction is active, this method does nothing.
  ///
  /// After calling this method, [isInTransaction] returns `false`.
  Future<void> rollback() async {
    if (!_isInTransaction) {
      return;
    }
    try {
      await _platform.executeSql(_db!, 'ROLLBACK');
    } finally {
      _isInTransaction = false;
    }
  }

  /// Executes [action] within a database transaction with automatic
  /// commit and rollback.
  ///
  /// If [action] completes successfully, the transaction is committed.
  /// If [action] throws an exception, the transaction is rolled back
  /// and the exception is rethrown.
  ///
  /// ```dart
  /// await db.transaction((db) async {
  ///   await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Alice']);
  ///   await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Bob']);
  /// });
  /// ```
  ///
  /// Throws a [StateError] if the database is not opened.
  /// Throws a [StateError] if a transaction is already active.
  Future<void> transaction(Future<void> Function(DbasSqlite db) action) async {
    if (_isInTransaction) {
      throw StateError('A transaction is already active. Cannot nest transactions.');
    }
    await beginTransaction();
    try {
      await action(this);
      await commit();
    } catch (_) {
      try {
        await rollback();
      } catch (_) {
        // Rollback failed, but we still rethrow the original exception.
      }
      rethrow;
    }
  }
}

