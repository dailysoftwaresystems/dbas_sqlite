import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';

/// Web integration tests.
///
/// Run with:
///   cd example
///   flutter test integration_test/dbas_sqlite_web_test.dart -d chrome
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<DbasSqlite> createWebDb(String name, {int readerPoolSize = 4}) async {
    final db = await DbasSqlite.getInstance(dbName: name, workerPoolSize: 4);
    await db.dropDb();
    await db.openDb(readerPoolSize: readerPoolSize);
    return db;
  }

  // ── Basic CRUD on web ─────────────────────────────────────────────────

  testWidgets('basic CRUD operations', (tester) async {
    final db = await createWebDb('web_crud.db');

    await db.executeSql('CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)');
    await db.executeSql("INSERT INTO items (id, name) VALUES (1, 'hello')");
    await db.executeSql('INSERT INTO items (id, name) VALUES (?, ?)', params: [2, 'world']);

    await db.executeReader('SELECT name FROM items ORDER BY id');
    expect(await db.readRow(), isTrue);
    expect(db.getColumnText(0), 'hello');
    expect(await db.readRow(), isTrue);
    expect(db.getColumnText(0), 'world');
    expect(await db.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ── Attach DB (bytes) ─────────────────────────────────────────────────

  testWidgets('attachDb from bytes then query', (tester) async {
    final src = await createWebDb('attach_src.db');
    await src.executeSql('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)');
    await src.executeSql("INSERT INTO products (id, name) VALUES (1, 'widget')");

    // Close to flush WAL, then export content
    await src.closeDb();
    final exporter = await DbasSqlite.getInstance(dbName: 'attach_src.db');
    final bytes = await exporter.getContent();
    await exporter.openDb();

    final carrier = await DbasSqlite.getInstance(dbName: 'attached_web.db');
    final attached = await carrier.attachDb(bytes);

    await attached.executeReader('SELECT COUNT(*) FROM products');
    expect(await attached.readRow(), isTrue);
    expect(attached.getColumnInt(0), 1);
    await attached.closeReader();

    await attached.closeDb();
    await attached.dropDb();
    await exporter.closeDb();
    await exporter.dropDb();
  });

  testWidgets('attachDb twice does not crash', (tester) async {
    final src = await createWebDb('attach2x_src.db');
    await src.executeSql('CREATE TABLE items (id INTEGER PRIMARY KEY, val TEXT)');
    await src.executeSql("INSERT INTO items (id, val) VALUES (1, 'first')");

    await src.closeDb();
    final exp = await DbasSqlite.getInstance(dbName: 'attach2x_src.db');
    final bytes = await exp.getContent();
    await exp.openDb();

    // First attach
    final c1 = await DbasSqlite.getInstance(dbName: 'attach2x.db');
    final a1 = await c1.attachDb(bytes);
    await a1.closeDb();

    // Second attach — was crashing with "memory access out of bounds"
    final c2 = await DbasSqlite.getInstance(dbName: 'attach2x.db');
    final a2 = await c2.attachDb(bytes);

    await a2.executeReader('SELECT val FROM items WHERE id = 1');
    expect(await a2.readRow(), isTrue);
    expect(a2.getColumnText(0), 'first');
    await a2.closeReader();

    await a2.closeDb();
    await a2.dropDb();
    await exp.closeDb();
    await exp.dropDb();
  });

  // ── Attach Stream DB ──────────────────────────────────────────────────

  testWidgets('attachStreamDb from byte stream then query', (tester) async {
    final src = await createWebDb('stream_src.db');
    await src.executeSql('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)');
    await src.executeSql("INSERT INTO products (id, name) VALUES (1, 'streamed')");

    await src.closeDb();
    final exp = await DbasSqlite.getInstance(dbName: 'stream_src.db');
    final bytes = await exp.getContent();
    await exp.openDb();

    final stream = Stream<List<int>>.value(bytes);
    final carrier = await DbasSqlite.getInstance(dbName: 'streamed_web.db');
    final streamed = await carrier.attachStreamDb(stream);

    await streamed.executeReader('SELECT name FROM products WHERE id = 1');
    expect(await streamed.readRow(), isTrue);
    expect(streamed.getColumnText(0), 'streamed');
    await streamed.closeReader();

    await streamed.closeDb();
    await streamed.dropDb();
    await exp.closeDb();
    await exp.dropDb();
  });

  testWidgets('attachStreamDb twice does not crash', (tester) async {
    final src = await createWebDb('stream2x_src.db');
    await src.executeSql('CREATE TABLE items (id INTEGER PRIMARY KEY)');
    await src.executeSql('INSERT INTO items (id) VALUES (1)');

    await src.closeDb();
    final exp = await DbasSqlite.getInstance(dbName: 'stream2x_src.db');
    final bytes = await exp.getContent();
    await exp.openDb();

    // First stream attach
    final c1 = await DbasSqlite.getInstance(dbName: 'stream2x.db');
    final s1 = await c1.attachStreamDb(Stream<List<int>>.value(bytes));
    await s1.closeDb();

    // Second stream attach — was crashing
    final c2 = await DbasSqlite.getInstance(dbName: 'stream2x.db');
    final s2 = await c2.attachStreamDb(Stream<List<int>>.value(bytes));

    await s2.executeReader('SELECT COUNT(*) FROM items');
    expect(await s2.readRow(), isTrue);
    expect(s2.getColumnInt(0), 1);
    await s2.closeReader();

    await s2.closeDb();
    await s2.dropDb();
    await exp.closeDb();
    await exp.dropDb();
  });

  // ── Copy Database + Vacuum ────────────────────────────────────────────

  testWidgets('streamCopyDb then vacuum does not crash', (tester) async {
    final db = await createWebDb('copy_vac_src.db');
    await db.executeSql('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)');
    await db.executeSql("INSERT INTO products (id, name) VALUES (1, 'original')");

    // Close/reopen to flush WAL
    await db.closeDb();
    final fresh = await DbasSqlite.getInstance(dbName: 'copy_vac_src.db');
    await fresh.openDb();

    // Copy
    await fresh.streamCopyDb('copy_vac_dest.db');

    // Open copy and verify
    final copy = await DbasSqlite.getInstance(dbName: 'copy_vac_dest.db');
    await copy.openDb();

    await copy.executeReader('SELECT COUNT(*) FROM products');
    expect(await copy.readRow(), isTrue);
    expect(copy.getColumnInt(0), 1);
    await copy.closeReader();
    await copy.closeDb();

    // Vacuum on source — was crashing after copy
    await fresh.vacuum();

    await fresh.closeDb();
    await fresh.dropDb();
    await copy.dropDb();
  });

  // ── Vacuum ────────────────────────────────────────────────────────────

  testWidgets('vacuum works after insert and delete', (tester) async {
    final db = await createWebDb('vacuum_web.db');
    await db.executeSql('CREATE TABLE big_tbl (id INTEGER PRIMARY KEY, data TEXT)');

    for (int i = 1; i <= 20; i++) {
      await db.executeSql('INSERT INTO big_tbl (id, data) VALUES (?, ?)', params: [i, 'x' * 100]);
    }
    await db.executeSql('DELETE FROM big_tbl WHERE id > 5');
    await db.vacuum();

    await db.executeReader('SELECT COUNT(*) FROM big_tbl');
    expect(await db.readRow(), isTrue);
    expect(db.getColumnInt(0), 5);
    await db.closeReader();

    await db.closeDb();
    await db.dropDb();
  });

  // ── Transactions ──────────────────────────────────────────────────────

  testWidgets('transaction commit and rollback', (tester) async {
    final db = await createWebDb('txn_web.db');
    await db.executeSql('CREATE TABLE txn_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await db.beginTransaction();
    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (1, 'committed')");
    await db.commit();

    await db.beginTransaction();
    await db.executeSql("INSERT INTO txn_tbl (id, val) VALUES (2, 'rolled_back')");
    await db.rollback();

    await db.executeReader('SELECT COUNT(*) FROM txn_tbl');
    expect(await db.readRow(), isTrue);
    expect(db.getColumnInt(0), 1);
    await db.closeReader();

    await db.closeDb();
    await db.dropDb();
  });

  testWidgets('transaction() helper auto-commits and auto-rollbacks', (tester) async {
    final db = await createWebDb('txn_helper_web.db');
    await db.executeSql('CREATE TABLE th_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await db.transaction((db) async {
      await db.executeSql("INSERT INTO th_tbl (id, val) VALUES (1, 'a')");
      await db.executeSql("INSERT INTO th_tbl (id, val) VALUES (2, 'b')");
    });

    try {
      await db.transaction((db) async {
        await db.executeSql("INSERT INTO th_tbl (id, val) VALUES (3, 'c')");
        throw Exception('force rollback');
      });
    } catch (_) {}

    await db.executeReader('SELECT COUNT(*) FROM th_tbl');
    expect(await db.readRow(), isTrue);
    expect(db.getColumnInt(0), 2);
    await db.closeReader();

    await db.closeDb();
    await db.dropDb();
  });

  // ── Concurrency: multiple DBs ─────────────────────────────────────────

  testWidgets('multiple databases operate independently via pool', (tester) async {
    final db1 = await createWebDb('conc_a.db');
    final db2 = await createWebDb('conc_b.db');

    await db1.executeSql('CREATE TABLE tbl_a (id INTEGER PRIMARY KEY, val TEXT)');
    await db2.executeSql('CREATE TABLE tbl_b (id INTEGER PRIMARY KEY, val TEXT)');

    await Future.wait([
      db1.executeSql("INSERT INTO tbl_a (id, val) VALUES (1, 'a')"),
      db2.executeSql("INSERT INTO tbl_b (id, val) VALUES (1, 'b')"),
    ]);

    await db1.executeReader('SELECT val FROM tbl_a WHERE id = 1');
    expect(await db1.readRow(), isTrue);
    expect(db1.getColumnText(0), 'a');
    await db1.closeReader();

    await db2.executeReader('SELECT val FROM tbl_b WHERE id = 1');
    expect(await db2.readRow(), isTrue);
    expect(db2.getColumnText(0), 'b');
    await db2.closeReader();

    await db1.closeDb();
    await db1.dropDb();
    await db2.closeDb();
    await db2.dropDb();
  });

  // ── Concurrency: serialized writes on same DB ─────────────────────────

  testWidgets('concurrent writes on same DB are serialized', (tester) async {
    final db = await createWebDb('conc_writes.db');
    await db.executeSql('CREATE TABLE cw_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    await Future.wait([
      db.executeSql("INSERT INTO cw_tbl (id, val) VALUES (1, 'a')"),
      db.executeSql("INSERT INTO cw_tbl (id, val) VALUES (2, 'b')"),
      db.executeSql("INSERT INTO cw_tbl (id, val) VALUES (3, 'c')"),
    ]);

    await db.executeReader('SELECT COUNT(*) FROM cw_tbl');
    expect(await db.readRow(), isTrue);
    expect(db.getColumnInt(0), 3);
    await db.closeReader();

    await db.closeDb();
    await db.dropDb();
  });

  // ── Concurrency: concurrent transactions ──────────────────────────────

  testWidgets('concurrent transactions are serialized', (tester) async {
    final db = await createWebDb('conc_txn.db');
    await db.executeSql('CREATE TABLE ct_tbl (id INTEGER PRIMARY KEY, val TEXT)');

    final order = <int>[];

    await Future.wait([
      db.transaction((db) async {
        await db.executeSql("INSERT INTO ct_tbl (id, val) VALUES (1, 'a')");
        order.add(1);
      }),
      db.transaction((db) async {
        await db.executeSql("INSERT INTO ct_tbl (id, val) VALUES (2, 'b')");
        order.add(2);
      }),
    ]);

    expect(order.length, 2);
    expect(order.toSet(), {1, 2});

    await db.executeReader('SELECT COUNT(*) FROM ct_tbl');
    expect(await db.readRow(), isTrue);
    expect(db.getColumnInt(0), 2);
    await db.closeReader();

    await db.closeDb();
    await db.dropDb();
  });

  // ── getLastInsertedId after pool release ───────────────────────────────

  testWidgets('getLastInsertedId works after executeSql', (tester) async {
    final db = await createWebDb('last_id_web.db');
    await db.executeSql('CREATE TABLE li_tbl (id INTEGER PRIMARY KEY AUTOINCREMENT, val TEXT)');
    await db.executeSql("INSERT INTO li_tbl (val) VALUES ('test')");

    final lastId = db.getLastInsertedId();
    expect(lastId, greaterThan(0));

    await db.closeDb();
    await db.dropDb();
  });

  // ── Close/reopen cycle ────────────────────────────────────────────────

  testWidgets('close and reopen DB preserves data', (tester) async {
    final db = await createWebDb('reopen_web.db');
    await db.executeSql('CREATE TABLE ro_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await db.executeSql("INSERT INTO ro_tbl (id, val) VALUES (1, 'persisted')");
    await db.closeDb();

    final reopened = await DbasSqlite.getInstance(dbName: 'reopen_web.db');
    await reopened.openDb();

    await reopened.executeReader('SELECT val FROM ro_tbl WHERE id = 1');
    expect(await reopened.readRow(), isTrue);
    expect(reopened.getColumnText(0), 'persisted');
    await reopened.closeReader();

    await reopened.closeDb();
    await reopened.dropDb();
  });

  // ── Full lifecycle: create → close → export → attach → vacuum ─────────

  testWidgets('full export-import-vacuum lifecycle', (tester) async {
    final src = await createWebDb('lifecycle_src.db');
    await src.executeSql('CREATE TABLE lc_tbl (id INTEGER PRIMARY KEY, val TEXT)');
    await src.executeSql("INSERT INTO lc_tbl (id, val) VALUES (1, 'lifecycle')");

    // Close to flush WAL, export content
    await src.closeDb();
    final exporter = await DbasSqlite.getInstance(dbName: 'lifecycle_src.db');
    final bytes = await exporter.getContent();
    expect(bytes.length, greaterThan(0));
    await exporter.openDb();

    // Import to new DB
    final carrier = await DbasSqlite.getInstance(dbName: 'lifecycle_dest.db');
    final imported = await carrier.attachDb(bytes);

    await imported.executeReader('SELECT val FROM lc_tbl WHERE id = 1');
    expect(await imported.readRow(), isTrue);
    expect(imported.getColumnText(0), 'lifecycle');
    await imported.closeReader();

    // Vacuum on both should work
    await exporter.vacuum();
    await imported.vacuum();

    await exporter.closeDb();
    await exporter.dropDb();
    await imported.closeDb();
    await imported.dropDb();
  });
}
