import 'dart:io';
import 'dart:typed_data';

import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

enum TestStatus { active, inactive, suspended }

/// Helper to create a fresh database.
///
/// Uses single connection (no pool) by default to minimize native resource
/// overhead. Pool-specific tests use [readerPoolSize] explicitly.
Future<DbasSqlite> _createTestDb(String dbName, {int readerPoolSize = 0}) async {
  final db = await DbasSqlite.getInstance(dbName: dbName);
  await db.dropDb();
  await db.openDb(readerPoolSize: readerPoolSize);
  return db;
}

void main() async {
  setUpAll(() async {
    // Clean test database directory before all tests
    final testDbDir = Directory(path.join(Directory.current.path, 'test', 'db'));
    if (await testDbDir.exists()) {
      await testDbDir.delete(recursive: true);
    }
    await testDbDir.create(recursive: true);
  });

  // ──────────────────────────────────────────────────────────────────────
  // Existing tests
  // ──────────────────────────────────────────────────────────────────────

  test('Test Open, create table, insert, select and close', () async {
    String dbName = 'test.db';
    final dbasSqlite = await DbasSqlite.getInstance(dbName: dbName);
    await dbasSqlite.dropDb();

    await dbasSqlite.openDb(readerPoolSize: 0);

    File dbFile = File(await dbasSqlite.getAppDatabasePath(dbName: dbName));

    expect(await dbasSqlite.databaseExists(), isTrue, reason: 'DB file should exist after opening the database (native).');
    expect(await dbFile.exists(), isTrue, reason: 'DB file should exist after opening the database.');
    expect(dbasSqlite.isOpened(), isTrue, reason: 'Database should be opened after calling openDb.');

    await dbasSqlite.executeSql('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await dbasSqlite.executeSql(
      'INSERT INTO users (name, email) VALUES (:name, :email)',
      nameParams: <String, Object?>{
        'name': 'test1',
        'email': 'test1@test.com',
      },
    );

    await dbasSqlite.executeSql(
      'INSERT INTO users (name, email) VALUES (?, ?)',
      params: ['test2', 'test2@test.com'],
    );

    final reader = await dbasSqlite.executeReader("SELECT name, email FROM users where id > :id", params: [0]);
    int colCount = reader.getColumnCount();

    List<List<Object?>> users = [];
    while (await reader.readRow()) {
      List<Object?> user = [];
      for (int colIdx = 0; colIdx < colCount; colIdx++) {
        SqliteColumnType type = reader.getColumnType(colIdx);

        if (type == SqliteColumnType.nullType) {
          user.add(null);
        } else if (type == SqliteColumnType.integer) {
          user.add(reader.getColumnInt(colIdx));
        } else if (type == SqliteColumnType.double) {
          user.add(reader.getColumnDouble(colIdx));
        } else if (type == SqliteColumnType.text) {
          user.add(reader.getColumnText(colIdx));
        } else if (type == SqliteColumnType.blob) {
          user.add(reader.getColumnBlob(colIdx));
        } else {
          user.add('<INVALID TYPE ${int.parse(type.toString())}>');
        }
      }

      users.add(user);
    }

    expect(users, [['test1', 'test1@test.com'], ['test2', 'test2@test.com']]);

    await dbasSqlite.closeDb();
    expect(dbasSqlite.isOpened(), isFalse);
  });

  test('Test exists and attach', () async {
    String testDbName = 'test_attach1.db';
    DbasSqlite testDbasSqlite = await DbasSqlite.getInstance(dbName: testDbName);
    String testDbPath = await testDbasSqlite.getAppDatabasePath();
    await testDbasSqlite.dropDb();

    await testDbasSqlite.openDb(readerPoolSize: 0);
    await testDbasSqlite.executeSql('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await testDbasSqlite.closeDb();

    String dbName = 'test_attach2.db';
    DbasSqlite dbasSqlite = await DbasSqlite.getInstance(dbName: dbName);

    File dbFile = File(await dbasSqlite.getAppDatabasePath());
    List<int> bytes = await File(testDbPath).readAsBytes();
    dbasSqlite = await dbasSqlite.attachDb(bytes);

    expect(await dbasSqlite.databaseExists(), isTrue, reason: 'DB file should exist after opening the database (native).');
    expect(await dbFile.exists(), isTrue, reason: 'DB file should exist after opening the database.');
    expect(dbasSqlite.isOpened(), isTrue, reason: 'Database should be opened after calling openDb.');

    final params = {
      ':name': 'name-text',
      ':email': 'email@email.com',
      ':created_at': '2023-01-01 00:00:00',
    };
    await dbasSqlite.executeSql('''
      INSERT INTO users (name, email, created_at) values (:name, :email, :created_at)
    ''', nameParams: params);

    final selectParams = {
      ':id': 0,
      ':name': 'random-bla',
    };
    final reader = await dbasSqlite.executeReader("SELECT * FROM users WHERE id > :id AND name != :name", nameParams: selectParams);
    List<Map<String, String>> users = [];
    while (await reader.readRow()) {
      users.add({
        'id': reader.getColumnText(0),
        'name': reader.getColumnText(1),
        'email': reader.getColumnText(2),
        'created_at': reader.getColumnText(3),
      });
    }

    expect(users.length, 1);
    expect(users[0]['name'], 'name-text');
    expect(users[0]['email'], 'email@email.com');
    expect(users[0]['created_at'], '2023-01-01 00:00:00');

    await dbasSqlite.closeDb();
    await dbasSqlite.dropDb();

    expect(await dbFile.exists(), isFalse, reason: 'DB file should not exist after opening the database.');
    expect(dbasSqlite.isOpened(), isFalse, reason: 'Database should not be opened after calling openDb.');
  });

  // ──────────────────────────────────────────────────────────────────────
  // Singleton behavior
  // ──────────────────────────────────────────────────────────────────────

  test('getInstance returns the same instance for the same dbName', () async {
    final db1 = await DbasSqlite.getInstance(dbName: 'singleton_test.db');
    final db2 = await DbasSqlite.getInstance(dbName: 'singleton_test.db');
    expect(identical(db1, db2), isTrue);

    final db3 = await DbasSqlite.getInstance(dbName: 'singleton_other.db');
    expect(identical(db1, db3), isFalse);
  });

  // ──────────────────────────────────────────────────────────────────────
  // Error handling
  // ──────────────────────────────────────────────────────────────────────

  test('executeSql throws StateError when database is not opened', () async {
    final db = await DbasSqlite.getInstance(dbName: 'not_opened.db');
    expect(
      () => db.executeSql('SELECT 1'),
      throwsA(isA<StateError>()),
    );
  });

  test('executeReader throws StateError when database is not opened', () async {
    final db = await DbasSqlite.getInstance(dbName: 'not_opened_reader.db');
    expect(
      () => db.executeReader('SELECT 1'),
      throwsA(isA<StateError>()),
    );
  });

  test('executeSql throws Exception on invalid SQL', () async {
    final db = await _createTestDb('invalid_sql.db');

    await expectLater(
      () => db.executeSql('INVALID SQL STATEMENT'),
      throwsA(anything),
    );

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // getLastInsertedId
  // ──────────────────────────────────────────────────────────────────────

  test('getLastInsertedId returns correct id', () async {
    final db = await _createTestDb('last_insert_id.db');

    await db.executeSql('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.executeSql(
      'INSERT INTO items (name) VALUES (?)',
      params: ['first'],
    );
    expect(db.getLastInsertedId(), 1);

    await db.executeSql(
      'INSERT INTO items (name) VALUES (?)',
      params: ['second'],
    );
    expect(db.getLastInsertedId(), 2);

    await db.executeSql(
      'INSERT INTO items (name) VALUES (?)',
      params: ['third'],
    );
    expect(db.getLastInsertedId(), 3);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // getColumnName
  // ──────────────────────────────────────────────────────────────────────

  test('getColumnName returns correct column names', () async {
    final db = await _createTestDb('col_name.db');

    await db.executeSql('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        product_name TEXT,
        price REAL
      )
    ''');

    await db.executeSql(
      'INSERT INTO products (id, product_name, price) VALUES (?, ?, ?)',
      params: [1, 'Widget', 9.99],
    );

    final reader = await db.executeReader('SELECT id, product_name, price FROM products');
    expect(await reader.readRow(), isTrue);

    expect(reader.getColumnName(0), 'id');
    expect(reader.getColumnName(1), 'product_name');
    expect(reader.getColumnName(2), 'price');
    expect(reader.getColumnCount(), 3);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // NULL handling & isColumnNull
  // ──────────────────────────────────────────────────────────────────────

  test('isColumnNull and nullable getters work correctly', () async {
    final db = await _createTestDb('null_test.db');

    await db.executeSql('''
      CREATE TABLE nullable_test (
        id INTEGER PRIMARY KEY,
        text_col TEXT,
        int_col INTEGER,
        real_col REAL,
        blob_col BLOB
      )
    ''');

    // Insert row with all NULLs (except id)
    await db.executeSql(
      'INSERT INTO nullable_test (id, text_col, int_col, real_col, blob_col) VALUES (?, ?, ?, ?, ?)',
      params: [1, null, null, null, null],
    );

    // Insert row with values
    await db.executeSql(
      'INSERT INTO nullable_test (id, text_col, int_col, real_col, blob_col) VALUES (?, ?, ?, ?, ?)',
      params: [2, 'hello', 42, 3.14, Uint8List.fromList([1, 2, 3])],
    );

    // Read NULL row
    final reader = await db.executeReader('SELECT text_col, int_col, real_col, blob_col FROM nullable_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    expect(reader.isColumnNull(0), isTrue);
    expect(reader.isColumnNull(1), isTrue);
    expect(reader.isColumnNull(2), isTrue);
    expect(reader.isColumnNull(3), isTrue);

    expect(reader.getColumnNullableText(0), isNull);
    expect(reader.getColumnNullableInt(1), isNull);
    expect(reader.getColumnNullableDouble(2), isNull);
    expect(reader.getColumnNullableBlob(3), isNull);

    await reader.close();

    // Read non-NULL row
    final reader2 = await db.executeReader('SELECT text_col, int_col, real_col, blob_col FROM nullable_test WHERE id = 2');
    expect(await reader2.readRow(), isTrue);

    expect(reader2.isColumnNull(0), isFalse);
    expect(reader2.getColumnNullableText(0), 'hello');
    expect(reader2.getColumnNullableInt(1), 42);
    expect(reader2.getColumnNullableDouble(2), closeTo(3.14, 0.001));

    final blobResult = reader2.getColumnNullableBlob(3);
    expect(blobResult, isNotNull);
    expect(blobResult!.sublist(0, 3), Uint8List.fromList([1, 2, 3]));

    await reader2.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Bool binding and retrieval
  // ──────────────────────────────────────────────────────────────────────

  test('Bool bind and getColumnBool / getColumnNullableBool', () async {
    final db = await _createTestDb('bool_test.db');

    await db.executeSql('''
      CREATE TABLE bool_test (
        id INTEGER PRIMARY KEY,
        flag INTEGER,
        nullable_flag INTEGER
      )
    ''');

    await db.executeSql(
      'INSERT INTO bool_test (id, flag, nullable_flag) VALUES (?, ?, ?)',
      params: [1, true, null],
    );
    await db.executeSql(
      'INSERT INTO bool_test (id, flag, nullable_flag) VALUES (?, ?, ?)',
      params: [2, false, true],
    );

    final reader = await db.executeReader('SELECT flag, nullable_flag FROM bool_test ORDER BY id');

    // Row 1: flag=true, nullable_flag=NULL
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnBool(0), isTrue);
    expect(reader.getColumnNullableBool(1), isNull);

    // Row 2: flag=false, nullable_flag=true
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnBool(0), isFalse);
    expect(reader.getColumnNullableBool(1), isTrue);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Decimal binding and retrieval
  // ──────────────────────────────────────────────────────────────────────

  test('Decimal bind and getColumnDecimal / getColumnNullableDecimal', () async {
    final db = await _createTestDb('decimal_test.db');

    await db.executeSql('''
      CREATE TABLE decimal_test (
        id INTEGER PRIMARY KEY,
        amount REAL,
        nullable_amount REAL
      )
    ''');

    final decimalValue = Decimal.parse('123.45');
    await db.executeSql(
      'INSERT INTO decimal_test (id, amount, nullable_amount) VALUES (?, ?, ?)',
      params: [1, decimalValue, null],
    );

    final reader = await db.executeReader('SELECT amount, nullable_amount FROM decimal_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    final result = reader.getColumnDecimal(0);
    expect(result.toDouble(), closeTo(123.45, 0.001));

    expect(reader.getColumnNullableDecimal(1), isNull);

    // getColumnDecimal on NULL returns Decimal.zero
    expect(reader.getColumnDecimal(1), Decimal.zero);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // DateTime binding and retrieval
  // ──────────────────────────────────────────────────────────────────────

  test('getColumnDateTime / getColumnNullableDateTime', () async {
    final db = await _createTestDb('datetime_test.db');

    await db.executeSql('''
      CREATE TABLE datetime_test (
        id INTEGER PRIMARY KEY,
        created_at TEXT,
        deleted_at TEXT
      )
    ''');

    await db.executeSql(
      'INSERT INTO datetime_test (id, created_at, deleted_at) VALUES (?, ?, ?)',
      params: [1, '2025-06-15T10:30:00.000', null],
    );

    final reader = await db.executeReader('SELECT created_at, deleted_at FROM datetime_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    final dt = reader.getColumnDateTime(0);
    expect(dt.year, 2025);
    expect(dt.month, 6);
    expect(dt.day, 15);
    expect(dt.hour, 10);
    expect(dt.minute, 30);

    expect(reader.getColumnNullableDateTime(1), isNull);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Duration (Time) retrieval
  // ──────────────────────────────────────────────────────────────────────

  test('getColumnTime / getColumnNullableTime', () async {
    final db = await _createTestDb('time_test.db');

    await db.executeSql('''
      CREATE TABLE time_test (
        id INTEGER PRIMARY KEY,
        duration TEXT,
        nullable_duration TEXT
      )
    ''');

    await db.executeSql(
      'INSERT INTO time_test (id, duration, nullable_duration) VALUES (?, ?, ?)',
      params: [1, '02:30:45', null],
    );
    await db.executeSql(
      'INSERT INTO time_test (id, duration, nullable_duration) VALUES (?, ?, ?)',
      params: [2, '01:15:30.500', null],
    );

    final reader = await db.executeReader('SELECT duration, nullable_duration FROM time_test ORDER BY id');

    // Row 1: 02:30:45
    expect(await reader.readRow(), isTrue);
    final d1 = reader.getColumnTime(0);
    expect(d1.inHours, 2);
    expect(d1.inMinutes % 60, 30);
    expect(d1.inSeconds % 60, 45);
    expect(reader.getColumnNullableTime(1), isNull);

    // Row 2: 01:15:30.500
    expect(await reader.readRow(), isTrue);
    final d2 = reader.getColumnTime(0);
    expect(d2.inHours, 1);
    expect(d2.inMinutes % 60, 15);
    expect(d2.inSeconds % 60, 30);
    expect(d2.inMilliseconds % 1000, 500);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Enum binding and retrieval
  // ──────────────────────────────────────────────────────────────────────

  test('Enum bind and getColumnEnum / getColumnNullableEnum', () async {
    final db = await _createTestDb('enum_test.db');

    await db.executeSql('''
      CREATE TABLE enum_test (
        id INTEGER PRIMARY KEY,
        status INTEGER,
        nullable_status INTEGER
      )
    ''');

    await db.executeSql(
      'INSERT INTO enum_test (id, status, nullable_status) VALUES (?, ?, ?)',
      params: [1, TestStatus.active, null],
    );
    await db.executeSql(
      'INSERT INTO enum_test (id, status, nullable_status) VALUES (?, ?, ?)',
      params: [2, TestStatus.suspended, TestStatus.inactive],
    );

    final reader = await db.executeReader('SELECT status, nullable_status FROM enum_test ORDER BY id');

    // Row 1
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnEnum(0, TestStatus.values), TestStatus.active);
    expect(reader.getColumnNullableEnum(1, TestStatus.values), isNull);

    // Row 2
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnEnum(0, TestStatus.values), TestStatus.suspended);
    expect(reader.getColumnNullableEnum(1, TestStatus.values), TestStatus.inactive);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Blob binding and retrieval
  // ──────────────────────────────────────────────────────────────────────

  test('Blob bind and getColumnBlob / getColumnNullableBlob', () async {
    final db = await _createTestDb('blob_test.db');

    await db.executeSql('''
      CREATE TABLE blob_test (
        id INTEGER PRIMARY KEY,
        data BLOB,
        nullable_data BLOB
      )
    ''');

    final blobData = Uint8List.fromList([0, 1, 2, 127, 128, 254, 255]);
    await db.executeSql(
      'INSERT INTO blob_test (id, data, nullable_data) VALUES (?, ?, ?)',
      params: [1, blobData, null],
    );

    final reader = await db.executeReader('SELECT data, nullable_data FROM blob_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    final blobResult = reader.getColumnBlob(0);
    expect(blobResult, isNotEmpty, reason: 'Blob should contain data');
    expect(reader.getColumnNullableBlob(1), isNull);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  test('Blob bind accepts List<int> (not just Uint8List)', () async {
    final db = await _createTestDb('blob_list_int_test.db');

    await db.executeSql('''
      CREATE TABLE blob_li_test (id INTEGER PRIMARY KEY, data BLOB)
    ''');

    // Use plain List<int> (not Uint8List) to exercise the List<int> branch
    final data = List<int>.generate(256, (i) => i);
    await db.executeSql(
      'INSERT INTO blob_li_test (id, data) VALUES (?, ?)',
      params: [1, data],
    );

    final reader = await db.executeReader('SELECT data FROM blob_li_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    final result = reader.getColumnBlob(0);
    expect(result.length, 256);
    expect(result[0], 0);
    expect(result[127], 127);
    expect(result[255], 255);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Double binding and retrieval
  // ──────────────────────────────────────────────────────────────────────

  test('Double bind and getColumnDouble / getColumnNullableDouble', () async {
    final db = await _createTestDb('double_test.db');

    await db.executeSql('''
      CREATE TABLE double_test (
        id INTEGER PRIMARY KEY,
        value REAL,
        nullable_value REAL
      )
    ''');

    await db.executeSql(
      'INSERT INTO double_test (id, value, nullable_value) VALUES (?, ?, ?)',
      params: [1, 3.14159265, null],
    );

    final reader = await db.executeReader('SELECT value, nullable_value FROM double_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    expect(reader.getColumnDouble(0), closeTo(3.14159265, 0.0000001));
    expect(reader.getColumnNullableDouble(1), isNull);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Named parameters: auto-prefix and different prefixes
  // ──────────────────────────────────────────────────────────────────────

  test('Named params without prefix get auto-prefixed with ":"', () async {
    final db = await _createTestDb('auto_prefix.db');

    await db.executeSql('''
      CREATE TABLE prefix_test (
        id INTEGER PRIMARY KEY,
        name TEXT,
        value INTEGER
      )
    ''');

    // No prefix — should be auto-prefixed with ':'
    await db.executeSql(
      'INSERT INTO prefix_test (id, name, value) VALUES (:id, :name, :value)',
      nameParams: {'id': 1, 'name': 'auto', 'value': 100},
    );

    final reader = await db.executeReader('SELECT name, value FROM prefix_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'auto');
    expect(reader.getColumnInt(1), 100);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  test('Named params with @ prefix', () async {
    final db = await _createTestDb('at_prefix.db');

    await db.executeSql('''
      CREATE TABLE at_test (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');

    await db.executeSql(
      'INSERT INTO at_test (id, name) VALUES (@id, @name)',
      nameParams: {'@id': 1, '@name': 'at-sign'},
    );

    final reader = await db.executeReader('SELECT name FROM at_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'at-sign');

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  test('Named params with \$ prefix', () async {
    final db = await _createTestDb('dollar_prefix.db');

    await db.executeSql('''
      CREATE TABLE dollar_test (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');

    await db.executeSql(
      'INSERT INTO dollar_test (id, name) VALUES (\$id, \$name)',
      nameParams: {r'$id': 1, r'$name': 'dollar-sign'},
    );

    final reader = await db.executeReader('SELECT name FROM dollar_test WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'dollar-sign');

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Named params: extra params silently skipped & throwOnMissingNamedParams
  // ──────────────────────────────────────────────────────────────────────

  test('Extra named params are silently skipped by default', () async {
    final db = await _createTestDb('skip_extra_params.db');

    await db.executeSql('''
      CREATE TABLE skip_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');

    // :extra does not exist in the SQL — should be silently ignored
    await db.executeSql(
      'INSERT INTO skip_tbl (id, name) VALUES (:id, :name)',
      nameParams: {'id': 1, 'name': 'Alice', 'extra': 'ignored'},
    );

    final reader = await db.executeReader('SELECT name FROM skip_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'Alice');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('Extra named params in executeReader are silently skipped', () async {
    final db = await _createTestDb('skip_extra_reader.db');

    await db.executeSql('''
      CREATE TABLE skip_reader_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');

    await db.executeSql(
      'INSERT INTO skip_reader_tbl (id, name) VALUES (?, ?)',
      params: [1, 'Alice'],
    );

    // :missing does not exist in the SQL — should be silently ignored
    final reader = await db.executeReader(
      'SELECT name FROM skip_reader_tbl WHERE id = :id',
      nameParams: {'id': 1, 'missing': 'ignored'},
    );
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'Alice');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('throwOnMissingNamedParams defaults to false', () async {
    final db = await _createTestDb('throw_default.db');
    expect(db.throwOnMissingNamedParams, isFalse);
    await db.closeDb();
    await db.dropDb();
  });

  test('throwOnMissingNamedParams can be set via getInstance', () async {
    final db = await DbasSqlite.getInstance(
      dbName: 'throw_via_instance.db',
      throwOnMissingNamedParams: true,
    );
    expect(db.throwOnMissingNamedParams, isTrue);

    await db.dropDb();
  });

  test('getInstance updates throwOnMissingNamedParams on cached instance', () async {
    final db1 = await DbasSqlite.getInstance(
      dbName: 'cached_flag.db',
      throwOnMissingNamedParams: false,
    );
    expect(db1.throwOnMissingNamedParams, isFalse);

    final db2 = await DbasSqlite.getInstance(
      dbName: 'cached_flag.db',
      throwOnMissingNamedParams: true,
    );
    expect(identical(db1, db2), isTrue);
    expect(db2.throwOnMissingNamedParams, isTrue);
    // The original reference reflects the update too
    expect(db1.throwOnMissingNamedParams, isTrue);

    await db1.dropDb();
  });

  test('throwOnMissingNamedParams throws on extra named params', () async {
    final db = await _createTestDb('throw_extra.db');

    await db.executeSql('''
      CREATE TABLE throw_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');

    db.throwOnMissingNamedParams = true;

    // :extra does not exist in the SQL — should throw
    await expectLater(
      () => db.executeSql(
        'INSERT INTO throw_tbl (id, name) VALUES (:id, :name)',
        nameParams: {'id': 1, 'name': 'Alice', 'extra': 'boom'},
      ),
      throwsA(isA<Exception>()),
    );

    // Verify the row was NOT inserted (exception aborted the bind)
    final reader = await db.executeReader('SELECT COUNT(*) FROM throw_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 0);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('throwOnMissingNamedParams does not throw when all params match', () async {
    final db = await _createTestDb('throw_all_match.db');
    db.throwOnMissingNamedParams = true;

    await db.executeSql('''
      CREATE TABLE match_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');

    // All params exist in the SQL — should succeed regardless of the flag
    await db.executeSql(
      'INSERT INTO match_tbl (id, name) VALUES (:id, :name)',
      nameParams: {'id': 1, 'name': 'Bob'},
    );

    final reader = await db.executeReader('SELECT name FROM match_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'Bob');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('throwOnMissingNamedParams can be toggled at runtime', () async {
    final db = await _createTestDb('toggle_throw.db');

    await db.executeSql('''
      CREATE TABLE toggle_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');

    // Default: off — extra params silently skipped
    await db.executeSql(
      'INSERT INTO toggle_tbl (id, name) VALUES (:id, :name)',
      nameParams: {'id': 1, 'name': 'first', 'extra': 'ok'},
    );

    // Turn on — extra params should throw
    db.throwOnMissingNamedParams = true;
    await expectLater(
      () => db.executeSql(
        'INSERT INTO toggle_tbl (id, name) VALUES (:id, :name)',
        nameParams: {'id': 2, 'name': 'second', 'extra': 'boom'},
      ),
      throwsA(isA<Exception>()),
    );

    // Turn back off — extra params silently skipped again
    db.throwOnMissingNamedParams = false;
    await db.executeSql(
      'INSERT INTO toggle_tbl (id, name) VALUES (:id, :name)',
      nameParams: {'id': 3, 'name': 'third', 'extra': 'ok'},
    );

    // Verify rows 1 and 3 exist (row 2 was never inserted due to the throw)
    final reader = await db.executeReader('SELECT name FROM toggle_tbl ORDER BY id');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'first');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'third');
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // getContent
  // ──────────────────────────────────────────────────────────────────────

  test('getContent returns database file bytes', () async {
    final db = await _createTestDb('content_test.db');

    await db.executeSql('''
      CREATE TABLE content_tbl (id INTEGER PRIMARY KEY)
    ''');

    final content = await db.getContent();
    expect(content, isNotEmpty);
    // SQLite files start with "SQLite format 3\0"
    expect(String.fromCharCodes(content.sublist(0, 15)), 'SQLite format 3');

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // attachDb with openDb: false
  // ──────────────────────────────────────────────────────────────────────

  test('attachDb with openDb false does not open the database', () async {
    // Create source DB
    final sourceDb = await _createTestDb('attach_src.db');
    await sourceDb.executeSql('CREATE TABLE t (id INTEGER PRIMARY KEY)');
    final bytes = await sourceDb.getContent();
    await sourceDb.closeDb();

    // Attach into new DB without opening
    final targetDb = await DbasSqlite.getInstance(dbName: 'attach_no_open.db');
    final result = await targetDb.attachDb(bytes, openDb: false);

    expect(result.isOpened(), isFalse);
    expect(await result.databaseExists(), isTrue);

    // Clean up
    await result.dropDb();
    await sourceDb.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // dropDb on non-existent database
  // ──────────────────────────────────────────────────────────────────────

  test('dropDb on non-existent database does nothing', () async {
    final db = await DbasSqlite.getInstance(dbName: 'nonexistent.db');
    // Should not throw
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // executeSql returns affected rows
  // ──────────────────────────────────────────────────────────────────────

  test('executeSql returns affected rows count', () async {
    final db = await _createTestDb('affected_rows.db');

    await db.executeSql('''
      CREATE TABLE ar_test (
        id INTEGER PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.executeSql("INSERT INTO ar_test (id, value) VALUES (1, 'a')");
    await db.executeSql("INSERT INTO ar_test (id, value) VALUES (2, 'b')");
    await db.executeSql("INSERT INTO ar_test (id, value) VALUES (3, 'c')");

    final updated = await db.executeSql("UPDATE ar_test SET value = 'x' WHERE id <= 2");
    expect(updated, 2);

    final deleted = await db.executeSql("DELETE FROM ar_test WHERE id = 3");
    expect(deleted, 1);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // readRow auto-closes reader when done
  // ──────────────────────────────────────────────────────────────────────

  test('readRow auto-closes reader when no more rows', () async {
    final db = await _createTestDb('auto_close.db');

    await db.executeSql('CREATE TABLE ac_test (id INTEGER PRIMARY KEY)');
    await db.executeSql("INSERT INTO ac_test (id) VALUES (1)");

    final reader = await db.executeReader('SELECT id FROM ac_test');

    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);

    // readRow returns false and auto-closes — subsequent query should work
    expect(await reader.readRow(), isFalse);

    // Verify we can immediately run another query (reader was properly closed)
    final reader2 = await db.executeReader('SELECT id FROM ac_test');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnInt(0), 1);
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Multiple column types in the same row
  // ──────────────────────────────────────────────────────────────────────

  test('All column types in a single query', () async {
    final db = await _createTestDb('all_types.db');

    await db.executeSql('''
      CREATE TABLE all_types (
        int_col INTEGER,
        real_col REAL,
        text_col TEXT,
        blob_col BLOB,
        null_col TEXT
      )
    ''');

    final blob = Uint8List.fromList([10, 20, 30]);
    await db.executeSql(
      'INSERT INTO all_types (int_col, real_col, text_col, blob_col, null_col) VALUES (?, ?, ?, ?, ?)',
      params: [42, 2.718, 'euler', blob, null],
    );

    final reader = await db.executeReader('SELECT int_col, real_col, text_col, blob_col, null_col FROM all_types');
    expect(await reader.readRow(), isTrue);

    expect(reader.getColumnType(0), SqliteColumnType.integer);
    expect(reader.getColumnType(1), SqliteColumnType.double);
    expect(reader.getColumnType(2), SqliteColumnType.text);
    expect(reader.getColumnType(3), SqliteColumnType.blob);
    expect(reader.getColumnType(4), SqliteColumnType.nullType);

    expect(reader.getColumnInt(0), 42);
    expect(reader.getColumnDouble(1), closeTo(2.718, 0.001));
    expect(reader.getColumnText(2), 'euler');
    expect(reader.getColumnBlob(3).sublist(0, blob.length), blob);
    expect(reader.isColumnNull(4), isTrue);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // getColumnEnum throws on out-of-range index
  // ──────────────────────────────────────────────────────────────────────

  test('getColumnEnum throws ArgumentError for invalid enum index', () async {
    final db = await _createTestDb('enum_error.db');

    await db.executeSql('CREATE TABLE enum_err (id INTEGER PRIMARY KEY, val INTEGER)');
    await db.executeSql('INSERT INTO enum_err (id, val) VALUES (1, 99)');

    final reader = await db.executeReader('SELECT val FROM enum_err WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    expect(
      () => reader.getColumnEnum(0, TestStatus.values),
      throwsA(isA<ArgumentError>()),
    );

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Named params bind with Decimal and bool
  // ──────────────────────────────────────────────────────────────────────

  test('Named params with Decimal and bool types', () async {
    final db = await _createTestDb('named_types.db');

    await db.executeSql('''
      CREATE TABLE named_types (
        id INTEGER PRIMARY KEY,
        amount REAL,
        active INTEGER
      )
    ''');

    await db.executeSql(
      'INSERT INTO named_types (id, amount, active) VALUES (:id, :amount, :active)',
      nameParams: {
        ':id': 1,
        ':amount': Decimal.parse('99.99'),
        ':active': true,
      },
    );

    final reader = await db.executeReader('SELECT amount, active FROM named_types WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    expect(reader.getColumnDecimal(0).toDouble(), closeTo(99.99, 0.01));
    expect(reader.getColumnBool(1), isTrue);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Named params bind with Blob and Enum
  // ──────────────────────────────────────────────────────────────────────

  test('Named params with Blob and Enum types', () async {
    final db = await _createTestDb('named_blob_enum.db');

    await db.executeSql('''
      CREATE TABLE named_be (
        id INTEGER PRIMARY KEY,
        data BLOB,
        status INTEGER
      )
    ''');

    final blob = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
    await db.executeSql(
      'INSERT INTO named_be (id, data, status) VALUES (:id, :data, :status)',
      nameParams: {
        ':id': 1,
        ':data': blob,
        ':status': TestStatus.inactive,
      },
    );

    final reader = await db.executeReader('SELECT data, status FROM named_be WHERE id = 1');
    expect(await reader.readRow(), isTrue);

    expect(reader.getColumnBlob(0).sublist(0, blob.length), blob);
    expect(reader.getColumnEnum(1, TestStatus.values), TestStatus.inactive);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Multiple databases open simultaneously
  // ──────────────────────────────────────────────────────────────────────

  test('Multiple databases can be open at the same time', () async {
    final db1 = await _createTestDb('multi_1.db');
    final db2 = await _createTestDb('multi_2.db');

    await db1.executeSql('CREATE TABLE t1 (id INTEGER PRIMARY KEY, val TEXT)');
    await db2.executeSql('CREATE TABLE t2 (id INTEGER PRIMARY KEY, val TEXT)');

    await db1.executeSql("INSERT INTO t1 (id, val) VALUES (1, 'from_db1')");
    await db2.executeSql("INSERT INTO t2 (id, val) VALUES (1, 'from_db2')");

    final reader1 = await db1.executeReader('SELECT val FROM t1 WHERE id = 1');
    expect(await reader1.readRow(), isTrue);
    expect(reader1.getColumnText(0), 'from_db1');
    await reader1.close();

    final reader2 = await db2.executeReader('SELECT val FROM t2 WHERE id = 1');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'from_db2');
    await reader2.close();

    await db1.closeDb();
    await db1.dropDb();
    await db2.closeDb();
    await db2.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Empty result set
  // ──────────────────────────────────────────────────────────────────────

  test('Empty result set returns false on first readRow', () async {
    final db = await _createTestDb('empty_result.db');

    await db.executeSql('CREATE TABLE empty_tbl (id INTEGER PRIMARY KEY)');

    final reader = await db.executeReader('SELECT id FROM empty_tbl');
    expect(await reader.readRow(), isFalse);

    // Should be able to run another query immediately
    final reader2 = await db.executeReader('SELECT id FROM empty_tbl');
    expect(await reader2.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Unicode / special characters
  // ──────────────────────────────────────────────────────────────────────

  test('Unicode and special characters in text', () async {
    final db = await _createTestDb('unicode_test.db');

    await db.executeSql('CREATE TABLE unicode_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    final testStrings = [
      'Hello 世界',
      'Ação não está à toa',
      'Ümlauts: äöü ÄÖÜ ß',
      '🚀🎉💡',
      "Quotes: 'single' and \"double\"",
      'Line\nbreak\ttab',
    ];

    for (int i = 0; i < testStrings.length; i++) {
      await db.executeSql(
        'INSERT INTO unicode_tbl (id, val) VALUES (?, ?)',
        params: [i + 1, testStrings[i]],
      );
    }

    final reader = await db.executeReader('SELECT val FROM unicode_tbl ORDER BY id');
    for (final expected in testStrings) {
      expect(await reader.readRow(), isTrue);
      expect(reader.getColumnText(0), expected);
    }
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: beginTransaction + commit
  // ──────────────────────────────────────────────────────────────────────

  test('beginTransaction and commit persists data', () async {
    final db = await _createTestDb('txn_commit.db');

    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await db.beginTransaction();
    expect(db.isInTransaction, isTrue);

    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (1, 'a')");
    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (2, 'b')");
    await db.commit();
    expect(db.isInTransaction, isFalse);

    final reader = await db.executeReader('SELECT val FROM txn_tbl ORDER BY id');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'a');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'b');
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: beginTransaction + rollback
  // ──────────────────────────────────────────────────────────────────────

  test('beginTransaction and rollback discards data', () async {
    final db = await _createTestDb('txn_rollback.db');

    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await db.beginTransaction();
    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (1, 'a')");
    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (2, 'b')");
    await db.rollback();
    expect(db.isInTransaction, isFalse);

    final reader = await db.executeReader('SELECT COUNT(*) FROM txn_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 0);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: transaction() helper commits on success
  // ──────────────────────────────────────────────────────────────────────

  test('transaction() helper commits on success', () async {
    final db = await _createTestDb('txn_helper_commit.db');

    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await db.transaction((db) async {
      await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (1, 'x')");
      await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (2, 'y')");
    });

    expect(db.isInTransaction, isFalse);

    final reader = await db.executeReader('SELECT val FROM txn_tbl ORDER BY id');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'x');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'y');
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: transaction() helper rolls back on error
  // ──────────────────────────────────────────────────────────────────────

  test('transaction() helper rolls back on error and rethrows', () async {
    final db = await _createTestDb('txn_helper_rollback.db');

    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    // Insert one row outside the transaction
    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (1, 'before')");

    await expectLater(
      () => db.transaction((db) async {
        await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (2, 'inside')");
        throw Exception('Simulated error');
      }),
      throwsA(isA<Exception>()),
    );

    expect(db.isInTransaction, isFalse);

    // Only the row inserted before the transaction should exist
    final reader = await db.executeReader('SELECT COUNT(*) FROM txn_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    final reader2 = await db.executeReader('SELECT val FROM txn_tbl WHERE id = 1');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'before');
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: idempotent behavior
  // ──────────────────────────────────────────────────────────────────────

  test('beginTransaction is idempotent when already in transaction', () async {
    final db = await _createTestDb('txn_idempotent_begin.db');

    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY)');

    await db.beginTransaction();
    expect(db.isInTransaction, isTrue);

    // Calling again should not throw
    await db.beginTransaction();
    expect(db.isInTransaction, isTrue);

    await db.commit();
    expect(db.isInTransaction, isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  test('commit is idempotent when no transaction is active', () async {
    final db = await _createTestDb('txn_idempotent_commit.db');

    expect(db.isInTransaction, isFalse);

    // Should not throw
    await db.commit();
    expect(db.isInTransaction, isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  test('rollback is idempotent when no transaction is active', () async {
    final db = await _createTestDb('txn_idempotent_rollback.db');

    expect(db.isInTransaction, isFalse);

    // Should not throw
    await db.rollback();
    expect(db.isInTransaction, isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: StateError when DB not opened
  // ──────────────────────────────────────────────────────────────────────

  test('beginTransaction throws StateError when database is not opened', () async {
    final db = await DbasSqlite.getInstance(dbName: 'txn_not_opened.db');
    expect(
      () => db.beginTransaction(),
      throwsA(isA<StateError>()),
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: transaction() throws StateError when nested
  // ──────────────────────────────────────────────────────────────────────

  test('transaction() throws StateError when already in transaction', () async {
    final db = await _createTestDb('txn_nested.db');

    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY)');

    await db.beginTransaction();
    expect(db.isInTransaction, isTrue);

    await expectLater(
      () => db.transaction((db) async {
        await db.executeSql("INSERT INTO txn_tbl (id) VALUES (1)");
      }),
      throwsA(isA<StateError>()),
    );

    // Original transaction should still be active
    expect(db.isInTransaction, isTrue);
    await db.rollback();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: closeDb auto-rollback
  // ──────────────────────────────────────────────────────────────────────

  test('closeDb automatically rolls back pending transaction', () async {
    final db = await _createTestDb('txn_close_rollback.db');

    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (1, 'committed')");

    await db.beginTransaction();
    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (2, 'uncommitted')");
    expect(db.isInTransaction, isTrue);

    // closeDb should rollback the pending transaction
    await db.closeDb();
    expect(db.isOpened(), isFalse);

    // Reopen and verify only committed data exists
    final db2 = await DbasSqlite.getInstance(dbName: 'txn_close_rollback.db');
    await db2.openDb();

    final reader = await db2.executeReader('SELECT COUNT(*) FROM txn_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    final reader2 = await db2.executeReader('SELECT val FROM txn_tbl WHERE id = 1');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'committed');
    await reader2.close();

    await db2.closeDb();
    await db2.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction: isInTransaction state tracking
  // ──────────────────────────────────────────────────────────────────────

  test('isInTransaction tracks state correctly through lifecycle', () async {
    final db = await _createTestDb('txn_state.db');

    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY)');

    expect(db.isInTransaction, isFalse);

    await db.beginTransaction();
    expect(db.isInTransaction, isTrue);

    await db.commit();
    expect(db.isInTransaction, isFalse);

    await db.beginTransaction();
    expect(db.isInTransaction, isTrue);

    await db.rollback();
    expect(db.isInTransaction, isFalse);

    await db.transaction((db) async {
      expect(db.isInTransaction, isTrue);
    });
    expect(db.isInTransaction, isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Pool: transparent pooling
  // ──────────────────────────────────────────────────────────────────────

  test('openDb with default pool works transparently', () async {
    final db = await _createTestDb('pool_default.db', readerPoolSize: 4);

    await db.executeSql('CREATE TABLE pool_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO pool_tbl (id, val) VALUES (1, 'pooled')");

    final reader = await db.executeReader('SELECT val FROM pool_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'pooled');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('openDb with readerPoolSize=0 uses single connection', () async {
    final db = await DbasSqlite.getInstance(dbName: 'pool_zero.db');
    await db.dropDb();

    await db.openDb(readerPoolSize: 0);
    expect(db.isOpened(), isTrue);

    await db.executeSql('CREATE TABLE single_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO single_tbl (id, val) VALUES (1, 'single')");

    final reader = await db.executeReader('SELECT val FROM single_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'single');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // streamCopyDb
  // ──────────────────────────────────────────────────────────────────────

  test('streamCopyDb copies database to new name', () async {
    final db = await _createTestDb('copy_src.db');

    await db.executeSql('CREATE TABLE copy_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO copy_tbl (id, val) VALUES (1, 'copied')");
    await db.closeDb();

    // Re-open to ensure WAL is flushed
    final srcDb = await DbasSqlite.getInstance(dbName: 'copy_src.db');
    await srcDb.openDb();
    await srcDb.streamCopyDb('copy_dest.db');
    await srcDb.closeDb();

    // Open the copy and verify data
    final destDb = await DbasSqlite.getInstance(dbName: 'copy_dest.db');
    await destDb.openDb();
    expect(destDb.isOpened(), isTrue);

    final reader = await destDb.executeReader('SELECT val FROM copy_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'copied');
    await reader.close();

    await destDb.closeDb();
    await destDb.dropDb();
    await srcDb.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // attachStreamDb
  // ──────────────────────────────────────────────────────────────────────

  test('attachStreamDb writes database from byte stream', () async {
    // Create source DB
    final srcDb = await _createTestDb('stream_src.db');
    await srcDb.executeSql('CREATE TABLE stream_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await srcDb.executeSql("INSERT INTO stream_tbl (id, val) VALUES (1, 'streamed')");
    final srcPath = await srcDb.getAppDatabasePath();
    await srcDb.closeDb();

    // Read source as a stream
    final stream = File(srcPath).openRead();

    // Attach via stream
    final destDb = await DbasSqlite.getInstance(dbName: 'stream_dest.db');
    final result = await destDb.attachStreamDb(stream);

    expect(result.isOpened(), isTrue);

    final reader = await result.executeReader('SELECT val FROM stream_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'streamed');
    await reader.close();

    await result.closeDb();
    await result.dropDb();
    await srcDb.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // closeReader idempotent
  // ──────────────────────────────────────────────────────────────────────

  test('closeReader is safe to call multiple times', () async {
    final db = await _createTestDb('close_reader_idem.db');

    await db.executeSql('CREATE TABLE cr_tbl (id INTEGER PRIMARY KEY)');
    await db.executeSql('INSERT INTO cr_tbl (id) VALUES (1)');

    final reader = await db.executeReader('SELECT id FROM cr_tbl');
    expect(await reader.readRow(), isTrue);

    // Close twice — should not throw
    await reader.close();
    await reader.close();

    // Should still be able to run queries after
    final reader2 = await db.executeReader('SELECT id FROM cr_tbl');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnInt(0), 1);
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // executeReader within a transaction
  // ──────────────────────────────────────────────────────────────────────

  test('executeReader works within a transaction', () async {
    final db = await _createTestDb('reader_in_txn.db');

    await db.executeSql('CREATE TABLE rit_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO rit_tbl (id, val) VALUES (1, 'before')");

    await db.beginTransaction();

    await db.executeSql("INSERT INTO rit_tbl (id, val) VALUES (2, 'during')");

    // Read within the same transaction — should see uncommitted data
    final reader = await db.executeReader('SELECT val FROM rit_tbl ORDER BY id');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'before');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'during');
    expect(await reader.readRow(), isFalse);

    await db.commit();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Sequential reader then writer
  // ──────────────────────────────────────────────────────────────────────

  test('sequential reader then writer works correctly', () async {
    final db = await _createTestDb('seq_rw.db');

    await db.executeSql('CREATE TABLE seq_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO seq_tbl (id, val) VALUES (1, 'a')");

    // Reader cycle
    final reader = await db.executeReader('SELECT val FROM seq_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'a');
    await reader.close();

    // Writer after reader
    await db.executeSql("UPDATE seq_tbl SET val = 'b' WHERE id = 1");

    // Verify write took effect
    final reader2 = await db.executeReader('SELECT val FROM seq_tbl WHERE id = 1');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'b');
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Thread safety: concurrent writes serialized
  // ──────────────────────────────────────────────────────────────────────

  test('concurrent executeSql calls are serialized and all succeed', () async {
    final db = await _createTestDb('concurrent_writes.db');

    await db.executeSql('CREATE TABLE cw_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    // Launch multiple writes concurrently
    await Future.wait([
      db.executeSql("INSERT INTO cw_tbl (id, val) VALUES (1, 'a')"),
      db.executeSql("INSERT INTO cw_tbl (id, val) VALUES (2, 'b')"),
      db.executeSql("INSERT INTO cw_tbl (id, val) VALUES (3, 'c')"),
    ]);

    // All three rows should exist
    final reader = await db.executeReader('SELECT COUNT(*) FROM cw_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 3);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Thread safety: writer lock held during transaction
  // ──────────────────────────────────────────────────────────────────────

  test('concurrent transactions are serialized via writer lock', () async {
    final db = await _createTestDb('txn_lock.db');

    await db.executeSql('CREATE TABLE tl_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    final executionOrder = <int>[];

    // Two transactions fired concurrently — must be serialized
    await Future.wait([
      db.transaction((db) async {
        await db.executeSql("INSERT INTO tl_tbl (id, val) VALUES (1, 'a')");
        executionOrder.add(1);
      }),
      db.transaction((db) async {
        await db.executeSql("INSERT INTO tl_tbl (id, val) VALUES (2, 'b')");
        executionOrder.add(2);
      }),
    ]);

    // Both should have completed
    expect(executionOrder.length, 2);
    expect(executionOrder.toSet(), {1, 2});

    // Both rows should exist
    final reader = await db.executeReader('SELECT COUNT(*) FROM tl_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 2);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Thread safety: reader does not block writer (pool)
  // ──────────────────────────────────────────────────────────────────────

  test('executeReader and executeSql do not deadlock', () async {
    final db = await _createTestDb('rw_nodeadlock.db');

    await db.executeSql('CREATE TABLE rw_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO rw_tbl (id, val) VALUES (1, 'initial')");

    // Start a reader
    final reader = await db.executeReader('SELECT val FROM rw_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'initial');
    await reader.close();

    // Writer should not be blocked
    await db.executeSql("UPDATE rw_tbl SET val = 'updated' WHERE id = 1");

    final reader2 = await db.executeReader('SELECT val FROM rw_tbl WHERE id = 1');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'updated');
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Thread safety: closeDb while operations pending
  // ──────────────────────────────────────────────────────────────────────

  test('closeDb cleans up state and subsequent operations throw', () async {
    final db = await _createTestDb('close_state.db');

    await db.executeSql('CREATE TABLE cs_tbl (id INTEGER PRIMARY KEY)');

    await db.closeDb();

    expect(db.isOpened(), isFalse);
    expect(db.isInTransaction, isFalse);

    expect(
      () => db.executeSql('SELECT 1'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => db.executeReader('SELECT 1'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => db.beginTransaction(),
      throwsA(isA<StateError>()),
    );

    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Multiple sequential reader sessions
  // ──────────────────────────────────────────────────────────────────────

  test('multiple sequential executeReader sessions work correctly', () async {
    final db = await _createTestDb('multi_reader.db');

    await db.executeSql('CREATE TABLE mr_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO mr_tbl (id, val) VALUES (1, 'a')");
    await db.executeSql("INSERT INTO mr_tbl (id, val) VALUES (2, 'b')");

    // First reader session
    final reader = await db.executeReader('SELECT val FROM mr_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'a');
    await reader.close();

    // Second reader session
    final reader2 = await db.executeReader('SELECT val FROM mr_tbl WHERE id = 2');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'b');
    await reader2.close();

    // Third session — full iteration
    final reader3 = await db.executeReader('SELECT val FROM mr_tbl ORDER BY id');
    final vals = <String>[];
    while (await reader3.readRow()) {
      vals.add(reader3.getColumnText(0));
    }
    expect(vals, ['a', 'b']);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Transaction with reads interleaved with writes
  // ──────────────────────────────────────────────────────────────────────

  test('transaction with interleaved reads and writes', () async {
    final db = await _createTestDb('txn_interleave.db');

    await db.executeSql('CREATE TABLE ti_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await db.transaction((db) async {
      await db.executeSql("INSERT INTO ti_tbl (id, val) VALUES (1, 'one')");

      // Read back within same transaction
      final reader = await db.executeReader('SELECT COUNT(*) FROM ti_tbl');
      expect(await reader.readRow(), isTrue);
      expect(reader.getColumnInt(0), 1);
      await reader.close();

      await db.executeSql("INSERT INTO ti_tbl (id, val) VALUES (2, 'two')");

      // Read again — should see both
      final reader2 = await db.executeReader('SELECT COUNT(*) FROM ti_tbl');
      expect(await reader2.readRow(), isTrue);
      expect(reader2.getColumnInt(0), 2);
      await reader2.close();
    });

    // Verify after commit
    final reader = await db.executeReader('SELECT val FROM ti_tbl ORDER BY id');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'one');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'two');
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Prepare failure: recovery and error reporting
  // ──────────────────────────────────────────────────────────────────────

  test('executeSql prepare failure includes error code and recovers', () async {
    final db = await _createTestDb('prepare_fail_exec.db');
    await db.executeSql('CREATE TABLE pfe_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    // Trigger prepare failure (references non-existent table)
    try {
      await db.executeSql('SELECT * FROM nonexistent_table');
      fail('Should have thrown');
    } on Exception catch (e) {
      expect(e.toString(), contains('(1)'));
    }

    // Connection must still be usable — stmt was properly finalized
    await db.executeSql("INSERT INTO pfe_tbl (id, val) VALUES (1, 'ok')");
    final reader = await db.executeReader('SELECT val FROM pfe_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'ok');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('executeReader prepare failure includes error code and recovers', () async {
    final db = await _createTestDb('prepare_fail_reader.db');
    await db.executeSql('CREATE TABLE pfr_tbl (id INTEGER PRIMARY KEY)');
    await db.executeSql('INSERT INTO pfr_tbl (id) VALUES (1)');

    try {
      await db.executeReader('SELECT * FROM nonexistent_table');
      fail('Should have thrown');
    } on Exception catch (e) {
      expect(e.toString(), contains('(1)'));
    }

    // Reader must still work — lock/pool was properly released
    final reader = await db.executeReader('SELECT id FROM pfr_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('executeSql prepare failure within transaction keeps transaction intact', () async {
    final db = await _createTestDb('prepare_fail_txn.db');
    await db.executeSql('CREATE TABLE pft_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await db.beginTransaction();
    await db.executeSql("INSERT INTO pft_tbl (id, val) VALUES (1, 'one')");

    // Prepare failure mid-transaction
    await expectLater(
      () => db.executeSql('SELECT * FROM nonexistent_table'),
      throwsA(isA<Exception>()),
    );

    // Transaction should still be active and usable
    expect(db.isInTransaction, isTrue);
    await db.executeSql("INSERT INTO pft_tbl (id, val) VALUES (2, 'two')");
    await db.commit();

    // Both rows should be committed
    final reader = await db.executeReader('SELECT COUNT(*) FROM pft_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 2);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Bind failure: recovery
  // ──────────────────────────────────────────────────────────────────────

  test('executeSql bind failure recovers and connection remains usable', () async {
    final db = await _createTestDb('bind_fail_exec.db');
    await db.executeSql('CREATE TABLE bfe_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    // Bind 2 params to a statement with 1 placeholder — index 2 is out of range
    // sqlite3_bind returns SQLITE_RANGE (25), now caught by != _sqliteOk
    await expectLater(
      () => db.executeSql(
        'INSERT INTO bfe_tbl (id) VALUES (?)',
        params: [1, 'extra'],
      ),
      throwsA(isA<Exception>()),
    );

    // Connection must still work — stmt was finalized by the finally block
    await db.executeSql("INSERT INTO bfe_tbl (id, val) VALUES (1, 'ok')");
    final reader = await db.executeReader('SELECT val FROM bfe_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'ok');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('executeReader bind failure recovers and reader is released', () async {
    final db = await _createTestDb('bind_fail_reader.db', readerPoolSize: 2);
    await db.executeSql('CREATE TABLE bfr_tbl (id INTEGER PRIMARY KEY)');
    await db.executeSql('INSERT INTO bfr_tbl (id) VALUES (1)');

    await expectLater(
      () => db.executeReader(
        'SELECT * FROM bfr_tbl WHERE id = ?',
        params: [1, 'extra'],
      ),
      throwsA(isA<Exception>()),
    );

    // Pool reader must be released — subsequent reader should work
    final reader = await db.executeReader('SELECT id FROM bfr_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Multiple temp tables in a single transaction (merge scenario)
  // ──────────────────────────────────────────────────────────────────────

  test('multiple temp table DDL+DML in transaction does not corrupt stmt', () async {
    final db = await _createTestDb('temp_tbl_txn.db');

    await db.executeSql('''
      CREATE TABLE src_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id INTEGER
      )
    ''');
    await db.executeSql("INSERT INTO src_tbl (id, name, parent_id) VALUES (1, 'root', NULL)");
    await db.executeSql("INSERT INTO src_tbl (id, name, parent_id) VALUES (2, 'child', 1)");
    await db.executeSql("INSERT INTO src_tbl (id, name, parent_id) VALUES (3, 'grandchild', 2)");

    await db.transaction((db) async {
      // First temp table — staging data (like merge temp table)
      await db.executeSql('CREATE TEMP TABLE __temp_merge__ (id INTEGER, name TEXT)');
      await db.executeSql('INSERT INTO __temp_merge__ SELECT id, name FROM src_tbl');

      final reader = await db.executeReader('SELECT COUNT(*) FROM __temp_merge__');
      expect(await reader.readRow(), isTrue);
      expect(reader.getColumnInt(0), 3);
      await reader.close();

      // Second temp table — hierarchy resolution (self-recursive FK)
      await db.executeSql('CREATE TEMP TABLE __temp_hier__ (id INTEGER, parent_id INTEGER)');
      await db.executeSql('INSERT INTO __temp_hier__ SELECT id, parent_id FROM src_tbl WHERE parent_id IS NOT NULL');

      final reader2 = await db.executeReader('SELECT COUNT(*) FROM __temp_hier__');
      expect(await reader2.readRow(), isTrue);
      expect(reader2.getColumnInt(0), 2);
      await reader2.close();

      // Cross-temp-table operation
      await db.executeSql('''
        INSERT INTO src_tbl (id, name, parent_id)
        SELECT 4, 'merged', h.parent_id
        FROM __temp_hier__ h
        WHERE h.id = 3
      ''');

      // Clean up temp tables
      await db.executeSql('DROP TABLE __temp_merge__');
      await db.executeSql('DROP TABLE __temp_hier__');
    });

    // Verify final state
    final reader3 = await db.executeReader('SELECT COUNT(*) FROM src_tbl');
    expect(await reader3.readRow(), isTrue);
    expect(reader3.getColumnInt(0), 4);
    await reader3.close();

    final reader4 = await db.executeReader('SELECT name, parent_id FROM src_tbl WHERE id = 4');
    expect(await reader4.readRow(), isTrue);
    expect(reader4.getColumnText(0), 'merged');
    expect(reader4.getColumnInt(1), 2);
    await reader4.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('rapid sequential executeSql in transaction all succeed', () async {
    final db = await _createTestDb('rapid_txn.db');
    await db.executeSql('CREATE TABLE rt_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await db.transaction((db) async {
      for (int i = 1; i <= 50; i++) {
        await db.executeSql(
          'INSERT INTO rt_tbl (id, val) VALUES (?, ?)',
          params: [i, 'row_$i'],
        );
      }
    });

    final reader = await db.executeReader('SELECT COUNT(*) FROM rt_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 50);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Pool: concurrent reads and writes with pool active
  // ──────────────────────────────────────────────────────────────────────

  test('concurrent writes with pool are serialized and all succeed', () async {
    final db = await _createTestDb('pool_conc_writes.db', readerPoolSize: 4);

    await db.executeSql('CREATE TABLE pcw_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await Future.wait([
      db.executeSql("INSERT INTO pcw_tbl (id, val) VALUES (1, 'a')"),
      db.executeSql("INSERT INTO pcw_tbl (id, val) VALUES (2, 'b')"),
      db.executeSql("INSERT INTO pcw_tbl (id, val) VALUES (3, 'c')"),
    ]);

    final reader = await db.executeReader('SELECT COUNT(*) FROM pcw_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 3);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: sequential reader then writer works correctly', () async {
    final db = await _createTestDb('pool_seq_rw.db', readerPoolSize: 2);

    await db.executeSql('CREATE TABLE psrw_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO psrw_tbl (id, val) VALUES (1, 'original')");

    // Reader cycle (uses pool reader)
    final reader = await db.executeReader('SELECT val FROM psrw_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'original');
    await reader.close();

    // Writer after reader
    await db.executeSql("UPDATE psrw_tbl SET val = 'updated' WHERE id = 1");

    // Verify write took effect
    final reader2 = await db.executeReader('SELECT val FROM psrw_tbl WHERE id = 1');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'updated');
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: getLastInsertedId works after executeSql', () async {
    final db = await _createTestDb('pool_last_id.db', readerPoolSize: 2);

    await db.executeSql('CREATE TABLE pli_tbl (id INTEGER PRIMARY KEY AUTOINCREMENT, val TEXT)');
    await db.executeSql("INSERT INTO pli_tbl (val) VALUES ('first')");

    final lastId = db.getLastInsertedId();
    expect(lastId, greaterThan(0));

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: transaction with pool-enabled database', () async {
    final db = await _createTestDb('pool_txn.db', readerPoolSize: 4);

    await db.executeSql('CREATE TABLE pt_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO pt_tbl (id, val) VALUES (1, 'before')");

    await db.beginTransaction();

    await db.executeSql("INSERT INTO pt_tbl (id, val) VALUES (2, 'during')");

    // Read within the same transaction — should see uncommitted data
    final reader = await db.executeReader('SELECT val FROM pt_tbl ORDER BY id');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'before');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'during');
    expect(await reader.readRow(), isFalse);

    await db.commit();

    // Verify committed data
    final reader2 = await db.executeReader('SELECT COUNT(*) FROM pt_tbl');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnInt(0), 2);
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: concurrent transactions are serialized', () async {
    final db = await _createTestDb('pool_conc_txn.db', readerPoolSize: 2);

    await db.executeSql('CREATE TABLE pct_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    final executionOrder = <int>[];

    await Future.wait([
      db.transaction((db) async {
        await db.executeSql("INSERT INTO pct_tbl (id, val) VALUES (1, 'a')");
        executionOrder.add(1);
      }),
      db.transaction((db) async {
        await db.executeSql("INSERT INTO pct_tbl (id, val) VALUES (2, 'b')");
        executionOrder.add(2);
      }),
    ]);

    expect(executionOrder.length, 2);
    expect(executionOrder.toSet(), {1, 2});

    final reader = await db.executeReader('SELECT COUNT(*) FROM pct_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 2);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: reader fallback to writer when all pool readers busy', () async {
    // Use pool with 1 reader — holding it should trigger writer fallback
    final db = await _createTestDb('pool_fallback.db', readerPoolSize: 1);

    await db.executeSql('CREATE TABLE pf_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO pf_tbl (id, val) VALUES (1, 'test')");

    // This should work even with small pool
    final reader = await db.executeReader('SELECT val FROM pf_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'test');
    await reader.close();

    // Subsequent operations should still work
    await db.executeSql("INSERT INTO pf_tbl (id, val) VALUES (2, 'test2')");

    final reader2 = await db.executeReader('SELECT COUNT(*) FROM pf_tbl');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnInt(0), 2);
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: multiple databases work independently', () async {
    final db1 = await _createTestDb('pool_multi_a.db', readerPoolSize: 2);
    final db2 = await _createTestDb('pool_multi_b.db', readerPoolSize: 2);

    await db1.executeSql('CREATE TABLE ma_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db2.executeSql('CREATE TABLE mb_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    // Concurrent operations on different DBs
    await Future.wait([
      db1.executeSql("INSERT INTO ma_tbl (id, val) VALUES (1, 'db1')"),
      db2.executeSql("INSERT INTO mb_tbl (id, val) VALUES (1, 'db2')"),
    ]);

    // Verify each DB independently
    final reader1 = await db1.executeReader('SELECT val FROM ma_tbl WHERE id = 1');
    expect(await reader1.readRow(), isTrue);
    expect(reader1.getColumnText(0), 'db1');
    await reader1.close();

    final reader2 = await db2.executeReader('SELECT val FROM mb_tbl WHERE id = 1');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'db2');
    await reader2.close();

    await db1.closeDb();
    await db1.dropDb();
    await db2.closeDb();
    await db2.dropDb();
  });

  test('pool: prepare failure releases pool slot', () async {
    final db = await _createTestDb('pool_prep_fail.db', readerPoolSize: 2);
    await db.executeSql('CREATE TABLE ppf_tbl (id INTEGER PRIMARY KEY)');

    // Bad SQL should fail and release the pool slot
    await expectLater(
      () => db.executeSql('INSERT INTO nonexistent_tbl VALUES (1)'),
      throwsA(isA<Exception>()),
    );

    // Subsequent operations should still work (slot was released)
    await db.executeSql('INSERT INTO ppf_tbl (id) VALUES (1)');

    final reader = await db.executeReader('SELECT id FROM ppf_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Issue fixes: regression tests
  // ──────────────────────────────────────────────────────────────────────

  test('getColumnDecimal throws FormatException on non-numeric text', () async {
    final db = await _createTestDb('decimal_err.db');
    await db.executeSql("CREATE TABLE d_tbl (id INTEGER PRIMARY KEY, val TEXT)");
    await db.executeSql("INSERT INTO d_tbl (id, val) VALUES (1, 'not_a_number')");

    final reader = await db.executeReader('SELECT val FROM d_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(() => reader.getColumnDecimal(0), throwsFormatException);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('getColumnTime throws FormatException on garbage input', () async {
    final db = await _createTestDb('time_err.db');
    await db.executeSql("CREATE TABLE t_tbl (id INTEGER PRIMARY KEY, val TEXT)");
    await db.executeSql("INSERT INTO t_tbl (id, val) VALUES (1, 'garbage')");

    final reader = await db.executeReader('SELECT val FROM t_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(() => reader.getColumnTime(0), throwsFormatException);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('getColumnTime parses HH:MM format without seconds', () async {
    final db = await _createTestDb('time_hhmm.db');
    await db.executeSql("CREATE TABLE t_tbl (id INTEGER PRIMARY KEY, val TEXT)");
    await db.executeSql("INSERT INTO t_tbl (id, val) VALUES (1, '14:30')");

    final reader = await db.executeReader('SELECT val FROM t_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    final d = reader.getColumnTime(0);
    expect(d.inHours, 14);
    expect(d.inMinutes % 60, 30);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('instance cleanup: dropDb cleans up platform delegates (Issue 7)', () async {
    final db = await _createTestDb('cleanup.db');
    await db.executeSql('CREATE TABLE cl_tbl (id INTEGER PRIMARY KEY)');
    await db.closeDb();
    await db.dropDb();

    // Re-create with same name — should not use stale delegate
    final db2 = await _createTestDb('cleanup.db');
    await db2.executeSql('CREATE TABLE cl_tbl (id INTEGER PRIMARY KEY)');
    await db2.closeDb();
    await db2.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Row cache correctness across pool writer/reader interleaving
  // ──────────────────────────────────────────────────────────────────────

  test('pool: row cache returns reader data after writer executeSql', () async {
    final db = await _createTestDb('cache_interleave.db', readerPoolSize: 2);
    await db.executeSql('CREATE TABLE ci_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO ci_tbl (id, val) VALUES (1, 'alpha')");
    await db.executeSql("INSERT INTO ci_tbl (id, val) VALUES (2, 'beta')");

    // Execute a write (touches writer's readRow path internally)
    await db.executeSql("INSERT INTO ci_tbl (id, val) VALUES (3, 'gamma')");
    final insertedId = db.getLastInsertedId();
    expect(insertedId, 3);

    // Now execute a reader query — should return reader data, not writer cache
    final reader = await db.executeReader('SELECT val FROM ci_tbl ORDER BY id');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'alpha');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'beta');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'gamma');
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Pool exhaustion: reader held open, second read falls back to writer
  // ──────────────────────────────────────────────────────────────────────

  test('pool: second reader falls back to writer when first reader held open', () async {
    final db = await _createTestDb('pool_exhaust.db', readerPoolSize: 1);
    await db.executeSql('CREATE TABLE pe_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO pe_tbl (id, val) VALUES (1, 'first')");
    await db.executeSql("INSERT INTO pe_tbl (id, val) VALUES (2, 'second')");

    // First reader: hold open without closing
    final reader = await db.executeReader('SELECT val FROM pe_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'first');
    // Don't close reader — pool reader is still held

    // Second read operation — should still work (falls back to writer or
    // closePendingReader releases the first reader automatically)
    final reader2 = await db.executeReader('SELECT val FROM pe_tbl WHERE id = 2');
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'second');
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // C pool: open, close, reopen with different pool size
  // ──────────────────────────────────────────────────────────────────────

  test('pool: close and reopen with different pool size', () async {
    final db1 = await _createTestDb('pool_reopen.db', readerPoolSize: 1);
    await db1.executeSql('CREATE TABLE pr_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db1.executeSql("INSERT INTO pr_tbl (id, val) VALUES (1, 'persisted')");
    await db1.closeDb();

    // Reopen with a different pool size
    final db2 = await DbasSqlite.getInstance(dbName: 'pool_reopen.db');
    await db2.openDb(readerPoolSize: 4);

    final reader = await db2.executeReader('SELECT val FROM pr_tbl WHERE id = 1');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'persisted');
    await reader.close();

    await db2.closeDb();
    await db2.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Error propagation from worker isolate
  // ──────────────────────────────────────────────────────────────────────

  test('executeSql with invalid SQL propagates error from worker', () async {
    final db = await _createTestDb('worker_err.db');
    await db.executeSql('CREATE TABLE we_tbl (id INTEGER PRIMARY KEY)');

    // Invalid SQL should propagate error through worker isolate
    await expectLater(
      () => db.executeSql('INVALID SQL THAT DOES NOT PARSE'),
      throwsA(isA<Exception>()),
    );

    // Connection should still be usable after error
    await db.executeSql('INSERT INTO we_tbl (id) VALUES (1)');

    final reader = await db.executeReader('SELECT id FROM we_tbl');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });
}
