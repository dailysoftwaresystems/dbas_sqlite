import 'package:dbas_sqlite/dbas_sqlite.dart';
import 'package:flutter/material.dart';

import '../widgets/operation_button.dart';

class SetupTab extends StatelessWidget {
  final DbasSqlite? db;
  final bool isLoading;
  final void Function(String) onLog;
  final void Function(DbasSqlite?) onDbChanged;
  final Future<void> Function(Future<void> Function()) runOp;

  const SetupTab({
    super.key,
    required this.db,
    required this.isLoading,
    required this.onLog,
    required this.onDbChanged,
    required this.runOp,
  });

  Future<void> _openDb() => runOp(() async {
    onLog('[...] Opening database...');
    try {
      final instance = await DbasSqlite.getInstance(dbName: 'example.db');
      await instance.openDb();

      final createStmt = await instance.prepareQuery('''
        CREATE TABLE IF NOT EXISTS products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      try {
        await createStmt.executeSql();
      } finally {
        await createStmt.close();
      }

      onDbChanged(instance);

      final path = await instance.getAppDatabasePath();
      onLog('[OK] Database opened at: $path');
      onLog('[OK] Table "products" ready');
    } catch (e) {
      onLog('[ERROR] Open DB: $e');
    }
  });

  Future<void> _closeDb() => runOp(() async {
    onLog('[...] Closing database...');
    try {
      await db!.closeDb();
      onDbChanged(null);
      onLog('[OK] Database closed');
    } catch (e) {
      onLog('[ERROR] Close DB: $e');
    }
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Database Lifecycle',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const Text(
          'Open creates a "products" table. Close releases all connections.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        OperationButton(
          label: 'Open Database',
          icon: Icons.folder_open,
          enabled: !isLoading && db == null,
          onPressed: _openDb,
        ),
        OperationButton(
          label: 'Close Database',
          icon: Icons.close,
          enabled: !isLoading && db != null,
          onPressed: _closeDb,
        ),
      ],
    );
  }
}
