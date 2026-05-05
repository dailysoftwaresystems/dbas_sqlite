import 'dart:async';
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

/// One-shot prepare/execute/close — the v2.3.x `db.executeSql(sql, ...)`
/// in a single function call. Used by test sites that need the call
/// to be a single expression (inside `Future.wait`, `() => ...`).
Future<int> _runSql(DbasSqlite db, String sql,
    {List<Object?>? params, Map<String, Object?>? nameParams}) async {
  final s = await db.prepareQuery(sql);
  try {
    return await s.executeSql(params: params, nameParams: nameParams);
  } finally {
    await s.close();
  }
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

    {
      final stmt = await dbasSqlite.prepareQuery('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await dbasSqlite.prepareQuery('INSERT INTO users (name, email) VALUES (:name, :email)');
      try {
        await stmt.executeSql(nameParams: <String, Object?>{
        'name': 'test1',
        'email': 'test1@test.com',
      },);
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await dbasSqlite.prepareQuery('INSERT INTO users (name, email) VALUES (?, ?)');
      try {
        await stmt.executeSql(params: ['test2', 'test2@test.com'],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await dbasSqlite.prepareQuery("SELECT name, email FROM users where id > :id")).executeReader(params: [0]);
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
    {
      final stmt = await testDbasSqlite.prepareQuery('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
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
    {
      final stmt = await dbasSqlite.prepareQuery('''
      INSERT INTO users (name, email, created_at) values (:name, :email, :created_at)
    ''');
      try {
        await stmt.executeSql(nameParams: params);
      } finally {
        await stmt.close();
      }
    }

    final selectParams = {
      ':id': 0,
      ':name': 'random-bla',
    };
    final reader = await (await dbasSqlite.prepareQuery("SELECT * FROM users WHERE id > :id AND name != :name")).executeReader(nameParams: selectParams);
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
      () => db.prepareQuery('SELECT 1'),
      throwsA(isA<StateError>()),
    );
  });

  test('executeReader throws StateError when database is not opened', () async {
    final db = await DbasSqlite.getInstance(dbName: 'not_opened_reader.db');
    expect(
      () => db.prepareQuery('SELECT 1'),
      throwsA(isA<StateError>()),
    );
  });

  test('executeSql throws Exception on invalid SQL', () async {
    final db = await _createTestDb('invalid_sql.db');

    await expectLater(
      () => _runSql(db, 'INVALID SQL STATEMENT'),
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final insertStmt =
        await db.prepareQuery('INSERT INTO items (name) VALUES (?)');
    await insertStmt.executeSql(params: ['first']);
    expect(insertStmt.getLastInsertedId(), 1);

    await insertStmt.executeSql(params: ['second']);
    expect(insertStmt.getLastInsertedId(), 2);

    await insertStmt.executeSql(params: ['third']);
    expect(insertStmt.getLastInsertedId(), 3);
    await insertStmt.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // getColumnName
  // ──────────────────────────────────────────────────────────────────────

  test('getColumnName returns correct column names', () async {
    final db = await _createTestDb('col_name.db');

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        product_name TEXT,
        price REAL
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO products (id, product_name, price) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, 'Widget', 9.99],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT id, product_name, price FROM products')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE nullable_test (
        id INTEGER PRIMARY KEY,
        text_col TEXT,
        int_col INTEGER,
        real_col REAL,
        blob_col BLOB
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Insert row with all NULLs (except id)
    {
      final stmt = await db.prepareQuery('INSERT INTO nullable_test (id, text_col, int_col, real_col, blob_col) VALUES (?, ?, ?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, null, null, null, null],);
      } finally {
        await stmt.close();
      }
    }

    // Insert row with values
    {
      final stmt = await db.prepareQuery('INSERT INTO nullable_test (id, text_col, int_col, real_col, blob_col) VALUES (?, ?, ?, ?, ?)');
      try {
        await stmt.executeSql(params: [2, 'hello', 42, 3.14, Uint8List.fromList([1, 2, 3])],);
      } finally {
        await stmt.close();
      }
    }

    // Read NULL row
    final reader = await (await db.prepareQuery('SELECT text_col, int_col, real_col, blob_col FROM nullable_test WHERE id = 1')).executeReader();
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
    final reader2 = await (await db.prepareQuery('SELECT text_col, int_col, real_col, blob_col FROM nullable_test WHERE id = 2')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE bool_test (
        id INTEGER PRIMARY KEY,
        flag INTEGER,
        nullable_flag INTEGER
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO bool_test (id, flag, nullable_flag) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, true, null],);
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO bool_test (id, flag, nullable_flag) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [2, false, true],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT flag, nullable_flag FROM bool_test ORDER BY id')).executeReader();

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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE decimal_test (
        id INTEGER PRIMARY KEY,
        amount REAL,
        nullable_amount REAL
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final decimalValue = Decimal.parse('123.45');
    {
      final stmt = await db.prepareQuery('INSERT INTO decimal_test (id, amount, nullable_amount) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, decimalValue, null],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT amount, nullable_amount FROM decimal_test WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE datetime_test (
        id INTEGER PRIMARY KEY,
        created_at TEXT,
        deleted_at TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO datetime_test (id, created_at, deleted_at) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, '2025-06-15T10:30:00.000', null],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT created_at, deleted_at FROM datetime_test WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE time_test (
        id INTEGER PRIMARY KEY,
        duration TEXT,
        nullable_duration TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO time_test (id, duration, nullable_duration) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, '02:30:45', null],);
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO time_test (id, duration, nullable_duration) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [2, '01:15:30.500', null],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT duration, nullable_duration FROM time_test ORDER BY id')).executeReader();

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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE enum_test (
        id INTEGER PRIMARY KEY,
        status INTEGER,
        nullable_status INTEGER
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO enum_test (id, status, nullable_status) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, TestStatus.active, null],);
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO enum_test (id, status, nullable_status) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [2, TestStatus.suspended, TestStatus.inactive],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT status, nullable_status FROM enum_test ORDER BY id')).executeReader();

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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE blob_test (
        id INTEGER PRIMARY KEY,
        data BLOB,
        nullable_data BLOB
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final blobData = Uint8List.fromList([0, 1, 2, 127, 128, 254, 255]);
    {
      final stmt = await db.prepareQuery('INSERT INTO blob_test (id, data, nullable_data) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, blobData, null],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT data, nullable_data FROM blob_test WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE blob_li_test (id INTEGER PRIMARY KEY, data BLOB)
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Use plain List<int> (not Uint8List) to exercise the List<int> branch
    final data = List<int>.generate(256, (i) => i);
    {
      final stmt = await db.prepareQuery('INSERT INTO blob_li_test (id, data) VALUES (?, ?)');
      try {
        await stmt.executeSql(params: [1, data],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT data FROM blob_li_test WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE double_test (
        id INTEGER PRIMARY KEY,
        value REAL,
        nullable_value REAL
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO double_test (id, value, nullable_value) VALUES (?, ?, ?)');
      try {
        await stmt.executeSql(params: [1, 3.14159265, null],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT value, nullable_value FROM double_test WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE prefix_test (
        id INTEGER PRIMARY KEY,
        name TEXT,
        value INTEGER
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // No prefix — should be auto-prefixed with ':'
    {
      final stmt = await db.prepareQuery('INSERT INTO prefix_test (id, name, value) VALUES (:id, :name, :value)');
      try {
        await stmt.executeSql(nameParams: {'id': 1, 'name': 'auto', 'value': 100},);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT name, value FROM prefix_test WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'auto');
    expect(reader.getColumnInt(1), 100);

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  test('Named params with @ prefix', () async {
    final db = await _createTestDb('at_prefix.db');

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE at_test (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO at_test (id, name) VALUES (@id, @name)');
      try {
        await stmt.executeSql(nameParams: {'@id': 1, '@name': 'at-sign'},);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT name FROM at_test WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'at-sign');

    await reader.close();
    await db.closeDb();
    await db.dropDb();
  });

  test('Named params with \$ prefix', () async {
    final db = await _createTestDb('dollar_prefix.db');

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE dollar_test (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO dollar_test (id, name) VALUES (\$id, \$name)');
      try {
        await stmt.executeSql(nameParams: {r'$id': 1, r'$name': 'dollar-sign'},);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT name FROM dollar_test WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE skip_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // :extra does not exist in the SQL — should be silently ignored
    {
      final stmt = await db.prepareQuery('INSERT INTO skip_tbl (id, name) VALUES (:id, :name)');
      try {
        await stmt.executeSql(nameParams: {'id': 1, 'name': 'Alice', 'extra': 'ignored'},);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT name FROM skip_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'Alice');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('Extra named params in executeReader are silently skipped', () async {
    final db = await _createTestDb('skip_extra_reader.db');

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE skip_reader_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO skip_reader_tbl (id, name) VALUES (?, ?)');
      try {
        await stmt.executeSql(params: [1, 'Alice'],);
      } finally {
        await stmt.close();
      }
    }

    // :missing does not exist in the SQL — should be silently ignored
    final reader = await (await db.prepareQuery('SELECT name FROM skip_reader_tbl WHERE id = :id')).executeReader(nameParams: {'id': 1, 'missing': 'ignored'},);
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE throw_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    db.throwOnMissingNamedParams = true;

    // :extra does not exist in the SQL — should throw
    await expectLater(
      () => _runSql(
        db,
        'INSERT INTO throw_tbl (id, name) VALUES (:id, :name)',
        nameParams: {'id': 1, 'name': 'Alice', 'extra': 'boom'},
      ),
      throwsA(isA<Exception>()),
    );

    // Verify the row was NOT inserted (exception aborted the bind)
    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM throw_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 0);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('throwOnMissingNamedParams does not throw when all params match', () async {
    final db = await _createTestDb('throw_all_match.db');
    db.throwOnMissingNamedParams = true;

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE match_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // All params exist in the SQL — should succeed regardless of the flag
    {
      final stmt = await db.prepareQuery('INSERT INTO match_tbl (id, name) VALUES (:id, :name)');
      try {
        await stmt.executeSql(nameParams: {'id': 1, 'name': 'Bob'},);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT name FROM match_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'Bob');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('throwOnMissingNamedParams can be toggled at runtime', () async {
    final db = await _createTestDb('toggle_throw.db');

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE toggle_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Default: off — extra params silently skipped
    {
      final stmt = await db.prepareQuery('INSERT INTO toggle_tbl (id, name) VALUES (:id, :name)');
      try {
        await stmt.executeSql(nameParams: {'id': 1, 'name': 'first', 'extra': 'ok'},);
      } finally {
        await stmt.close();
      }
    }

    // Turn on — extra params should throw
    db.throwOnMissingNamedParams = true;
    await expectLater(
      () => _runSql(
        db,
        'INSERT INTO toggle_tbl (id, name) VALUES (:id, :name)',
        nameParams: {'id': 2, 'name': 'second', 'extra': 'boom'},
      ),
      throwsA(isA<Exception>()),
    );

    // Turn back off — extra params silently skipped again
    db.throwOnMissingNamedParams = false;
    {
      final stmt = await db.prepareQuery('INSERT INTO toggle_tbl (id, name) VALUES (:id, :name)');
      try {
        await stmt.executeSql(nameParams: {'id': 3, 'name': 'third', 'extra': 'ok'},);
      } finally {
        await stmt.close();
      }
    }

    // Verify rows 1 and 3 exist (row 2 was never inserted due to the throw)
    final reader = await (await db.prepareQuery('SELECT name FROM toggle_tbl ORDER BY id')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE content_tbl (id INTEGER PRIMARY KEY)
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

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
    {
      final stmt = await sourceDb.prepareQuery('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE ar_test (
        id INTEGER PRIMARY KEY,
        value TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery("INSERT INTO ar_test (id, value) VALUES (1, 'a')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO ar_test (id, value) VALUES (2, 'b')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO ar_test (id, value) VALUES (3, 'c')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final updated = await ((stmt) async { try { return await stmt.executeSql(); } finally { await stmt.close(); } })(await db.prepareQuery("UPDATE ar_test SET value = 'x' WHERE id <= 2"));
    expect(updated, 2);

    final deleted = await ((stmt) async { try { return await stmt.executeSql(); } finally { await stmt.close(); } })(await db.prepareQuery("DELETE FROM ar_test WHERE id = 3"));
    expect(deleted, 1);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // readRow auto-closes reader when done
  // ──────────────────────────────────────────────────────────────────────

  test('readRow auto-closes reader when no more rows', () async {
    final db = await _createTestDb('auto_close.db');

    {
      final stmt = await db.prepareQuery('CREATE TABLE ac_test (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO ac_test (id) VALUES (1)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT id FROM ac_test')).executeReader();

    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);

    // readRow returns false and auto-closes — subsequent query should work
    expect(await reader.readRow(), isFalse);

    // Verify we can immediately run another query (reader was properly closed)
    final reader2 = await (await db.prepareQuery('SELECT id FROM ac_test')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE all_types (
        int_col INTEGER,
        real_col REAL,
        text_col TEXT,
        blob_col BLOB,
        null_col TEXT
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final blob = Uint8List.fromList([10, 20, 30]);
    {
      final stmt = await db.prepareQuery('INSERT INTO all_types (int_col, real_col, text_col, blob_col, null_col) VALUES (?, ?, ?, ?, ?)');
      try {
        await stmt.executeSql(params: [42, 2.718, 'euler', blob, null],);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT int_col, real_col, text_col, blob_col, null_col FROM all_types')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE enum_err (id INTEGER PRIMARY KEY, val INTEGER)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO enum_err (id, val) VALUES (1, 99)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM enum_err WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE named_types (
        id INTEGER PRIMARY KEY,
        amount REAL,
        active INTEGER
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO named_types (id, amount, active) VALUES (:id, :amount, :active)');
      try {
        await stmt.executeSql(nameParams: {
        ':id': 1,
        ':amount': Decimal.parse('99.99'),
        ':active': true,
      },);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT amount, active FROM named_types WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE named_be (
        id INTEGER PRIMARY KEY,
        data BLOB,
        status INTEGER
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final blob = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
    {
      final stmt = await db.prepareQuery('INSERT INTO named_be (id, data, status) VALUES (:id, :data, :status)');
      try {
        await stmt.executeSql(nameParams: {
        ':id': 1,
        ':data': blob,
        ':status': TestStatus.inactive,
      },);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT data, status FROM named_be WHERE id = 1')).executeReader();
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

    {
      final stmt = await db1.prepareQuery('CREATE TABLE t1 (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db2.prepareQuery('CREATE TABLE t2 (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db1.prepareQuery("INSERT INTO t1 (id, val) VALUES (1, 'from_db1')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db2.prepareQuery("INSERT INTO t2 (id, val) VALUES (1, 'from_db2')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader1 = await (await db1.prepareQuery('SELECT val FROM t1 WHERE id = 1')).executeReader();
    expect(await reader1.readRow(), isTrue);
    expect(reader1.getColumnText(0), 'from_db1');
    await reader1.close();

    final reader2 = await (await db2.prepareQuery('SELECT val FROM t2 WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE empty_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT id FROM empty_tbl')).executeReader();
    expect(await reader.readRow(), isFalse);

    // Should be able to run another query immediately
    final reader2 = await (await db.prepareQuery('SELECT id FROM empty_tbl')).executeReader();
    expect(await reader2.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Unicode / special characters
  // ──────────────────────────────────────────────────────────────────────

  test('Unicode and special characters in text', () async {
    final db = await _createTestDb('unicode_test.db');

    {
      final stmt = await db.prepareQuery('CREATE TABLE unicode_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final testStrings = [
      'Hello 世界',
      'Ação não está à toa',
      'Ümlauts: äöü ÄÖÜ ß',
      '🚀🎉💡',
      "Quotes: 'single' and \"double\"",
      'Line\nbreak\ttab',
    ];

    for (int i = 0; i < testStrings.length; i++) {
      {
        final stmt = await db.prepareQuery('INSERT INTO unicode_tbl (id, val) VALUES (?, ?)');
        try {
          await stmt.executeSql(params: [i + 1, testStrings[i]],);
        } finally {
          await stmt.close();
        }
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM unicode_tbl ORDER BY id')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.beginTransaction();
    expect(db.isInTransaction, isTrue);

    {
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (1, 'a')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (2, 'b')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db.commit();
    expect(db.isInTransaction, isFalse);

    final reader = await (await db.prepareQuery('SELECT val FROM txn_tbl ORDER BY id')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.beginTransaction();
    {
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (1, 'a')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (2, 'b')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db.rollback();
    expect(db.isInTransaction, isFalse);

    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM txn_tbl')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.transaction((db) async {
      {
        final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (1, 'x')");
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
      {
        final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (2, 'y')");
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
    });

    expect(db.isInTransaction, isFalse);

    final reader = await (await db.prepareQuery('SELECT val FROM txn_tbl ORDER BY id')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Insert one row outside the transaction
    {
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (1, 'before')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await expectLater(
      () => db.transaction((db) async {
        {
          final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (2, 'inside')");
          try {
            await stmt.executeSql();
          } finally {
            await stmt.close();
          }
        }
        throw Exception('Simulated error');
      }),
      throwsA(isA<Exception>()),
    );

    expect(db.isInTransaction, isFalse);

    // Only the row inserted before the transaction should exist
    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM txn_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    final reader2 = await (await db.prepareQuery('SELECT val FROM txn_tbl WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

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

    {
      final stmt = await db.prepareQuery('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.beginTransaction();
    expect(db.isInTransaction, isTrue);

    await expectLater(
      () => db.transaction((db) async {
        {
          final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id) VALUES (1)");
          try {
            await stmt.executeSql();
          } finally {
            await stmt.close();
          }
        }
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (1, 'committed')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.beginTransaction();
    {
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (2, 'uncommitted')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    expect(db.isInTransaction, isTrue);

    // closeDb should rollback the pending transaction
    await db.closeDb();
    expect(db.isOpened(), isFalse);

    // Reopen and verify only committed data exists
    final db2 = await DbasSqlite.getInstance(dbName: 'txn_close_rollback.db');
    await db2.openDb();

    final reader = await (await db2.prepareQuery('SELECT COUNT(*) FROM txn_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    final reader2 = await (await db2.prepareQuery('SELECT val FROM txn_tbl WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

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

    {
      final stmt = await db.prepareQuery('CREATE TABLE pool_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO pool_tbl (id, val) VALUES (1, 'pooled')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM pool_tbl WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE single_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO single_tbl (id, val) VALUES (1, 'single')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM single_tbl WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE copy_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO copy_tbl (id, val) VALUES (1, 'copied')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
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

    final reader = await (await destDb.prepareQuery('SELECT val FROM copy_tbl WHERE id = 1')).executeReader();
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
    {
      final stmt = await srcDb.prepareQuery('CREATE TABLE stream_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await srcDb.prepareQuery("INSERT INTO stream_tbl (id, val) VALUES (1, 'streamed')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    final srcPath = await srcDb.getAppDatabasePath();
    await srcDb.closeDb();

    // Read source as a stream
    final stream = File(srcPath).openRead();

    // Attach via stream
    final destDb = await DbasSqlite.getInstance(dbName: 'stream_dest.db');
    final result = await destDb.attachStreamDb(stream);

    expect(result.isOpened(), isTrue);

    final reader = await (await result.prepareQuery('SELECT val FROM stream_tbl WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE cr_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO cr_tbl (id) VALUES (1)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT id FROM cr_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);

    // Close twice — should not throw
    await reader.close();
    await reader.close();

    // Should still be able to run queries after
    final reader2 = await (await db.prepareQuery('SELECT id FROM cr_tbl')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE rit_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO rit_tbl (id, val) VALUES (1, 'before')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.beginTransaction();

    {
      final stmt = await db.prepareQuery("INSERT INTO rit_tbl (id, val) VALUES (2, 'during')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Read within the same transaction — should see uncommitted data
    final reader = await (await db.prepareQuery('SELECT val FROM rit_tbl ORDER BY id')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE seq_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO seq_tbl (id, val) VALUES (1, 'a')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Reader cycle
    final reader = await (await db.prepareQuery('SELECT val FROM seq_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'a');
    await reader.close();

    // Writer after reader
    {
      final stmt = await db.prepareQuery("UPDATE seq_tbl SET val = 'b' WHERE id = 1");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Verify write took effect
    final reader2 = await (await db.prepareQuery('SELECT val FROM seq_tbl WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE cw_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Launch multiple writes concurrently
    await Future.wait([
      _runSql(db, "INSERT INTO cw_tbl (id, val) VALUES (1, 'a')"),
      _runSql(db, "INSERT INTO cw_tbl (id, val) VALUES (2, 'b')"),
      _runSql(db, "INSERT INTO cw_tbl (id, val) VALUES (3, 'c')"),
    ]);

    // All three rows should exist
    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM cw_tbl')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE tl_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final executionOrder = <int>[];

    // Two transactions fired concurrently — must be serialized
    await Future.wait([
      db.transaction((db) async {
        {
          final stmt = await db.prepareQuery("INSERT INTO tl_tbl (id, val) VALUES (1, 'a')");
          try {
            await stmt.executeSql();
          } finally {
            await stmt.close();
          }
        }
        executionOrder.add(1);
      }),
      db.transaction((db) async {
        {
          final stmt = await db.prepareQuery("INSERT INTO tl_tbl (id, val) VALUES (2, 'b')");
          try {
            await stmt.executeSql();
          } finally {
            await stmt.close();
          }
        }
        executionOrder.add(2);
      }),
    ]);

    // Both should have completed
    expect(executionOrder.length, 2);
    expect(executionOrder.toSet(), {1, 2});

    // Both rows should exist
    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM tl_tbl')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE rw_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO rw_tbl (id, val) VALUES (1, 'initial')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Start a reader
    final reader = await (await db.prepareQuery('SELECT val FROM rw_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'initial');
    await reader.close();

    // Writer should not be blocked
    {
      final stmt = await db.prepareQuery("UPDATE rw_tbl SET val = 'updated' WHERE id = 1");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader2 = await (await db.prepareQuery('SELECT val FROM rw_tbl WHERE id = 1')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE cs_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.closeDb();

    expect(db.isOpened(), isFalse);
    expect(db.isInTransaction, isFalse);

    expect(
      () => db.prepareQuery('SELECT 1'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => db.prepareQuery('SELECT 1'),
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE mr_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO mr_tbl (id, val) VALUES (1, 'a')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO mr_tbl (id, val) VALUES (2, 'b')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // First reader session
    final reader = await (await db.prepareQuery('SELECT val FROM mr_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'a');
    await reader.close();

    // Second reader session
    final reader2 = await (await db.prepareQuery('SELECT val FROM mr_tbl WHERE id = 2')).executeReader();
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'b');
    await reader2.close();

    // Third session — full iteration
    final reader3 = await (await db.prepareQuery('SELECT val FROM mr_tbl ORDER BY id')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE ti_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.transaction((db) async {
      {
        final stmt = await db.prepareQuery("INSERT INTO ti_tbl (id, val) VALUES (1, 'one')");
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }

      // Read back within same transaction
      final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM ti_tbl')).executeReader();
      expect(await reader.readRow(), isTrue);
      expect(reader.getColumnInt(0), 1);
      await reader.close();

      {
        final stmt = await db.prepareQuery("INSERT INTO ti_tbl (id, val) VALUES (2, 'two')");
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }

      // Read again — should see both
      final reader2 = await (await db.prepareQuery('SELECT COUNT(*) FROM ti_tbl')).executeReader();
      expect(await reader2.readRow(), isTrue);
      expect(reader2.getColumnInt(0), 2);
      await reader2.close();
    });

    // Verify after commit
    final reader = await (await db.prepareQuery('SELECT val FROM ti_tbl ORDER BY id')).executeReader();
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
    {
      final stmt = await db.prepareQuery('CREATE TABLE pfe_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Trigger prepare failure (references non-existent table). v2.4
    // surfaces the C lib's error message; the rc is conveyed through
    // the `(handle == 0)` invariant rather than embedded in the
    // message, so we assert on the human-readable error text.
    try {
      {
        final stmt = await db.prepareQuery('SELECT * FROM nonexistent_table');
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
      fail('Should have thrown');
    } on Exception catch (e) {
      expect(e.toString(), contains('no such table'));
    }

    // Connection must still be usable — stmt was properly finalized
    {
      final stmt = await db.prepareQuery("INSERT INTO pfe_tbl (id, val) VALUES (1, 'ok')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    final reader = await (await db.prepareQuery('SELECT val FROM pfe_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'ok');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('executeReader prepare failure includes error code and recovers', () async {
    final db = await _createTestDb('prepare_fail_reader.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE pfr_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO pfr_tbl (id) VALUES (1)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    try {
      await (await db.prepareQuery('SELECT * FROM nonexistent_table')).executeReader();
      fail('Should have thrown');
    } on Exception catch (e) {
      // v2.4 surfaces the human-readable C-lib error message
      // instead of the rc — see the executeSql counterpart.
      expect(e.toString(), contains('no such table'));
    }

    // Reader must still work — lock/pool was properly released
    final reader = await (await db.prepareQuery('SELECT id FROM pfr_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('executeSql prepare failure within transaction keeps transaction intact', () async {
    final db = await _createTestDb('prepare_fail_txn.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE pft_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.beginTransaction();
    {
      final stmt = await db.prepareQuery("INSERT INTO pft_tbl (id, val) VALUES (1, 'one')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Prepare failure mid-transaction
    await expectLater(
      () => _runSql(db, 'SELECT * FROM nonexistent_table'),
      throwsA(isA<Exception>()),
    );

    // Transaction should still be active and usable
    expect(db.isInTransaction, isTrue);
    {
      final stmt = await db.prepareQuery("INSERT INTO pft_tbl (id, val) VALUES (2, 'two')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db.commit();

    // Both rows should be committed
    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM pft_tbl')).executeReader();
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
    {
      final stmt = await db.prepareQuery('CREATE TABLE bfe_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Bind 2 params to a statement with 1 placeholder — index 2 is out of range
    // sqlite3_bind returns SQLITE_RANGE (25), now caught by != _sqliteOk
    await expectLater(
      () => _runSql(
        db,
        'INSERT INTO bfe_tbl (id) VALUES (?)',
        params: [1, 'extra'],
      ),
      throwsA(isA<Exception>()),
    );

    // Connection must still work — stmt was finalized by the finally block
    {
      final stmt = await db.prepareQuery("INSERT INTO bfe_tbl (id, val) VALUES (1, 'ok')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    final reader = await (await db.prepareQuery('SELECT val FROM bfe_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'ok');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('executeReader bind failure recovers and reader is released', () async {
    final db = await _createTestDb('bind_fail_reader.db', readerPoolSize: 2);
    {
      final stmt = await db.prepareQuery('CREATE TABLE bfr_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO bfr_tbl (id) VALUES (1)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await expectLater(
      () async {
        final s = await db.prepareQuery('SELECT * FROM bfr_tbl WHERE id = ?');
        try {
          await s.executeReader(params: [1, 'extra']);
        } finally {
          await s.close();
        }
      },
      throwsA(isA<Exception>()),
    );

    // Pool reader must be released — subsequent reader should work
    final reader = await (await db.prepareQuery('SELECT id FROM bfr_tbl')).executeReader();
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

    {
      final stmt = await db.prepareQuery('''
      CREATE TABLE src_tbl (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id INTEGER
      )
    ''');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO src_tbl (id, name, parent_id) VALUES (1, 'root', NULL)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO src_tbl (id, name, parent_id) VALUES (2, 'child', 1)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO src_tbl (id, name, parent_id) VALUES (3, 'grandchild', 2)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.transaction((db) async {
      // First temp table — staging data (like merge temp table)
      {
        final stmt = await db.prepareQuery('CREATE TEMP TABLE __temp_merge__ (id INTEGER, name TEXT)');
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
      {
        final stmt = await db.prepareQuery('INSERT INTO __temp_merge__ SELECT id, name FROM src_tbl');
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }

      final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM __temp_merge__')).executeReader();
      expect(await reader.readRow(), isTrue);
      expect(reader.getColumnInt(0), 3);
      await reader.close();

      // Second temp table — hierarchy resolution (self-recursive FK)
      {
        final stmt = await db.prepareQuery('CREATE TEMP TABLE __temp_hier__ (id INTEGER, parent_id INTEGER)');
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
      {
        final stmt = await db.prepareQuery('INSERT INTO __temp_hier__ SELECT id, parent_id FROM src_tbl WHERE parent_id IS NOT NULL');
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }

      final reader2 = await (await db.prepareQuery('SELECT COUNT(*) FROM __temp_hier__')).executeReader();
      expect(await reader2.readRow(), isTrue);
      expect(reader2.getColumnInt(0), 2);
      await reader2.close();

      // Cross-temp-table operation
      {
        final stmt = await db.prepareQuery('''
        INSERT INTO src_tbl (id, name, parent_id)
        SELECT 4, 'merged', h.parent_id
        FROM __temp_hier__ h
        WHERE h.id = 3
      ''');
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }

      // Clean up temp tables
      {
        final stmt = await db.prepareQuery('DROP TABLE __temp_merge__');
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
      {
        final stmt = await db.prepareQuery('DROP TABLE __temp_hier__');
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
    });

    // Verify final state
    final reader3 = await (await db.prepareQuery('SELECT COUNT(*) FROM src_tbl')).executeReader();
    expect(await reader3.readRow(), isTrue);
    expect(reader3.getColumnInt(0), 4);
    await reader3.close();

    final reader4 = await (await db.prepareQuery('SELECT name, parent_id FROM src_tbl WHERE id = 4')).executeReader();
    expect(await reader4.readRow(), isTrue);
    expect(reader4.getColumnText(0), 'merged');
    expect(reader4.getColumnInt(1), 2);
    await reader4.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('rapid sequential executeSql in transaction all succeed', () async {
    final db = await _createTestDb('rapid_txn.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE rt_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.transaction((db) async {
      for (int i = 1; i <= 50; i++) {
        {
          final stmt = await db.prepareQuery('INSERT INTO rt_tbl (id, val) VALUES (?, ?)');
          try {
            await stmt.executeSql(params: [i, 'row_$i'],);
          } finally {
            await stmt.close();
          }
        }
      }
    });

    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM rt_tbl')).executeReader();
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

    {
      final stmt = await db.prepareQuery('CREATE TABLE pcw_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await Future.wait([
      _runSql(db, "INSERT INTO pcw_tbl (id, val) VALUES (1, 'a')"),
      _runSql(db, "INSERT INTO pcw_tbl (id, val) VALUES (2, 'b')"),
      _runSql(db, "INSERT INTO pcw_tbl (id, val) VALUES (3, 'c')"),
    ]);

    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM pcw_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 3);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: sequential reader then writer works correctly', () async {
    final db = await _createTestDb('pool_seq_rw.db', readerPoolSize: 2);

    {
      final stmt = await db.prepareQuery('CREATE TABLE psrw_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO psrw_tbl (id, val) VALUES (1, 'original')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Reader cycle (uses pool reader)
    final reader = await (await db.prepareQuery('SELECT val FROM psrw_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'original');
    await reader.close();

    // Writer after reader
    {
      final stmt = await db.prepareQuery("UPDATE psrw_tbl SET val = 'updated' WHERE id = 1");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Verify write took effect
    final reader2 = await (await db.prepareQuery('SELECT val FROM psrw_tbl WHERE id = 1')).executeReader();
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'updated');
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: getLastInsertedId works after executeSql', () async {
    final db = await _createTestDb('pool_last_id.db', readerPoolSize: 2);

    {
      final stmt = await db.prepareQuery('CREATE TABLE pli_tbl (id INTEGER PRIMARY KEY AUTOINCREMENT, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    final insertStmt =
        await db.prepareQuery("INSERT INTO pli_tbl (val) VALUES ('first')");
    int lastId;
    try {
      await insertStmt.executeSql();
      lastId = insertStmt.getLastInsertedId();
    } finally {
      await insertStmt.close();
    }
    expect(lastId, greaterThan(0));

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: transaction with pool-enabled database', () async {
    final db = await _createTestDb('pool_txn.db', readerPoolSize: 4);

    {
      final stmt = await db.prepareQuery('CREATE TABLE pt_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO pt_tbl (id, val) VALUES (1, 'before')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.beginTransaction();

    {
      final stmt = await db.prepareQuery("INSERT INTO pt_tbl (id, val) VALUES (2, 'during')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Read within the same transaction — should see uncommitted data
    final reader = await (await db.prepareQuery('SELECT val FROM pt_tbl ORDER BY id')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'before');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'during');
    expect(await reader.readRow(), isFalse);

    await db.commit();

    // Verify committed data
    final reader2 = await (await db.prepareQuery('SELECT COUNT(*) FROM pt_tbl')).executeReader();
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnInt(0), 2);
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: concurrent transactions are serialized', () async {
    final db = await _createTestDb('pool_conc_txn.db', readerPoolSize: 2);

    {
      final stmt = await db.prepareQuery('CREATE TABLE pct_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final executionOrder = <int>[];

    await Future.wait([
      db.transaction((db) async {
        {
          final stmt = await db.prepareQuery("INSERT INTO pct_tbl (id, val) VALUES (1, 'a')");
          try {
            await stmt.executeSql();
          } finally {
            await stmt.close();
          }
        }
        executionOrder.add(1);
      }),
      db.transaction((db) async {
        {
          final stmt = await db.prepareQuery("INSERT INTO pct_tbl (id, val) VALUES (2, 'b')");
          try {
            await stmt.executeSql();
          } finally {
            await stmt.close();
          }
        }
        executionOrder.add(2);
      }),
    ]);

    expect(executionOrder.length, 2);
    expect(executionOrder.toSet(), {1, 2});

    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM pct_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 2);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: reader fallback to writer when all pool readers busy', () async {
    // Use pool with 1 reader — holding it should trigger writer fallback
    final db = await _createTestDb('pool_fallback.db', readerPoolSize: 1);

    {
      final stmt = await db.prepareQuery('CREATE TABLE pf_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO pf_tbl (id, val) VALUES (1, 'test')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // This should work even with small pool
    final reader = await (await db.prepareQuery('SELECT val FROM pf_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'test');
    await reader.close();

    // Subsequent operations should still work
    {
      final stmt = await db.prepareQuery("INSERT INTO pf_tbl (id, val) VALUES (2, 'test2')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader2 = await (await db.prepareQuery('SELECT COUNT(*) FROM pf_tbl')).executeReader();
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnInt(0), 2);
    await reader2.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('pool: multiple databases work independently', () async {
    final db1 = await _createTestDb('pool_multi_a.db', readerPoolSize: 2);
    final db2 = await _createTestDb('pool_multi_b.db', readerPoolSize: 2);

    {
      final stmt = await db1.prepareQuery('CREATE TABLE ma_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db2.prepareQuery('CREATE TABLE mb_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Concurrent operations on different DBs
    await Future.wait([
      _runSql(db1, "INSERT INTO ma_tbl (id, val) VALUES (1, 'db1')"),
      _runSql(db2, "INSERT INTO mb_tbl (id, val) VALUES (1, 'db2')"),
    ]);

    // Verify each DB independently
    final reader1 = await (await db1.prepareQuery('SELECT val FROM ma_tbl WHERE id = 1')).executeReader();
    expect(await reader1.readRow(), isTrue);
    expect(reader1.getColumnText(0), 'db1');
    await reader1.close();

    final reader2 = await (await db2.prepareQuery('SELECT val FROM mb_tbl WHERE id = 1')).executeReader();
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
    {
      final stmt = await db.prepareQuery('CREATE TABLE ppf_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Bad SQL should fail and release the pool slot
    await expectLater(
      () => _runSql(db, 'INSERT INTO nonexistent_tbl VALUES (1)'),
      throwsA(isA<Exception>()),
    );

    // Subsequent operations should still work (slot was released)
    {
      final stmt = await db.prepareQuery('INSERT INTO ppf_tbl (id) VALUES (1)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT id FROM ppf_tbl')).executeReader();
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
    {
      final stmt = await db.prepareQuery("CREATE TABLE d_tbl (id INTEGER PRIMARY KEY, val TEXT)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO d_tbl (id, val) VALUES (1, 'not_a_number')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM d_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(() => reader.getColumnDecimal(0), throwsFormatException);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('getColumnTime throws FormatException on garbage input', () async {
    final db = await _createTestDb('time_err.db');
    {
      final stmt = await db.prepareQuery("CREATE TABLE t_tbl (id INTEGER PRIMARY KEY, val TEXT)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO t_tbl (id, val) VALUES (1, 'garbage')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM t_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(() => reader.getColumnTime(0), throwsFormatException);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  test('getColumnTime parses HH:MM format without seconds', () async {
    final db = await _createTestDb('time_hhmm.db');
    {
      final stmt = await db.prepareQuery("CREATE TABLE t_tbl (id INTEGER PRIMARY KEY, val TEXT)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO t_tbl (id, val) VALUES (1, '14:30')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM t_tbl WHERE id = 1')).executeReader();
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
    {
      final stmt = await db.prepareQuery('CREATE TABLE cl_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db.closeDb();
    await db.dropDb();

    // Re-create with same name — should not use stale delegate
    final db2 = await _createTestDb('cleanup.db');
    {
      final stmt = await db2.prepareQuery('CREATE TABLE cl_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db2.closeDb();
    await db2.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Row cache correctness across pool writer/reader interleaving
  // ──────────────────────────────────────────────────────────────────────

  test('pool: row cache returns reader data after writer executeSql', () async {
    final db = await _createTestDb('cache_interleave.db', readerPoolSize: 2);
    {
      final stmt = await db.prepareQuery('CREATE TABLE ci_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO ci_tbl (id, val) VALUES (1, 'alpha')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO ci_tbl (id, val) VALUES (2, 'beta')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Execute a write (touches writer's readRow path internally)
    final gammaStmt = await db
        .prepareQuery("INSERT INTO ci_tbl (id, val) VALUES (3, 'gamma')");
    int insertedId;
    try {
      await gammaStmt.executeSql();
      insertedId = gammaStmt.getLastInsertedId();
    } finally {
      await gammaStmt.close();
    }
    expect(insertedId, 3);

    // Now execute a reader query — should return reader data, not writer cache
    final reader = await (await db.prepareQuery('SELECT val FROM ci_tbl ORDER BY id')).executeReader();
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

  test('pool: blocking-acquire times out when readers are saturated', () async {
    // v2.4 contract: pool exhaustion no longer silently falls back
    // to the writer. Instead the second reader blocks up to
    // [DbasSqlite.kPoolAcquireTimeoutMs] (default 30s) and then
    // throws TimeoutException. We use the test-only override to
    // shorten the timeout so the test completes quickly.
    final db = await _createTestDb('pool_exhaust.db', readerPoolSize: 1);
    DbasSqlite.debugPoolAcquireTimeoutMs = 200;
    try {
      {
        final stmt = await db.prepareQuery('CREATE TABLE pe_tbl (id INTEGER PRIMARY KEY, val TEXT)');
        try { await stmt.executeSql(); } finally { await stmt.close(); }
      }
      {
        final stmt = await db.prepareQuery("INSERT INTO pe_tbl (id, val) VALUES (1, 'first')");
        try { await stmt.executeSql(); } finally { await stmt.close(); }
      }

      // First reader holds the only pool slot.
      final reader = await (await db.prepareQuery('SELECT val FROM pe_tbl WHERE id = 1')).executeReader();
      expect(await reader.readRow(), isTrue);
      expect(reader.getColumnText(0), 'first');
      // Don't close reader yet.

      // Second reader blocks-then-times-out.
      await expectLater(
        () async {
          final stmt = await db.prepareQuery('SELECT val FROM pe_tbl WHERE id = 1');
          try {
            await stmt.executeReader();
          } finally {
            await stmt.close();
          }
        },
        throwsA(isA<TimeoutException>()),
      );

      // Closing the first reader frees the slot — a fresh reader works.
      await reader.close();
      final reader2 = await (await db.prepareQuery('SELECT val FROM pe_tbl WHERE id = 1')).executeReader();
      expect(await reader2.readRow(), isTrue);
      expect(reader2.getColumnText(0), 'first');
      await reader2.close();
    } finally {
      DbasSqlite.debugPoolAcquireTimeoutMs = null;
      await db.closeDb();
      await db.dropDb();
    }
  });

  // ──────────────────────────────────────────────────────────────────────
  // C pool: open, close, reopen with different pool size
  // ──────────────────────────────────────────────────────────────────────

  test('pool: close and reopen with different pool size', () async {
    final db1 = await _createTestDb('pool_reopen.db', readerPoolSize: 1);
    {
      final stmt = await db1.prepareQuery('CREATE TABLE pr_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db1.prepareQuery("INSERT INTO pr_tbl (id, val) VALUES (1, 'persisted')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db1.closeDb();

    // Reopen with a different pool size
    final db2 = await DbasSqlite.getInstance(dbName: 'pool_reopen.db');
    await db2.openDb(readerPoolSize: 4);

    final reader = await (await db2.prepareQuery('SELECT val FROM pr_tbl WHERE id = 1')).executeReader();
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
    {
      final stmt = await db.prepareQuery('CREATE TABLE we_tbl (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Invalid SQL should propagate error through worker isolate
    await expectLater(
      () => _runSql(db, 'INVALID SQL THAT DOES NOT PARSE'),
      throwsA(isA<Exception>()),
    );

    // Connection should still be usable after error
    {
      final stmt = await db.prepareQuery('INSERT INTO we_tbl (id) VALUES (1)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT id FROM we_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ──────────────────────────────────────────────────────────────────────
  // v2.4.0 regression + capability tests
  //
  // Each guards a behaviour that was either added or fixed in v2.4.0.
  // Comments name the bug class so a future maintainer touching the
  // affected area sees what the test pins.
  // ──────────────────────────────────────────────────────────────────────

  // ── 1. Counter cache survives reader auto-close on DONE ──────────────
  // Regression test for the §4.2 ordering bug where the executeReader
  // onClose closure read counters AFTER FinalizeStmt — which always
  // returned -1 because the handle was already removed from the C
  // lib's liveStmts map. Fixed by reading counters before finalize.
  test('counter cache survives reader auto-close on DONE', () async {
    final db = await _createTestDb('counter_after_autoclose.db');
    {
      final stmt = await db.prepareQuery(
          'CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO t (v) VALUES (?)');
      try {
        await stmt.executeSql(params: ['a']);
        await stmt.executeSql(params: ['b']);
      } finally { await stmt.close(); }
    }

    // INSERT ... RETURNING goes through executeReader. After auto-close
    // (readRow returns false on the second call), the statement's
    // cached counters must reflect the insert — they were captured
    // BEFORE finalize, so the C lib's GetStmtLastInsertedId was still
    // valid when called.
    final stmt =
        await db.prepareQuery('INSERT INTO t (v) VALUES (?) RETURNING id');
    try {
      final reader = await stmt.executeReader(params: ['c']);
      expect(await reader.readRow(), isTrue);
      final returnedId = reader.getColumnInt(0);
      expect(returnedId, 3);
      // Second readRow returns false → triggers auto-close (which
      // captures counters then finalises).
      expect(await reader.readRow(), isFalse);
      expect(reader.isClosed, isTrue);

      expect(stmt.getLastInsertedId(), 3,
          reason: 'getLastInsertedId must NOT be -1 after reader auto-close');
      expect(stmt.getAffectedRows(), greaterThanOrEqualTo(1));
    } finally { await stmt.close(); }

    await db.closeDb();
    await db.dropDb();
  });

  // ── 2. Column metadata available BEFORE first readRow ────────────────
  // Regression test for the bug discovered while running v2.4.0:
  // getColumnCount() returned 0 before the first readRow because the
  // count was only populated inside readRowAndCache. Fixed by
  // capturing column metadata at prepare time and pre-populating the
  // reader's RowData cache.
  test('getColumnCount and getColumnName work BEFORE first readRow', () async {
    final db = await _createTestDb('col_meta_before_readrow.db');
    {
      final stmt = await db.prepareQuery(
          'CREATE TABLE t (alpha INTEGER, beta TEXT, gamma REAL)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }

    final stmt =
        await db.prepareQuery('SELECT alpha, beta, gamma FROM t WHERE alpha > ?');
    try {
      // Empty table — readRow will return false. But metadata is
      // available immediately after executeReader.
      final reader = await stmt.executeReader(params: [0]);

      expect(reader.getColumnCount(), 3,
          reason: 'count must be set before any readRow call');
      expect(reader.getColumnName(0), 'alpha');
      expect(reader.getColumnName(1), 'beta');
      expect(reader.getColumnName(2), 'gamma');

      // Column count survives DONE consistently (the worker now reads
      // it from the live statement, not from the row payload).
      expect(await reader.readRow(), isFalse);
      expect(reader.getColumnCount(), 3,
          reason: 'count must remain stable after DONE');
    } finally { await stmt.close(); }

    await db.closeDb();
    await db.dropDb();
  });

  // ── 3. Bind error rc surfaces with offending parameter index ─────────
  // Regression test for the FFI fire-and-forget bind bug. Before the
  // fix, every bindXxx returned sqliteOk synchronously without
  // awaiting the worker dispatch, so SQLITE_RANGE on out-of-bounds
  // index (the most common bind error) was silently dropped and only
  // surfaced as an opaque step failure with a generic "Misuse"
  // message. The fix awaits the dispatch and reports the index.
  test('bind error surfaces specific offending positional index', () async {
    final db = await _createTestDb('bind_error_index.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }

    // SQL has 1 placeholder; binding index 2 → SQLITE_RANGE.
    final stmt = await db.prepareQuery('INSERT INTO t (id) VALUES (?)');
    try {
      await expectLater(
        stmt.executeSql(params: [1, 'extra']),
        throwsA(predicate<Exception>(
          (e) => e.toString().contains('positional index 2'),
          'exception message identifies the offending bind index',
        )),
      );
    } finally { await stmt.close(); }

    await db.closeDb();
    await db.dropDb();
  });

  // ── 4. Bind buffer preserved when execute throws ─────────────────────
  // executeSql / executeReader accept `params:` / `nameParams:`
  // arguments that override the buffered binds. The override happens
  // BEFORE execute, but on a throw the snapshot must be restored so
  // the caller can fix one slot and retry without re-binding.
  test('bind buffer is restored when an execute call throws', () async {
    final db = await _createTestDb('bind_preserve.db');
    {
      final stmt = await db.prepareQuery(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT NOT NULL)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }

    final stmt = await db.prepareQuery('INSERT INTO t (id, v) VALUES (?, ?)');
    try {
      // Pre-bind via fluent setters — buffer is [100, 'good'].
      stmt.bindInt(1, 100).bindText(2, 'good');

      // Override with bad params. NULL into NOT NULL → SQLITE_CONSTRAINT
      // at step time. The execute throws and the buffer must be
      // restored to [100, 'good'].
      await expectLater(
        stmt.executeSql(params: [101, null]),
        throwsA(isA<Exception>()),
      );

      // No params on this call — must use the restored buffer.
      final affected = await stmt.executeSql();
      expect(affected, 1);
      expect(stmt.getLastInsertedId(), 100);
    } finally { await stmt.close(); }

    // Verify the row really was the original buffer's values.
    final readStmt = await db.prepareQuery('SELECT id, v FROM t');
    try {
      final reader = await readStmt.executeReader();
      try {
        expect(await reader.readRow(), isTrue);
        expect(reader.getColumnInt(0), 100);
        expect(reader.getColumnText(1), 'good');
        expect(await reader.readRow(), isFalse);
      } finally { await reader.close(); }
    } finally { await readStmt.close(); }

    await db.closeDb();
    await db.dropDb();
  });

  // ── 5. setBusyTimeout terminates on a quiescent pool ─────────────────
  // Regression test for the infinite-loop bug. The original loop
  // depended on `poolAcquireReaderBlocking` returning 0 to terminate,
  // but on an idle pool every acquire succeeds, the slot is released,
  // and the next acquire can re-grab the same slot indefinitely.
  // Fixed by tracking _readerPoolSize and iterating exactly that many
  // times while holding all slots exclusively.
  test('setBusyTimeout terminates on a quiescent pool', () async {
    final db = await _createTestDb('busy_timeout_quiet.db', readerPoolSize: 4);
    // 3 s outer timeout: 4 idle acquires + 4 SetBusyTimeout calls
    // should complete in ms. If the loop is broken, this fails fast.
    await expectLater(
      db.setBusyTimeout(7500).timeout(const Duration(seconds: 3)),
      completes,
    );
    // A second call must also succeed cleanly.
    await db.setBusyTimeout(5000).timeout(const Duration(seconds: 3));
    await db.closeDb();
    await db.dropDb();
  });

  // ── 6. setBusyTimeout throws when a reader is in flight ──────────────
  // The contract is best-effort with strict failure mode: if any
  // reader slot is busy beyond kSetBusyTimeoutAcquireMs, throw a
  // clear StateError naming the slot. Uses the test-only
  // debugSetBusyTimeoutAcquireMs override to keep the test fast.
  test('setBusyTimeout throws StateError when a reader is in flight', () async {
    final db = await _createTestDb('busy_timeout_busy.db', readerPoolSize: 1);
    DbasSqlite.debugSetBusyTimeoutAcquireMs = 200;
    try {
      {
        final stmt = await db.prepareQuery('CREATE TABLE t (id INTEGER)');
        try { await stmt.executeSql(); } finally { await stmt.close(); }
      }
      {
        final stmt = await db.prepareQuery('INSERT INTO t VALUES (1)');
        try { await stmt.executeSql(); } finally { await stmt.close(); }
      }

      // Hold the only pool slot.
      final readerStmt = await db.prepareQuery('SELECT id FROM t');
      final reader = await readerStmt.executeReader();
      expect(await reader.readRow(), isTrue);

      try {
        await expectLater(
          db.setBusyTimeout(10000),
          throwsA(predicate<StateError>(
            (e) => e.toString().contains('200ms') &&
                   e.toString().contains('reader 0'),
            'message names the slot index and timeout',
          )),
        );
      } finally {
        await reader.close();
        await readerStmt.close();
      }

      // After the reader closes, the call works again.
      await db.setBusyTimeout(10000).timeout(const Duration(seconds: 3));
    } finally {
      DbasSqlite.debugSetBusyTimeoutAcquireMs = null;
      await db.closeDb();
      await db.dropDb();
    }
  });

  // ── 7. getSqliteVersion returns a parsable version ───────────────────
  test('getSqliteVersion returns a SemVer-shaped string', () async {
    final db = await _createTestDb('sqlite_version.db');
    final v = db.getSqliteVersion();
    expect(v, matches(RegExp(r'^\d+\.\d+\.\d+$')),
        reason: 'expected M.m.p — got "$v"');
    // Library is well past 3.0.0; sanity-check the major.
    final major = int.parse(v.split('.').first);
    expect(major, greaterThanOrEqualTo(3));
    await db.closeDb();
    await db.dropDb();
  });

  // ── 8. getTotalChanges reflects mutations ────────────────────────────
  test('getTotalChanges grows with each successful mutation', () async {
    final db = await _createTestDb('total_changes.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE t (id INTEGER)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }
    final baseline = db.getTotalChanges();
    expect(baseline, greaterThanOrEqualTo(0));

    final ins = await db.prepareQuery('INSERT INTO t (id) VALUES (?)');
    try {
      for (int i = 1; i <= 5; i++) {
        await ins.executeSql(params: [i]);
      }
    } finally { await ins.close(); }

    expect(db.getTotalChanges(), baseline + 5);
    await db.closeDb();
    await db.dropDb();
  });

  // ── 9. getDbFileName returns the database path ───────────────────────
  test('getDbFileName returns the path while open and null after close', () async {
    final db = await _createTestDb('file_name.db');
    final fn = db.getDbFileName();
    expect(fn, isNotNull);
    expect(fn!, endsWith('file_name.db'));
    await db.closeDb();
    expect(db.getDbFileName(), isNull,
        reason: 'must return null after the connection is closed');
    await db.dropDb();
  });

  // ── 10. enableWal is idempotent on a pooled database ─────────────────
  // Regression test for the silent-no-op-on-web review finding (web
  // is fixed to actually verify); native side has always been
  // idempotent but no test guards it.
  test('enableWal is idempotent on a pooled database', () async {
    final db = await _createTestDb('enable_wal_idempotent.db', readerPoolSize: 2);
    // Pool always opens with WAL. Both calls must succeed.
    await db.enableWal();
    await db.enableWal();
    await db.closeDb();
    await db.dropDb();
  });

  // ── 11. Two statements with concurrently active readers ──────────────
  // The headline v2.4.0 capability: multiple statements with their
  // own native handles, each with its own reader on its own pool
  // connection. Interleaved reads must produce distinct, correct
  // result sets — which is the core regression test for the
  // multi-isolate FFI worker pool design.
  test('two statements with concurrently active readers', () async {
    final db = await _createTestDb('multi_stmt.db', readerPoolSize: 4);
    {
      final stmt = await db.prepareQuery(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }
    final ins = await db.prepareQuery('INSERT INTO t (id, v) VALUES (?, ?)');
    try {
      for (int i = 1; i <= 3; i++) {
        await ins.executeSql(params: [i, 'row$i']);
      }
    } finally { await ins.close(); }

    final stmt1 = await db.prepareQuery('SELECT v FROM t WHERE id = ?');
    final stmt2 = await db.prepareQuery('SELECT v FROM t ORDER BY id DESC');
    try {
      final r1 = await stmt1.executeReader(params: [2]);
      final r2 = await stmt2.executeReader();
      try {
        // Interleave reads — each reader reads from its own handle
        // on its own pool connection.
        expect(await r1.readRow(), isTrue);
        expect(r1.getColumnText(0), 'row2');

        expect(await r2.readRow(), isTrue);
        expect(r2.getColumnText(0), 'row3');

        expect(await r1.readRow(), isFalse,
            reason: 'r1 has only one matching row');

        expect(await r2.readRow(), isTrue);
        expect(r2.getColumnText(0), 'row2');
        expect(await r2.readRow(), isTrue);
        expect(r2.getColumnText(0), 'row1');
        expect(await r2.readRow(), isFalse);
      } finally {
        await r1.close();
        await r2.close();
      }
    } finally {
      await stmt1.close();
      await stmt2.close();
    }

    await db.closeDb();
    await db.dropDb();
  });

  // ── 12. Statement reuse with different params per execute ────────────
  // The deferred-prepare model means the SAME DbasSqliteStatement can
  // be executed many times — the C lib's PrepareQuery runs each
  // time, the bind buffer is replayed, and counters reflect the most
  // recent successful step.
  test('statement reuse with different params per execute', () async {
    final db = await _createTestDb('stmt_reuse.db');
    {
      final stmt = await db.prepareQuery(
          'CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }

    final ins = await db.prepareQuery('INSERT INTO t (v) VALUES (?)');
    try {
      const values = ['a', 'b', 'c', 'd', 'e'];
      for (int i = 0; i < values.length; i++) {
        final affected = await ins.executeSql(params: [values[i]]);
        expect(affected, 1);
        expect(ins.getLastInsertedId(), i + 1);
      }
    } finally { await ins.close(); }

    final read = await db.prepareQuery('SELECT v FROM t ORDER BY id');
    try {
      final reader = await read.executeReader();
      try {
        final got = <String>[];
        while (await reader.readRow()) {
          got.add(reader.getColumnText(0));
        }
        expect(got, ['a', 'b', 'c', 'd', 'e']);
      } finally { await reader.close(); }
    } finally { await read.close(); }

    await db.closeDb();
    await db.dropDb();
  });

  // ── 13. Two readers on the same statement throws StateError ──────────
  // Per-statement invariant: only one DbasSqliteReader may be active
  // per DbasSqliteStatement at a time. Closing the first reader
  // releases the slot for the next.
  test('executeReader while a reader from same stmt is active throws', () async {
    final db = await _createTestDb('two_readers_same_stmt.db', readerPoolSize: 2);
    {
      final stmt = await db.prepareQuery('CREATE TABLE t (id INTEGER)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO t VALUES (1)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }

    final stmt = await db.prepareQuery('SELECT id FROM t');
    try {
      final r1 = await stmt.executeReader();
      try {
        expect(await r1.readRow(), isTrue);

        // Second reader on same statement → StateError.
        await expectLater(
          stmt.executeReader(),
          throwsA(predicate<StateError>(
            (e) => e.toString().contains('reader from this statement is still active'),
            'message names the active-reader invariant',
          )),
        );
      } finally { await r1.close(); }

      // After r1 closes, we can open a fresh reader on the same stmt.
      final r2 = await stmt.executeReader();
      try {
        expect(await r2.readRow(), isTrue);
        expect(r2.getColumnInt(0), 1);
      } finally { await r2.close(); }
    } finally { await stmt.close(); }

    await db.closeDb();
    await db.dropDb();
  });

  // ── 14. Per-statement state is isolated across statements ────────────
  // The C lib gives each handle its own lastError / affectedRows /
  // lastInsertedId. A failure on one statement must not corrupt the
  // observable state of another.
  test('per-statement state is isolated across statements', () async {
    final db = await _createTestDb('per_stmt_isolation.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }

    final stmt1 = await db.prepareQuery('INSERT INTO t (id) VALUES (?)');
    final stmt2 = await db.prepareQuery('INSERT INTO t (id) VALUES (?)');
    try {
      // stmt1: bind out-of-range → SQLITE_RANGE → execute throws
      // before any successful step. Counters stay at -1.
      await expectLater(
        stmt1.executeSql(params: [42, 'extra']),
        throwsA(isA<Exception>()),
      );
      expect(stmt1.getLastInsertedId(), -1,
          reason: 'no successful step on stmt1 → counter is -1');
      expect(stmt1.getAffectedRows(), -1);

      // stmt2: succeeds — its own counters are correct, untouched by stmt1.
      final affected = await stmt2.executeSql(params: [99]);
      expect(affected, 1);
      expect(stmt2.getLastInsertedId(), 99);
      expect(stmt2.getAffectedRows(), 1);

      // Retry stmt1 with valid params — its counters now update.
      final affected1 = await stmt1.executeSql(params: [42]);
      expect(affected1, 1);
      expect(stmt1.getLastInsertedId(), 42);
      // stmt2's counters must NOT have moved.
      expect(stmt2.getLastInsertedId(), 99,
          reason: 'stmt2 counters are isolated from stmt1 activity');
    } finally {
      await stmt1.close();
      await stmt2.close();
    }

    await db.closeDb();
    await db.dropDb();
  });

  // ── 17. closeDb cleans up forgotten statements ───────────────────────
  // The C lib's CloseDb refuses with SQLITE_BUSY if any handle is
  // live. DbasSqlite must finalise tracked statements before
  // attempting close so the user doesn't have to think about it.
  test('closeDb cleans up statements the caller forgot to close', () async {
    final db = await _createTestDb('forgotten_stmts.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE t (id INTEGER)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO t VALUES (1)');
      try { await stmt.executeSql(); } finally { await stmt.close(); }
    }

    // Prepare two and INTENTIONALLY do not close them.
    final orphan1 = await db.prepareQuery('SELECT id FROM t');
    final orphan2 = await db.prepareQuery('INSERT INTO t (id) VALUES (?)');

    // closeDb must succeed regardless and mark them closed.
    await db.closeDb();
    expect(orphan1.isClosed, isTrue);
    expect(orphan2.isClosed, isTrue);

    // A subsequent execute on a closed statement must throw.
    await expectLater(
      orphan2.executeSql(params: [2]),
      throwsA(isA<StateError>()),
    );

    await db.dropDb();
  });
}
