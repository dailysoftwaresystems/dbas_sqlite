import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';

/// Web integration tests using the SharedPool (1 writer + N reader workers).
///
/// Run with:
///   cd example
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/dbas_sqlite_web_test.dart \
///     -d web-server --browser-name=chrome
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<DbasSqlite> createWebDb(String name, {int readerPoolSize = 3}) async {
    final db = await DbasSqlite.getInstance(dbName: name, workerPoolSize: 3);
    await db.dropDb();
    await db.openDb(readerPoolSize: readerPoolSize);
    return db;
  }

  // ── Basic CRUD on web ─────────────────────────────────────────────────

  testWidgets('basic CRUD operations', (tester) async {
    final db = await createWebDb('web_crud.db');

    {
      final stmt = await db.prepareQuery('CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO items (id, name) VALUES (1, 'hello')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery('INSERT INTO items (id, name) VALUES (?, ?)');
      try {
        await stmt.executeSql(params: [2, 'world']);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT name FROM items ORDER BY id')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'hello');
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'world');
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ── Attach DB (bytes) ─────────────────────────────────────────────────

  testWidgets('attachDb from bytes then query', (tester) async {
    final src = await createWebDb('attach_src.db');
    {
      final stmt = await src.prepareQuery('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await src.prepareQuery("INSERT INTO products (id, name) VALUES (1, 'widget')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Close to flush WAL, then export content
    await src.closeDb();
    final exporter = await DbasSqlite.getInstance(dbName: 'attach_src.db');
    final bytes = await exporter.getContent();
    await exporter.openDb();

    final carrier = await DbasSqlite.getInstance(dbName: 'attached_web.db');
    final attached = await carrier.attachDb(bytes);

    final reader = await (await attached.prepareQuery('SELECT COUNT(*) FROM products')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await attached.closeDb();
    await attached.dropDb();
    await exporter.closeDb();
    await exporter.dropDb();
  });

  testWidgets('attachDb twice does not crash', (tester) async {
    final src = await createWebDb('attach2x_src.db');
    {
      final stmt = await src.prepareQuery('CREATE TABLE items (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await src.prepareQuery("INSERT INTO items (id, val) VALUES (1, 'first')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await src.closeDb();
    final exp = await DbasSqlite.getInstance(dbName: 'attach2x_src.db');
    final bytes = await exp.getContent();
    await exp.openDb();

    // First attach
    final c1 = await DbasSqlite.getInstance(dbName: 'attach2x.db');
    final a1 = await c1.attachDb(bytes);
    await a1.closeDb();

    // Second attach
    final c2 = await DbasSqlite.getInstance(dbName: 'attach2x.db');
    final a2 = await c2.attachDb(bytes);

    final reader = await (await a2.prepareQuery('SELECT val FROM items WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'first');
    await reader.close();

    await a2.closeDb();
    await a2.dropDb();
    await exp.closeDb();
    await exp.dropDb();
  });

  // ── Attach Stream DB ──────────────────────────────────────────────────

  testWidgets('attachStreamDb from byte stream then query', (tester) async {
    final src = await createWebDb('stream_src.db');
    {
      final stmt = await src.prepareQuery('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await src.prepareQuery("INSERT INTO products (id, name) VALUES (1, 'streamed')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await src.closeDb();
    final exp = await DbasSqlite.getInstance(dbName: 'stream_src.db');
    final bytes = await exp.getContent();
    await exp.openDb();

    final stream = Stream<List<int>>.value(bytes);
    final carrier = await DbasSqlite.getInstance(dbName: 'streamed_web.db');
    final streamed = await carrier.attachStreamDb(stream);

    final reader = await (await streamed.prepareQuery('SELECT name FROM products WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'streamed');
    await reader.close();

    await streamed.closeDb();
    await streamed.dropDb();
    await exp.closeDb();
    await exp.dropDb();
  });

  testWidgets('attachStreamDb twice does not crash', (tester) async {
    final src = await createWebDb('stream2x_src.db');
    {
      final stmt = await src.prepareQuery('CREATE TABLE items (id INTEGER PRIMARY KEY)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await src.prepareQuery('INSERT INTO items (id) VALUES (1)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await src.closeDb();
    final exp = await DbasSqlite.getInstance(dbName: 'stream2x_src.db');
    final bytes = await exp.getContent();
    await exp.openDb();

    // First stream attach
    final c1 = await DbasSqlite.getInstance(dbName: 'stream2x.db');
    final s1 = await c1.attachStreamDb(Stream<List<int>>.value(bytes));
    await s1.closeDb();

    // Second stream attach
    final c2 = await DbasSqlite.getInstance(dbName: 'stream2x.db');
    final s2 = await c2.attachStreamDb(Stream<List<int>>.value(bytes));

    final reader = await (await s2.prepareQuery('SELECT COUNT(*) FROM items')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await s2.closeDb();
    await s2.dropDb();
    await exp.closeDb();
    await exp.dropDb();
  });

  // ── Copy Database + Vacuum ────────────────────────────────────────────

  testWidgets('streamCopyDb then vacuum does not crash', (tester) async {
    final db = await createWebDb('copy_vac_src.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO products (id, name) VALUES (1, 'original')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Close/reopen to flush WAL
    await db.closeDb();
    final fresh = await DbasSqlite.getInstance(dbName: 'copy_vac_src.db');
    await fresh.openDb();

    // Copy
    await fresh.streamCopyDb('copy_vac_dest.db');

    // Open copy and verify
    final copy = await DbasSqlite.getInstance(dbName: 'copy_vac_dest.db');
    await copy.openDb();

    final reader = await (await copy.prepareQuery('SELECT COUNT(*) FROM products')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();
    await copy.closeDb();

    // Vacuum on source
    await fresh.vacuum();

    await fresh.closeDb();
    await fresh.dropDb();
    await copy.dropDb();
  });

  // ── Vacuum ────────────────────────────────────────────────────────────

  testWidgets('vacuum works after insert and delete', (tester) async {
    final db = await createWebDb('vacuum_web.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE big_tbl (id INTEGER PRIMARY KEY, data TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    for (int i = 1; i <= 20; i++) {
      {
        final stmt = await db.prepareQuery('INSERT INTO big_tbl (id, data) VALUES (?, ?)');
        try {
          await stmt.executeSql(params: [i, 'x' * 100]);
        } finally {
          await stmt.close();
        }
      }
    }
    {
      final stmt = await db.prepareQuery('DELETE FROM big_tbl WHERE id > 5');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db.vacuum();

    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM big_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 5);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ── Transactions ──────────────────────────────────────────────────────

  testWidgets('transaction commit and rollback', (tester) async {
    final db = await createWebDb('txn_web.db');
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
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (1, 'committed')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db.commit();

    await db.beginTransaction();
    {
      final stmt = await db.prepareQuery("INSERT INTO txn_tbl (id, val) VALUES (2, 'rolled_back')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db.rollback();

    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM txn_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 1);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  testWidgets('transaction() helper auto-commits and auto-rollbacks', (tester) async {
    final db = await createWebDb('txn_helper_web.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE th_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    await db.transaction((db) async {
      {
        final stmt = await db.prepareQuery("INSERT INTO th_tbl (id, val) VALUES (1, 'a')");
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
      {
        final stmt = await db.prepareQuery("INSERT INTO th_tbl (id, val) VALUES (2, 'b')");
        try {
          await stmt.executeSql();
        } finally {
          await stmt.close();
        }
      }
    });

    try {
      await db.transaction((db) async {
        {
          final stmt = await db.prepareQuery("INSERT INTO th_tbl (id, val) VALUES (3, 'c')");
          try {
            await stmt.executeSql();
          } finally {
            await stmt.close();
          }
        }
        throw Exception('force rollback');
      });
    } catch (_) {}

    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM th_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 2);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ── Concurrency: multiple DBs ─────────────────────────────────────────

  testWidgets('multiple databases operate independently via pool', (tester) async {
    final db1 = await createWebDb('conc_a.db');
    final db2 = await createWebDb('conc_b.db');

    {
      final stmt = await db1.prepareQuery('CREATE TABLE tbl_a (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db2.prepareQuery('CREATE TABLE tbl_b (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    Future<int> runWrite(DbasSqlite d, String sql) async {
      final s = await d.prepareQuery(sql);
      try { return await s.executeSql(); } finally { await s.close(); }
    }
    await Future.wait([
      runWrite(db1, "INSERT INTO tbl_a (id, val) VALUES (1, 'a')"),
      runWrite(db2, "INSERT INTO tbl_b (id, val) VALUES (1, 'b')"),
    ]);

    final reader = await (await db1.prepareQuery('SELECT val FROM tbl_a WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'a');
    await reader.close();

    final reader2 = await (await db2.prepareQuery('SELECT val FROM tbl_b WHERE id = 1')).executeReader();
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), 'b');
    await reader2.close();

    await db1.closeDb();
    await db1.dropDb();
    await db2.closeDb();
    await db2.dropDb();
  });

  // ── Concurrency: serialized writes on same DB ─────────────────────────

  testWidgets('concurrent writes on same DB are serialized', (tester) async {
    final db = await createWebDb('conc_writes.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE cw_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    Future<int> runWrite(String sql) async {
      final s = await db.prepareQuery(sql);
      try { return await s.executeSql(); } finally { await s.close(); }
    }
    await Future.wait([
      runWrite("INSERT INTO cw_tbl (id, val) VALUES (1, 'a')"),
      runWrite("INSERT INTO cw_tbl (id, val) VALUES (2, 'b')"),
      runWrite("INSERT INTO cw_tbl (id, val) VALUES (3, 'c')"),
    ]);

    final reader = await (await db.prepareQuery('SELECT COUNT(*) FROM cw_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 3);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ── getLastInsertedId after pool release ───────────────────────────────

  testWidgets('getLastInsertedId works after executeSql', (tester) async {
    final db = await createWebDb('last_id_web.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE li_tbl (id INTEGER PRIMARY KEY AUTOINCREMENT, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    final insertStmt = await db.prepareQuery("INSERT INTO li_tbl (val) VALUES ('test')");
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

  // ── Close/reopen cycle ────────────────────────────────────────────────

  testWidgets('close and reopen DB preserves data', (tester) async {
    final db = await createWebDb('reopen_web.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE ro_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO ro_tbl (id, val) VALUES (1, 'persisted')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    await db.closeDb();

    final reopened = await DbasSqlite.getInstance(dbName: 'reopen_web.db');
    await reopened.openDb();

    final reader = await (await reopened.prepareQuery('SELECT val FROM ro_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'persisted');
    await reader.close();

    await reopened.closeDb();
    await reopened.dropDb();
  });

  // ── Bug fixes regression tests ─────────────────────────────────────────

  testWidgets('getColumnDecimal throws on non-numeric text', (tester) async {
    final db = await createWebDb('decimal_err_web.db');
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

  testWidgets('getColumnTime throws on garbage input', (tester) async {
    final db = await createWebDb('time_err_web.db');
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

  testWidgets('getColumnDecimal works with valid Decimal', (tester) async {
    final db = await createWebDb('decimal_ok_web.db');
    {
      final stmt = await db.prepareQuery("CREATE TABLE d_tbl (id INTEGER PRIMARY KEY, val TEXT)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO d_tbl (id, val) VALUES (1, '123.456')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM d_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    final d = reader.getColumnDecimal(0);
    expect(d.toString(), '123.456');
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  testWidgets('getColumnTime works with valid HH:MM:SS.mmm', (tester) async {
    final db = await createWebDb('time_ok_web.db');
    {
      final stmt = await db.prepareQuery("CREATE TABLE t_tbl (id INTEGER PRIMARY KEY, val TEXT)");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await db.prepareQuery("INSERT INTO t_tbl (id, val) VALUES (1, '02:30:45.500')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT val FROM t_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    final d = reader.getColumnTime(0);
    expect(d.inHours, 2);
    expect(d.inMinutes % 60, 30);
    expect(d.inSeconds % 60, 45);
    expect(d.inMilliseconds % 1000, 500);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  testWidgets('named params with positional and named binds', (tester) async {
    final db = await createWebDb('named_web.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE n_tbl (id INTEGER PRIMARY KEY, name TEXT, val REAL)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    {
      final stmt = await db.prepareQuery('INSERT INTO n_tbl (id, name, val) VALUES (:id, :name, :val)');
      try {
        await stmt.executeSql(nameParams: {'id': 1, 'name': 'test', 'val': 3.14},);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT name, val FROM n_tbl WHERE id = :id')).executeReader(nameParams: {'id': 1});
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'test');
    expect(reader.getColumnDouble(1), closeTo(3.14, 0.001));
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  testWidgets('blob round-trip works on web', (tester) async {
    final db = await createWebDb('blob_web.db');
    {
      final stmt = await db.prepareQuery('CREATE TABLE b_tbl (id INTEGER PRIMARY KEY, data BLOB)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    final bytes = List<int>.generate(256, (i) => i);
    {
      final stmt = await db.prepareQuery('INSERT INTO b_tbl (id, data) VALUES (?, ?)');
      try {
        await stmt.executeSql(params: [1, bytes]);
      } finally {
        await stmt.close();
      }
    }

    final reader = await (await db.prepareQuery('SELECT data FROM b_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    final result = reader.getColumnBlob(0);
    expect(result.length, 256);
    expect(result[0], 0);
    expect(result[255], 255);
    await reader.close();

    await db.closeDb();
    await db.dropDb();
  });

  testWidgets('databaseExists is consistent with openDb', (tester) async {
    final db = await createWebDb('exists_web.db');
    expect(await db.databaseExists(), isTrue);
    await db.closeDb();
    await db.dropDb();
  });

  // ── Full lifecycle: create → close → export → attach → vacuum ─────────

  testWidgets('full export-import-vacuum lifecycle', (tester) async {
    final src = await createWebDb('lifecycle_src.db');
    {
      final stmt = await src.prepareQuery('CREATE TABLE lc_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    {
      final stmt = await src.prepareQuery("INSERT INTO lc_tbl (id, val) VALUES (1, 'lifecycle')");
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }

    // Close to flush WAL, export content
    await src.closeDb();
    final exporter = await DbasSqlite.getInstance(dbName: 'lifecycle_src.db');
    final bytes = await exporter.getContent();
    expect(bytes.length, greaterThan(0));
    await exporter.openDb();

    // Import to new DB
    final carrier = await DbasSqlite.getInstance(dbName: 'lifecycle_dest.db');
    final imported = await carrier.attachDb(bytes);

    final reader = await (await imported.prepareQuery('SELECT val FROM lc_tbl WHERE id = 1')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'lifecycle');
    await reader.close();

    // Vacuum on both should work
    await exporter.vacuum();
    await imported.vacuum();

    await exporter.closeDb();
    await exporter.dropDb();
    await imported.closeDb();
    await imported.dropDb();
  });

  // ── Multi-chunk streaming attach ──────────────────────────────────────

  testWidgets('attachStreamDb with multiple chunks preserves data', (tester) async {
    // Create source DB with enough data to produce multi-chunk export
    final src = await createWebDb('multi_chunk_src.db');
    {
      final stmt = await src.prepareQuery('CREATE TABLE mc_tbl (id INTEGER PRIMARY KEY, data TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    for (int i = 1; i <= 50; i++) {
      {
        final stmt = await src.prepareQuery('INSERT INTO mc_tbl (id, data) VALUES (?, ?)');
        try {
          await stmt.executeSql(params: [i, 'row_$i${'x' * 200}'],);
        } finally {
          await stmt.close();
        }
      }
    }

    // Export, then stream-attach as multiple smaller chunks
    await src.closeDb();
    final exporter = await DbasSqlite.getInstance(dbName: 'multi_chunk_src.db');
    final bytes = await exporter.getContent();
    await exporter.openDb();

    // Split exported bytes into 4 KB chunks to exercise the multi-chunk path
    const chunkSize = 4096;
    final chunks = <List<int>>[];
    for (int offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize > bytes.length) ? bytes.length : offset + chunkSize;
      chunks.add(bytes.sublist(offset, end));
    }
    // Verify we actually have multiple chunks
    expect(chunks.length, greaterThan(1));

    final stream = Stream<List<int>>.fromIterable(chunks);
    final carrier = await DbasSqlite.getInstance(dbName: 'multi_chunk_dest.db');
    final dest = await carrier.attachStreamDb(stream);

    final reader = await (await dest.prepareQuery('SELECT COUNT(*) FROM mc_tbl')).executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 50);
    await reader.close();

    // Verify specific row
    final reader2 = await (await dest.prepareQuery('SELECT data FROM mc_tbl WHERE id = 25')).executeReader();
    expect(await reader2.readRow(), isTrue);
    expect(reader2.getColumnText(0), startsWith('row_25'));
    await reader2.close();

    await dest.closeDb();
    await dest.dropDb();
    await exporter.closeDb();
    await exporter.dropDb();
  });

  // ── Export content round-trip ──────────────────────────────────────────

  testWidgets('getContent and attachDb produce identical data', (tester) async {
    final src = await createWebDb('export_rt_src.db');
    {
      final stmt = await src.prepareQuery('CREATE TABLE rt_tbl (id INTEGER PRIMARY KEY, val TEXT)');
      try {
        await stmt.executeSql();
      } finally {
        await stmt.close();
      }
    }
    for (int i = 1; i <= 10; i++) {
      {
        final stmt = await src.prepareQuery("INSERT INTO rt_tbl (id, val) VALUES (?, ?)");
        try {
          await stmt.executeSql(params: [i, 'val_$i']);
        } finally {
          await stmt.close();
        }
      }
    }

    // Export
    await src.closeDb();
    final exp = await DbasSqlite.getInstance(dbName: 'export_rt_src.db');
    final bytes = await exp.getContent();
    expect(bytes.length, greaterThan(0));
    await exp.openDb();

    // Import to new DB
    final carrier = await DbasSqlite.getInstance(dbName: 'export_rt_dest.db');
    final dest = await carrier.attachDb(bytes);

    // Verify all 10 rows
    final reader = await (await dest.prepareQuery('SELECT id, val FROM rt_tbl ORDER BY id')).executeReader();
    for (int i = 1; i <= 10; i++) {
      expect(await reader.readRow(), isTrue);
      expect(reader.getColumnInt(0), i);
      expect(reader.getColumnText(1), 'val_$i');
    }
    expect(await reader.readRow(), isFalse);

    await dest.closeDb();
    await dest.dropDb();
    await exp.closeDb();
    await exp.dropDb();
  });

  // ── dropDb on never-opened DB ─────────────────────────────────────────

  testWidgets('dropDb on never-opened DB does not crash', (tester) async {
    final db = await DbasSqlite.getInstance(dbName: 'never_opened.db');
    // dropDb should not throw even if the DB was never opened
    await db.dropDb();
  });
}
