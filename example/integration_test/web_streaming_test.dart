// Integration tests for the per-row streaming SELECT path.
//
// These tests validate the v2.5.0 web change that replaced the eager
// `pool.query` materialisation with a `prepareQuery` / `bindParams` /
// `readRow` / `finalizeStmt` streaming pipeline (worker bundle v4.4.1).
// Native already streams, so the same tests must pass on both platforms
// — the point is that the observable behaviour is now identical:
//
//   - `executeReader` over a 10k-row table reads rows one at a time;
//     the order matches the SQL ordering exactly.
//   - `executeScalar` issues one `readRow` and returns; the rest of
//     the result set is never fetched.
//   - Column metadata (count + names) is available BEFORE the first
//     `readRow` step, including for empty result sets.
//   - SQLite INTEGER values outside the 32-bit range round-trip as
//     Dart ints (subject to the Dart-on-web 53-bit int limit, same as
//     any other large integer literal in Dart-on-web).
//   - A reader closed before exhaustion releases its worker handle so
//     subsequent statements aren't blocked by leaked state.
//
// Run on native:
//   cd example
//   flutter test integration_test/web_streaming_test.dart
//
// Run on web:
//   cd example
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/web_streaming_test.dart \
//     -d web-server --browser-name=chrome

import 'dart:typed_data';

import 'package:dbas_sqlite/dbas_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<DbasSqlite> newDb(String name, {int readerPoolSize = 4}) async {
    final db = await DbasSqlite.getInstance(
        dbName: name, workerPoolSize: 12);
    await db.dropDb();
    await db.openDb(readerPoolSize: readerPoolSize);
    return db;
  }

  Future<int> runSql(DbasSqlite db, String sql,
      {List<Object?>? params, Map<String, Object?>? nameParams}) async {
    final s = await db.prepareQuery(sql);
    try {
      return await s.executeSql(params: params, nameParams: nameParams);
    } finally {
      await s.close();
    }
  }

  // ── Per-row streaming over a wide result set ───────────────────────────

  testWidgets('executeReader streams 10000 rows in order', (tester) async {
    final db = await newDb('stream_10k.db');
    await runSql(db,
        'CREATE TABLE t (id INTEGER PRIMARY KEY, val INTEGER NOT NULL)');

    // Bulk insert inside a single transaction to keep the setup fast.
    await db.beginTransaction();
    for (int i = 1; i <= 10000; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [i, i * 2]);
    }
    await db.commit();

    final stmt = await db.prepareQuery('SELECT id, val FROM t ORDER BY id');
    final reader = await stmt.executeReader();
    int seen = 0;
    while (await reader.readRow()) {
      seen++;
      // Per-row assertion — a buffering regression that returned rows
      // out of order would surface as a wrong-id failure here, not
      // just a wrong final count.
      expect(reader.getColumnInt(0), seen,
          reason: 'row $seen has unexpected id');
      expect(reader.getColumnInt(1), seen * 2,
          reason: 'row $seen has unexpected val');
    }
    expect(seen, 10000);
    expect(reader.isClosed, isTrue,
        reason: 'reader auto-closes on SQLITE_DONE');

    await stmt.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ── executeScalar must not pull rows past the first ────────────────────

  testWidgets(
      'executeScalar over a large table returns the first row only',
      (tester) async {
    final db = await newDb('stream_scalar_first.db');
    await runSql(db,
        'CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT NOT NULL)');

    // Populate with 5000 rows. With the eager path, executeScalar would
    // fetch all 5000 even though only the first is read. With the
    // streaming path, exactly one `readRow` round-trip happens before
    // finalize. We can't observe round-trip count from the test, but
    // we *can* assert that the returned value is the FIRST row's val
    // (not an arbitrary one) and that the call completes promptly.
    await db.beginTransaction();
    for (int i = 1; i <= 5000; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?, ?)',
          params: [i, 'row_$i']);
    }
    await db.commit();

    final v = await (await db.prepareQuery(
            'SELECT val FROM t ORDER BY id ASC'))
        .executeScalar();
    expect(v, 'row_1');

    await db.closeDb();
    await db.dropDb();
  });

  // ── Column metadata is available even for empty result sets ────────────

  testWidgets('empty result set still exposes column count and names',
      (tester) async {
    final db = await newDb('stream_empty_meta.db');
    await runSql(db, 'CREATE TABLE t (a INTEGER, b TEXT, c REAL)');
    // No rows inserted.

    final stmt =
        await db.prepareQuery('SELECT a, b, c FROM t WHERE a > 1000');
    final reader = await stmt.executeReader();

    // Metadata must be populated BEFORE any readRow call — the eager
    // pre-2.5.0 web path could only recover names from row 0, so empty
    // results returned columnCount==0. The streaming path captures
    // metadata at prepare time.
    expect(reader.getColumnCount(), 3);
    expect(reader.getColumnName(0), 'a');
    expect(reader.getColumnName(1), 'b');
    expect(reader.getColumnName(2), 'c');

    expect(await reader.readRow(), isFalse,
        reason: 'no rows match the WHERE clause');
    expect(reader.isClosed, isTrue);

    await stmt.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ── Large INTEGER values round-trip as Dart int ────────────────────────

  testWidgets('SQLite INTEGER values outside int32 round-trip as Dart int',
      (tester) async {
    final db = await newDb('stream_bigint.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, big INTEGER)');

    // 2^53 - 1 — the largest integer Dart-on-web can represent
    // exactly. Both native (64-bit int) and web (53-bit int) preserve
    // this value losslessly.
    const big = 9007199254740991;
    await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [1, big]);

    final v = await (await db.prepareQuery('SELECT big FROM t WHERE id = 1'))
        .executeScalar();
    expect(v, big,
        reason: 'large INTEGER must come back as int, not text or BigInt');
    expect(v, isA<int>(),
        reason: 'public API exposes int (web: 53-bit, native: 64-bit)');

    // A smaller positive value (fits in int32) — the worker emits a JS
    // Number for this; classification must still be INTEGER.
    await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [2, 42]);
    expect(
        await (await db.prepareQuery('SELECT big FROM t WHERE id = 2'))
            .executeScalar(),
        42);

    // Negative large value — sign must round-trip.
    const negBig = -9007199254740991;
    await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [3, negBig]);
    expect(
        await (await db.prepareQuery('SELECT big FROM t WHERE id = 3'))
            .executeScalar(),
        negBig);

    await db.closeDb();
    await db.dropDb();
  });

  // ── Abandoned reader releases its worker handle ────────────────────────

  testWidgets(
      'closing a reader before exhaustion releases the prepared statement',
      (tester) async {
    final db = await newDb('stream_abandoned.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val INTEGER)');
    for (int i = 1; i <= 1000; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [i, i]);
    }

    // Read 5 rows out of 1000, then close. On web this must call
    // `finalizeStmt` so the worker's `_openStmts` map doesn't grow
    // monotonically; on native this releases the FFI stmt handle.
    {
      final stmt =
          await db.prepareQuery('SELECT id FROM t ORDER BY id');
      final reader = await stmt.executeReader();
      for (int i = 0; i < 5; i++) {
        expect(await reader.readRow(), isTrue);
      }
      await reader.close();
      await stmt.close();
    }

    // A fresh full read on the same table must still work end-to-end.
    // If the previous handle had leaked, the worker / native path
    // could either run out of slots or (on web) accumulate state that
    // surfaces as a `SQLITE_BUSY` later. Running a 1000-row scan now
    // is the indirect signal of correct cleanup.
    {
      final stmt =
          await db.prepareQuery('SELECT id FROM t ORDER BY id');
      final reader = await stmt.executeReader();
      int seen = 0;
      while (await reader.readRow()) {
        seen++;
        expect(reader.getColumnInt(0), seen);
      }
      expect(seen, 1000);
      await stmt.close();
    }

    await db.closeDb();
    await db.dropDb();
  });

  // ── Concurrent readers on different statements ─────────────────────────

  testWidgets('two readers on different statements coexist', (tester) async {
    final db = await newDb('stream_concurrent.db', readerPoolSize: 4);
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val INTEGER)');
    for (int i = 1; i <= 100; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [i, i]);
    }

    final stmtA =
        await db.prepareQuery('SELECT id FROM t WHERE id <= 50 ORDER BY id');
    final stmtB =
        await db.prepareQuery('SELECT id FROM t WHERE id > 50 ORDER BY id');
    final readerA = await stmtA.executeReader();
    final readerB = await stmtB.executeReader();

    // Interleave reads — A and B must not corrupt each other's
    // cursors. Native uses two independent stmt handles; web uses two
    // independent worker-side handles in `_openStmts`.
    int aSeen = 0;
    int bSeen = 0;
    bool aDone = false;
    bool bDone = false;
    while (!aDone || !bDone) {
      if (!aDone) {
        if (await readerA.readRow()) {
          aSeen++;
          expect(readerA.getColumnInt(0), aSeen);
        } else {
          aDone = true;
        }
      }
      if (!bDone) {
        if (await readerB.readRow()) {
          bSeen++;
          expect(readerB.getColumnInt(0), 50 + bSeen);
        } else {
          bDone = true;
        }
      }
    }
    expect(aSeen, 50);
    expect(bSeen, 50);

    await stmtA.close();
    await stmtB.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ── Mixed-type row payload ─────────────────────────────────────────────

  testWidgets('row payload preserves int / double / text / blob / null',
      (tester) async {
    final db = await newDb('stream_mixed_types.db');
    await runSql(db,
        'CREATE TABLE t (i INTEGER, d REAL, s TEXT, b BLOB, n INTEGER)');
    final blob = Uint8List.fromList([1, 2, 3, 4, 255]);
    final stmt =
        await db.prepareQuery('INSERT INTO t VALUES (?, ?, ?, ?, ?)');
    await stmt.executeSql(params: [42, 3.14, 'hello', blob, null]);
    await stmt.close();

    final reader = await (await db.prepareQuery(
            'SELECT i, d, s, b, n FROM t'))
        .executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 42);
    expect(reader.getColumnDouble(1), closeTo(3.14, 1e-9));
    expect(reader.getColumnText(2), 'hello');
    expect(reader.getColumnBlob(3), blob);
    expect(reader.isColumnNull(4), isTrue);
    expect(reader.getColumnNullableInt(4), isNull);
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });
}
