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

  test('Open and Close test db', () async {
    final dbasSqlite = await DbasSqlite.getInstance();
    await dbasSqlite.openDb(db);
    expect(dbasSqlite.isOpened(), isTrue);
    await dbasSqlite.closeDb();
    expect(dbasSqlite.isOpened(), isFalse);
  });
}
