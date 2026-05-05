import 'dart:async';

import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';
import 'package:flutter/material.dart';

import '../widgets/operation_button.dart';

class DbOpsTab extends StatelessWidget {
  final DbasSqlite? db;
  final bool isLoading;
  final void Function(String) onLog;
  final void Function(DbasSqlite?) onDbChanged;
  final Future<void> Function(Future<void> Function()) runOp;

  const DbOpsTab({
    super.key,
    required this.db,
    required this.isLoading,
    required this.onLog,
    required this.onDbChanged,
    required this.runOp,
  });

  bool get _enabled => !isLoading && db != null;

  /// Closes the current DB (flushes WAL) and reopens it.
  /// Returns the content bytes read while the DB was closed.
  Future<List<int>> _exportContent() async {
    final dbName = db!.dbName;
    await db!.closeDb();
    onDbChanged(null);

    final fresh = await DbasSqlite.getInstance(dbName: dbName);
    final bytes = await fresh.getContent();

    await fresh.openDb();
    onDbChanged(fresh);
    return bytes;
  }

  Future<void> _attachDb() => runOp(() async {
    onLog('[...] Attaching DB from bytes...');
    try {
      // Close/reopen to flush WAL journal into main DB file
      final bytes = await _exportContent();
      onLog('[...] Exported ${bytes.length} bytes from current DB');

      final carrier = await DbasSqlite.getInstance(dbName: 'attached.db');
      final attached = await carrier.attachDb(bytes);

      final stmt = await attached.prepareQuery('SELECT COUNT(*) FROM products');
      int count = 0;
      try {
        final reader = await stmt.executeReader();
        try {
          if (await reader.readRow()) count = reader.getColumnInt(0);
        } finally {
          await reader.close();
        }
      } finally {
        await stmt.close();
      }

      await attached.closeDb();
      onLog('[OK] Attached "attached.db" from ${bytes.length} bytes, contains $count products');
    } catch (e) {
      onLog('[ERROR] Attach DB: $e');
    }
  });

  Future<void> _attachStreamDb() => runOp(() async {
    onLog('[...] Attaching DB from stream...');
    try {
      // Close/reopen to flush WAL journal into main DB file
      final bytes = await _exportContent();
      onLog('[...] Exported ${bytes.length} bytes, streaming to new DB...');

      final stream = Stream<List<int>>.value(bytes);
      final carrier = await DbasSqlite.getInstance(dbName: 'streamed.db');
      final streamed = await carrier.attachStreamDb(stream);

      final stmt = await streamed.prepareQuery('SELECT COUNT(*) FROM products');
      int count = 0;
      try {
        final reader = await stmt.executeReader();
        try {
          if (await reader.readRow()) count = reader.getColumnInt(0);
        } finally {
          await reader.close();
        }
      } finally {
        await stmt.close();
      }

      await streamed.closeDb();
      onLog('[OK] Stream-attached "streamed.db" from ${bytes.length} bytes, contains $count products');
    } catch (e) {
      onLog('[ERROR] Attach Stream DB: $e');
    }
  });

  Future<void> _copyDb() => runOp(() async {
    onLog('[...] Copying database...');
    try {
      final dbName = db!.dbName;

      // Close/reopen to flush WAL journal into main DB file
      await db!.closeDb();
      onDbChanged(null);

      final fresh = await DbasSqlite.getInstance(dbName: dbName);
      await fresh.openDb();
      onDbChanged(fresh);

      await fresh.streamCopyDb('example_copy.db');

      final copy = await DbasSqlite.getInstance(dbName: 'example_copy.db');
      await copy.openDb();

      final stmt = await copy.prepareQuery('SELECT COUNT(*) FROM products');
      int count = 0;
      try {
        final reader = await stmt.executeReader();
        try {
          if (await reader.readRow()) count = reader.getColumnInt(0);
        } finally {
          await reader.close();
        }
      } finally {
        await stmt.close();
      }

      await copy.closeDb();
      onLog('[OK] Copied to "example_copy.db", contains $count products');
    } catch (e) {
      onLog('[ERROR] Copy DB: $e');
    }
  });

  Future<void> _vacuum() => runOp(() async {
    onLog('[...] Running VACUUM...');
    try {
      await db!.vacuum();
      onLog('[OK] VACUUM completed — database compacted');
    } catch (e) {
      onLog('[ERROR] Vacuum: $e');
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
            'Database Operations',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const Text(
          'Attach, copy, and maintain databases.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        OperationButton(
          label: 'Attach DB (bytes)',
          icon: Icons.file_download,
          enabled: _enabled,
          onPressed: _attachDb,
        ),
        OperationButton(
          label: 'Attach DB (stream)',
          icon: Icons.stream,
          enabled: _enabled,
          onPressed: _attachStreamDb,
        ),
        OperationButton(
          label: 'Copy Database',
          icon: Icons.copy,
          enabled: _enabled,
          onPressed: _copyDb,
        ),
        OperationButton(
          label: 'Vacuum',
          icon: Icons.compress,
          enabled: _enabled,
          onPressed: _vacuum,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
          ),
        ),
      ],
    );
  }
}
