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

  // ── Mixed positional + named params (T1) ───────────────────────────────
  //
  // The web bind buffer keeps positional and named values in two
  // separate maps and flushes them via two `bindParams` worker calls
  // when both are present. Native FFI replays each bind individually.
  // This test pins down that the unified path treats both sets as
  // active on every platform — a regression to "positional wins,
  // named silently dropped" would surface here as a failed UPDATE.

  testWidgets('mixed positional + named params both bind correctly',
      (tester) async {
    final db = await newDb('stream_mixed_binds.db');
    await runSql(db,
        'CREATE TABLE t (id INTEGER PRIMARY KEY, label TEXT, val INTEGER)');
    await runSql(db, "INSERT INTO t VALUES (1, 'a', 10)");
    await runSql(db, "INSERT INTO t VALUES (2, 'b', 20)");

    // SQL with one positional marker (?) and one named (:idMatch).
    // SQLite numbers parameters left-to-right regardless of marker
    // type, so `?` is slot 1 and `:idMatch` is slot 2 for this SQL.
    // Verifying that BOTH shapes bind correctly when used together
    // is the point of this test — a regression where one shape
    // silently drops would leave slot 2 unbound (NULL), so the
    // UPDATE would match no rows.
    final stmt = await db.prepareQuery(
        'UPDATE t SET val = ? WHERE id = :idMatch');
    final affected = await stmt.executeSql(
      params: [99],
      nameParams: <String, Object?>{'idMatch': 1},
    );
    await stmt.close();
    expect(affected, 1,
        reason: 'mixed binds must update exactly id=1; got '
            'affected=$affected — likely one bind shape was dropped');

    // Verify the row mutated as intended.
    expect(
        await (await db.prepareQuery('SELECT val FROM t WHERE id = 1'))
            .executeScalar(),
        99);
    expect(
        await (await db.prepareQuery('SELECT val FROM t WHERE id = 2'))
            .executeScalar(),
        20,
        reason: 'unrelated row must be unchanged');

    await db.closeDb();
    await db.dropDb();
  });

  // ── Sparse positional binds (T1 sibling) ───────────────────────────────
  //
  // Binding only slots 1 and 3 (skipping 2) must produce a dense
  // payload `[v1, null, v3]` so SQLite slot 2 receives NULL rather
  // than shifting v3 into slot 2.

  testWidgets('sparse positional binds preserve slot ordering',
      (tester) async {
    final db = await newDb('stream_sparse_binds.db');
    await runSql(db, 'CREATE TABLE t (a INTEGER, b TEXT, c INTEGER)');

    final stmt = await db.prepareQuery('INSERT INTO t VALUES (?, ?, ?)');
    // Build the bind buffer manually so slot 2 stays unset, then run.
    // `executeSql(params: [v, null, v])` would also work but doesn't
    // exercise the sparse-fold path in `_WebStmtState.mergedParams`.
    stmt.bindInt(1, 7);
    stmt.bindInt(3, 9);
    final affected = await stmt.executeSql();
    await stmt.close();
    expect(affected, 1);

    final reader =
        await (await db.prepareQuery('SELECT a, b, c FROM t'))
            .executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnInt(0), 7);
    expect(reader.isColumnNull(1), isTrue,
        reason: 'slot 2 must bind NULL, not shift slot 3 in');
    expect(reader.getColumnInt(2), 9);
    expect(await reader.readRow(), isFalse);

    await db.closeDb();
    await db.dropDb();
  });

  // ── Statement reuse after a reader closes (T2) ─────────────────────────
  //
  // `Statement.executeReader` allocates a fresh handle per call. A
  // bug where chunk-cache state, `firstFetchDone`, or `bindsFlushed`
  // leaked from one call to the next would surface as wrong rows on
  // the second iteration.

  testWidgets('statement reuse after reader close fetches fresh rows',
      (tester) async {
    final db = await newDb('stream_stmt_reuse.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val INTEGER)');
    for (int i = 1; i <= 100; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [i, i]);
    }

    final stmt =
        await db.prepareQuery('SELECT val FROM t WHERE id BETWEEN ? AND ?');

    // First reader: rows 1..5.
    {
      final reader = await stmt.executeReader(params: [1, 5]);
      final got = <int>[];
      while (await reader.readRow()) {
        got.add(reader.getColumnInt(0));
      }
      expect(got, [1, 2, 3, 4, 5]);
    }

    // Second reader on the same stmt object, different params: rows
    // 91..95. If the prior chunk cache or bindsFlushed flag leaked,
    // we'd see 1..5 again or get a stale partial chunk.
    {
      final reader = await stmt.executeReader(params: [91, 95]);
      final got = <int>[];
      while (await reader.readRow()) {
        got.add(reader.getColumnInt(0));
      }
      expect(got, [91, 92, 93, 94, 95]);
    }

    await stmt.close();
    await db.closeDb();
    await db.dropDb();
  });

  // ── Partial-final-chunk boundary (T3) ──────────────────────────────────
  //
  // Chunk size is 50; a 73-row scan exercises the partial final
  // chunk (50 + 23). Off-by-one here would either drop the final
  // chunk's leftovers or hang requesting another chunk after DONE.

  testWidgets('result set whose size is not a multiple of chunk size',
      (tester) async {
    final db = await newDb('stream_partial_chunk.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY)');
    for (int i = 1; i <= 73; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?)', params: [i]);
    }

    final reader = await (await db.prepareQuery(
            'SELECT id FROM t ORDER BY id'))
        .executeReader();
    int seen = 0;
    while (await reader.readRow()) {
      seen++;
      expect(reader.getColumnInt(0), seen);
    }
    expect(seen, 73);

    await db.closeDb();
    await db.dropDb();
  });

  // ── Statement.close() while reader is mid-stream (T4) ──────────────────
  //
  // The previous "abandoned reader" test triggers cleanup via
  // `Reader.close()`. This one closes the Statement directly while
  // the reader is still active — the `Statement.close()` cascade
  // must finalize the worker handle and release the SHARED reader
  // fence so subsequent statements can prepare without
  // `UNKNOWN_HANDLE` or fence-acquire timeouts.

  testWidgets(
      'statement.close() while reader mid-stream releases the worker handle',
      (tester) async {
    final db = await newDb('stream_stmt_close_midstream.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY)');
    for (int i = 1; i <= 200; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?)', params: [i]);
    }

    {
      final stmt =
          await db.prepareQuery('SELECT id FROM t ORDER BY id');
      final reader = await stmt.executeReader();
      // Read 3 rows out of 200 then close the STATEMENT (not the
      // reader directly). Statement.close() cascades to reader.close
      // which cascades to finalizeStmt.
      for (int i = 0; i < 3; i++) {
        expect(await reader.readRow(), isTrue);
      }
      await stmt.close();
      // Reader becomes unusable after the cascade.
      expect(reader.isClosed, isTrue);
    }

    // Fresh stmt + full scan: if the prior worker handle had leaked,
    // this would either fail outright or stall on fence acquire.
    final reader = await (await db.prepareQuery(
            'SELECT id FROM t ORDER BY id'))
        .executeReader();
    int seen = 0;
    while (await reader.readRow()) {
      seen++;
    }
    expect(seen, 200);

    await db.closeDb();
    await db.dropDb();
  });

  // ── INSERT … RETURNING — counter capture for column-count > 0 (T5) ─────
  //
  // `INSERT … RETURNING id` produces a row payload AND mutates the
  // table. The unified counter-capture must run on every DONE, not
  // just write-shape stmts (`columnCount == 0`), so
  // `Statement.getAffectedRows()` / `getLastInsertedId()` reflect the
  // insert even though the SQL also returned data.

  testWidgets('INSERT … RETURNING captures counters and returns rows',
      (tester) async {
    // INSERT … RETURNING is a write that produces rows. `executeReader`
    // routes to a pool reader connection by default — but pool readers
    // are read-only (PRAGMA query_only=ON), so the INSERT would fail
    // with SQLITE_READONLY. Run with `readerPoolSize: 0` so the
    // single-connection fallback path uses the writer for everything.
    // This matches how the native unit-test "counter cache survives
    // reader auto-close on DONE" exercises INSERT … RETURNING.
    final db = await newDb('stream_returning.db', readerPoolSize: 0);
    await runSql(db,
        'CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, val TEXT)');

    // Pre-insert a row so the next INSERT's auto-allocated id is 2,
    // making the assertion stronger than "any positive integer".
    await runSql(db, "INSERT INTO t (val) VALUES ('seed')");

    final stmt = await db.prepareQuery(
        "INSERT INTO t (val) VALUES (?) RETURNING id");
    final reader = await stmt.executeReader(params: ['next']);
    expect(await reader.readRow(), isTrue);
    final returnedId = reader.getColumnInt(0);
    expect(returnedId, 2);
    expect(await reader.readRow(), isFalse,
        reason: 'INSERT … RETURNING produces exactly one row per insert');
    // Counters captured on DONE — must be available without an extra
    // round-trip and must reflect the insert.
    expect(stmt.getAffectedRows(), 1,
        reason: 'INSERT … RETURNING must report 1 affected row');
    expect(stmt.getLastInsertedId(), 2,
        reason: 'lastInsertedId must match the RETURNING-emitted id');
    await stmt.close();

    await db.closeDb();
    await db.dropDb();
  });

  // ── Raw List<int> blob bind (T6) ───────────────────────────────────────
  //
  // The web `_jsifyBindValue` wraps a raw `List<int>` in a
  // `Uint8List` because the worker's `bindParams` recognises blobs by
  // `instanceof Uint8Array` — a plain JS Array would fall through to
  // `bindText`'s string coercion, silently corrupting the bytes.

  testWidgets('raw List<int> blob bind preserves bytes',
      (tester) async {
    final db = await newDb('stream_raw_blob.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, b BLOB)');

    // Note the literal `<int>[...]` — NOT Uint8List.fromList. The
    // platform layer must convert this to Uint8List before crossing
    // the postMessage boundary. The previous test always used
    // Uint8List.fromList directly.
    final raw = <int>[0, 1, 2, 0xff, 0x80];
    final stmt = await db.prepareQuery('INSERT INTO t VALUES (?, ?)');
    await stmt.executeSql(params: [1, raw]);
    await stmt.close();

    final got = await (await db.prepareQuery('SELECT b FROM t WHERE id = 1'))
        .executeScalar();
    expect(got, isA<Uint8List>(),
        reason: 'blob column must come back typed');
    expect(got as Uint8List, equals(Uint8List.fromList(raw)));

    await db.closeDb();
    await db.dropDb();
  });

  // ── databaseExists no longer leaks (regression for I-fix) ──────────────
  //
  // Previously `databaseExists` created a pool and never closed it —
  // a stale entry stayed in the static `_pools` map. This test calls
  // `databaseExists` repeatedly then opens the db; the open must
  // succeed and queries must run normally. A pool leak would either
  // surface here or accumulate workers across the suite.

  testWidgets('databaseExists is repeatable without leaking the worker',
      (tester) async {
    const name = 'stream_exists_no_leak.db';
    {
      final db = await newDb(name);
      await db.closeDb();
      await db.dropDb();
    }

    final db =
        await DbasSqlite.getInstance(dbName: name, workerPoolSize: 4);
    // Multiple existence checks — each should clean up its probe
    // pool so subsequent operations are not blocked by a stale
    // worker still holding the writer connection.
    for (int i = 0; i < 3; i++) {
      await db.databaseExists();
    }
    await db.openDb(readerPoolSize: 2);
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY)');
    await runSql(db, 'INSERT INTO t VALUES (1)');
    expect(
        await (await db.prepareQuery('SELECT id FROM t')).executeScalar(),
        1);

    await db.closeDb();
    await db.dropDb();
  });
}
