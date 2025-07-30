import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

void main() async {
  String dbPath = path.join(Directory.current.path, 'test', 'db');
  String db = path.join(Directory.current.path, 'test', 'db', 'test.db');

  final dirDbPath = Directory(dbPath);
  final fileDb = File(db);

  if (!await dirDbPath.exists()) {
    print('Creating parent test db path in $dbPath.');
    await dirDbPath.create(recursive: true);
  }

  if (await fileDb.exists()) {
    await fileDb.delete();
    print('Deleting previously existing test db in $dbPath.');
  }

  test('Test Open, create table, insert, select and close', () async {
    final dbasSqlite = await DbasSqlite.getInstance();
    await dbasSqlite.openDb(db);
    expect(dbasSqlite.isOpened(), isTrue);

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
    while (dbasSqlite.readRow()) {
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
}
