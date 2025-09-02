import 'dart:io';

import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() async {
  test('Test Open, create table, insert, select and close', () async {
    String dbName = 'test.db';
    final dbasSqlite = await DbasSqlite.getInstance(dbName: dbName);

    File dbFile = File(await dbasSqlite.getAppDatabasePath(dbName: dbName));
    if (await dbasSqlite.databaseExists()) {
      dbFile.delete();
    }

    await dbasSqlite.openDb();

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

    await dbasSqlite.executeReader("SELECT name, email FROM users where id > :id", params: [0]);
    int colCount = dbasSqlite.getColumnCount();

    List<List<Object?>> users = [];
    while (await dbasSqlite.readRow()) {
      List<Object?> user = [];
      for (int colIdx = 0; colIdx < colCount; colIdx++) {
        SqliteColumnType type = dbasSqlite.getColumnType(colIdx);

        if (type == SqliteColumnType.nullType) {
          user.add(null);
        } else if (type == SqliteColumnType.integer) {
          user.add(dbasSqlite.getColumnInt(colIdx));
        } else if (type == SqliteColumnType.double) {
          user.add(dbasSqlite.getColumnDouble(colIdx));
        } else if (type == SqliteColumnType.text) {
          user.add(dbasSqlite.getColumnText(colIdx));
        } else if (type == SqliteColumnType.blob) {
          user.add(dbasSqlite.getColumnBlob(colIdx));
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

    File testDbFile = File(testDbPath);
    if (await testDbasSqlite.databaseExists()) {
      testDbFile.delete();
    }

    await testDbasSqlite.openDb();
    await testDbasSqlite.executeSql('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    String dbName = 'test_attach2.db';
    DbasSqlite dbasSqlite = await DbasSqlite.getInstance(dbName: dbName);

    File dbFile = File(await dbasSqlite.getAppDatabasePath());
    List<int> bytes = await File(testDbPath).readAsBytes();
    dbasSqlite = await dbasSqlite.attachDb(bytes);

    expect(await dbasSqlite.databaseExists(), isTrue, reason: 'DB file should exist after opening the database (native).');
    expect(await dbFile.exists(), isTrue, reason: 'DB file should exist after opening the database.');
    expect(dbasSqlite.isOpened(), isTrue, reason: 'Database should be opened after calling openDb.');
  });
}
