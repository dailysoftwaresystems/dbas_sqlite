import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';
import 'package:flutter/material.dart';

import '../widgets/operation_button.dart';

class CrudTab extends StatelessWidget {
  final DbasSqlite? db;
  final bool isLoading;
  final void Function(String) onLog;
  final Future<void> Function(Future<void> Function()) runOp;

  const CrudTab({
    super.key,
    required this.db,
    required this.isLoading,
    required this.onLog,
    required this.runOp,
  });

  bool get _enabled => !isLoading && db != null;

  Future<void> _select() => runOp(() async {
    onLog('[...] Running SELECT...');
    try {
      await db!.executeReader(
        'SELECT id, name, price, quantity, created_at FROM products ORDER BY id DESC LIMIT 10',
      );
      final rows = <String>[];
      try {
        while (await db!.readRow()) {
          final id = db!.getColumnInt(0);
          final name = db!.getColumnText(1);
          final price = db!.getColumnDouble(2);
          final qty = db!.getColumnInt(3);
          final createdAt = db!.getColumnText(4);
          rows.add('  #$id | $name | \$$price | qty:$qty | $createdAt');
        }
      } finally {
        await db!.closeReader();
      }
      if (rows.isEmpty) {
        onLog('[OK] SELECT: no rows found');
      } else {
        onLog('[OK] SELECT: ${rows.length} row(s):');
        for (final row in rows) {
          onLog(row);
        }
      }
    } catch (e) {
      onLog('[ERROR] SELECT: $e');
    }
  });

  Future<void> _insertPositional() => runOp(() async {
    onLog('[...] Inserting with positional params...');
    try {
      final name = 'Widget-${DateTime.now().millisecondsSinceEpoch % 10000}';
      await db!.executeSql(
        'INSERT INTO products (name, price, quantity, created_at) VALUES (?, ?, ?, ?)',
        params: [name, 9.99, 10, DateTime.now().toIso8601String()],
      );
      final id = db!.getLastInsertedId();
      onLog('[OK] Inserted "$name" with id=$id (positional params)');
    } catch (e) {
      onLog('[ERROR] INSERT (positional): $e');
    }
  });

  Future<void> _insertNamed() => runOp(() async {
    onLog('[...] Inserting with named params...');
    try {
      final name = 'Gadget-${DateTime.now().millisecondsSinceEpoch % 10000}';
      await db!.executeSql(
        'INSERT INTO products (name, price, quantity, created_at) VALUES (:name, :price, :quantity, :created_at)',
        nameParams: {
          'name': name,
          'price': 24.50,
          'quantity': 5,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
      final id = db!.getLastInsertedId();
      onLog('[OK] Inserted "$name" with id=$id (named params)');
    } catch (e) {
      onLog('[ERROR] INSERT (named): $e');
    }
  });

  Future<void> _update() => runOp(() async {
    onLog('[...] Running UPDATE...');
    try {
      final affected = await db!.executeSql(
        'UPDATE products SET price = price * 1.1 WHERE id = (SELECT MAX(id) FROM products)',
      );
      onLog('[OK] UPDATE: $affected row(s) affected (price +10% on last product)');
    } catch (e) {
      onLog('[ERROR] UPDATE: $e');
    }
  });

  Future<void> _delete() => runOp(() async {
    onLog('[...] Running DELETE...');
    try {
      final affected = await db!.executeSql(
        'DELETE FROM products WHERE id = (SELECT MIN(id) FROM products)',
      );
      onLog('[OK] DELETE: $affected row(s) deleted (oldest product)');
    } catch (e) {
      onLog('[ERROR] DELETE: $e');
    }
  });

  Future<void> _transactionInsert() => runOp(() async {
    onLog('[...] Running transactioned bulk insert...');
    try {
      await db!.transaction((tx) async {
        for (int i = 1; i <= 5; i++) {
          await tx.executeSql(
            'INSERT INTO products (name, price, quantity, created_at) VALUES (?, ?, ?, ?)',
            params: [
              'Batch-$i',
              (i * 3.33),
              i * 10,
              DateTime.now().toIso8601String(),
            ],
          );
        }
      });

      await db!.executeReader('SELECT COUNT(*) FROM products');
      int count = 0;
      try {
        if (await db!.readRow()) {
          count = db!.getColumnInt(0);
        }
      } finally {
        await db!.closeReader();
      }

      onLog('[OK] Transaction committed: 5 rows inserted. Total products: $count');
    } catch (e) {
      onLog('[ERROR] Transaction: $e');
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
            'CRUD Operations',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const Text(
          'All operations target the "products" table.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        OperationButton(
          label: 'SELECT (last 10 rows)',
          icon: Icons.search,
          enabled: _enabled,
          onPressed: _select,
        ),
        OperationButton(
          label: 'INSERT (positional params)',
          icon: Icons.add,
          enabled: _enabled,
          onPressed: _insertPositional,
        ),
        OperationButton(
          label: 'INSERT (named params)',
          icon: Icons.add_circle_outline,
          enabled: _enabled,
          onPressed: _insertNamed,
        ),
        OperationButton(
          label: 'UPDATE (last product +10%)',
          icon: Icons.edit,
          enabled: _enabled,
          onPressed: _update,
        ),
        OperationButton(
          label: 'DELETE (oldest product)',
          icon: Icons.delete,
          enabled: _enabled,
          onPressed: _delete,
        ),
        OperationButton(
          label: 'Transaction (insert 5 rows)',
          icon: Icons.playlist_add_check,
          enabled: _enabled,
          onPressed: _transactionInsert,
        ),
      ],
    );
  }
}
