// Integration tests for the auto-routing of in-transaction reads
// (executeReader / executeScalar) introduced in 2.5.0. These run on a
// real device — native and web — to validate that the read-routing
// matches the contract end-to-end:
//
//   - Outside a tx, or in a tx before any executeSql, reads use the
//     pool reader (last-committed snapshot). Parallel fan-out works.
//   - Once any executeSql runs in the active tx, subsequent reads
//     route to the writer connection so they observe the in-flight
//     uncommitted writes (read-your-writes).
//
// Run on native (e.g. macOS / Windows / iOS / Android):
//   cd example
//   flutter test integration_test/autoroute_parallel_test.dart
//
// Run on web (Chrome dev server):
//   cd example
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/autoroute_parallel_test.dart \
//     -d web-server --browser-name=chrome

import 'package:dbas_sqlite/dbas_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Pool size matches the parallel fan-out in the heavy tests below so
  // every reader gets a connection without queuing on the blocking
  // pool acquire. Worker pool auto-bumps to readerCount + 2, leaving
  // headroom for the prepare/bind/step round-trips that follow each
  // acquire.
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

  // ── Read-your-writes inside a transaction ─────────────────────────────

  testWidgets('in-tx write then executeReader sees the written row',
      (tester) async {
    final db = await newDb('autoroute_int_writethenread.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT)');

    await db.beginTransaction();
    await runSql(db, "INSERT INTO t VALUES (1, 'inflight')");

    final reader = await (await db
            .prepareQuery('SELECT val FROM t WHERE id = 1'))
        .executeReader();
    expect(await reader.readRow(), isTrue);
    expect(reader.getColumnText(0), 'inflight');
    await reader.close();

    await db.rollback();
    await db.closeDb();
    await db.dropDb();
  });

  testWidgets('in-tx write then executeScalar returns the written value',
      (tester) async {
    final db = await newDb('autoroute_int_writethenscalar.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT)');

    await db.beginTransaction();
    await runSql(db, "INSERT INTO t VALUES (7, 'inflight-scalar')");

    final v = await (await db.prepareQuery('SELECT val FROM t WHERE id = 7'))
        .executeScalar();
    expect(v, 'inflight-scalar');

    await db.rollback();
    await db.closeDb();
    await db.dropDb();
  });

  // ── Parallel in-tx reads (the original bug-driver scenario) ──────────

  testWidgets(
      '10 parallel pre-write in-tx executeScalar reads all complete '
      '(Future.wait)', (tester) async {
    final db = await newDb('autoroute_int_par_scalar.db', readerPoolSize: 10);
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val INTEGER)');
    for (int i = 1; i <= 10; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [i, i * 10]);
    }

    await db.beginTransaction();
    final results = await Future.wait(
      List.generate(10, (i) {
        final id = i + 1;
        return (() async => (await db
                .prepareQuery('SELECT val FROM t WHERE id = ?'))
            .executeScalar(params: [id]))();
      }),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () =>
          fail('10 parallel pre-write in-tx scalar reads timed out'),
    );
    for (int i = 0; i < 10; i++) {
      expect(results[i], (i + 1) * 10);
    }

    await db.commit();
    await db.closeDb();
    await db.dropDb();
  });

  testWidgets(
      '10 parallel pre-write in-tx executeReader runs all complete',
      (tester) async {
    final db = await newDb('autoroute_int_par_reader.db', readerPoolSize: 10);
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT)');
    for (int i = 1; i <= 10; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?, ?)',
          params: [i, 'row-$i']);
    }

    Future<String?> readOne(int id) async {
      final stmt =
          await db.prepareQuery('SELECT val FROM t WHERE id = ?');
      try {
        final reader = await stmt.executeReader(params: [id]);
        try {
          if (!await reader.readRow()) return null;
          return reader.getColumnText(0);
        } finally {
          await reader.close();
        }
      } finally {
        await stmt.close();
      }
    }

    await db.beginTransaction();
    final results = await Future.wait(
      List.generate(10, (i) => readOne(i + 1)),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () =>
          fail('10 parallel pre-write in-tx executeReader runs timed out'),
    );
    for (int i = 0; i < 10; i++) {
      expect(results[i], 'row-${i + 1}');
    }

    await db.commit();
    await db.closeDb();
    await db.dropDb();
  });

  testWidgets(
      '10 parallel post-write in-tx reads all complete (writer-serialised)',
      (tester) async {
    // After a write, every in-tx read routes to the writer connection
    // for read-your-writes. They serialise on the writer but must all
    // succeed and observe the in-flight UPDATE.
    final db = await newDb('autoroute_int_par_postwrite.db',
        readerPoolSize: 10);
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val INTEGER)');
    for (int i = 1; i <= 10; i++) {
      await runSql(db, 'INSERT INTO t VALUES (?, ?)', params: [i, i]);
    }

    await db.beginTransaction();
    await runSql(db, 'UPDATE t SET val = val * 100');

    final results = await Future.wait(
      List.generate(10, (i) {
        final id = i + 1;
        return (() async => (await db
                .prepareQuery('SELECT val FROM t WHERE id = ?'))
            .executeScalar(params: [id]))();
      }),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => fail(
          '10 parallel post-write in-tx reads timed out (writer path)'),
    );
    for (int i = 0; i < 10; i++) {
      expect(results[i], (i + 1) * 100);
    }

    await db.commit();
    await db.closeDb();
    await db.dropDb();
  });

  // ── Alternation: write/read repeatedly inside one tx ─────────────────

  testWidgets('multi-statement write/read alternation inside one tx',
      (tester) async {
    final db = await newDb('autoroute_int_alternation.db');
    await runSql(db, 'CREATE TABLE t (id INTEGER PRIMARY KEY, val INTEGER)');

    await db.beginTransaction();

    await runSql(db, 'INSERT INTO t VALUES (1, 100)');
    var sum = await (await db.prepareQuery('SELECT SUM(val) FROM t'))
        .executeScalar();
    expect(sum, 100);

    await runSql(db, 'INSERT INTO t VALUES (2, 200)');
    sum = await (await db.prepareQuery('SELECT SUM(val) FROM t'))
        .executeScalar();
    expect(sum, 300);

    await runSql(db, 'UPDATE t SET val = val + 50 WHERE id = 1');
    sum = await (await db.prepareQuery('SELECT SUM(val) FROM t'))
        .executeScalar();
    expect(sum, 350);

    await db.commit();
    await db.closeDb();
    await db.dropDb();
  });

  // ── In-tx write then multiple parallel multi-row readers ─────────────
  //
  // The existing post-write test above uses `executeScalar` for the
  // parallel readers. This one uses `executeReader` so each reader
  // streams several rows (exercising the chunked-read path on web,
  // the per-step FFI path on native), and every reader must observe
  // the in-flight UPDATE — read-your-writes through the writer route
  // must hold under fan-out.

  testWidgets(
      'in-tx write then 8 parallel executeReader runs all see the write',
      (tester) async {
    final db = await newDb('autoroute_int_par_postwrite_reader.db',
        readerPoolSize: 10);
    await runSql(db,
        'CREATE TABLE t (group_id INTEGER, id INTEGER PRIMARY KEY, val INTEGER)');
    // 8 groups × 5 rows = 40 rows. Each reader scans one group's rows.
    int rowId = 1;
    for (int g = 1; g <= 8; g++) {
      for (int i = 1; i <= 5; i++) {
        await runSql(db, 'INSERT INTO t VALUES (?, ?, ?)',
            params: [g, rowId++, i]);
      }
    }

    await db.beginTransaction();
    // Bump every val by 1000 in-flight; the readers must see val+1000.
    await runSql(db, 'UPDATE t SET val = val + 1000');

    final results = await Future.wait(
      List.generate(8, (g) async {
        final reader = await (await db.prepareQuery(
                'SELECT val FROM t WHERE group_id = ? ORDER BY id'))
            .executeReader(params: [g + 1]);
        try {
          final got = <int>[];
          while (await reader.readRow()) {
            got.add(reader.getColumnInt(0));
          }
          return got;
        } finally {
          if (!reader.isClosed) await reader.close();
        }
      }),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => fail(
          '8 parallel post-write in-tx executeReader runs timed out '
          '(writer path)'),
    );

    for (int g = 0; g < 8; g++) {
      // Each group's rows were [1, 2, 3, 4, 5]; in-flight UPDATE
      // bumped them by 1000.
      expect(results[g], [1001, 1002, 1003, 1004, 1005],
          reason: 'group ${g + 1} did not observe the in-flight UPDATE');
    }

    // Roll back: post-rollback reads must see the original values
    // (reset for the in-tx write flag is also exercised here).
    await db.rollback();
    final after =
        await (await db.prepareQuery('SELECT val FROM t WHERE id = 1'))
            .executeScalar();
    expect(after, 1, reason: 'rollback must restore the original value');

    await db.closeDb();
    await db.dropDb();
  });

  // ── executeScalar smoke (return shapes that the unit tests cover, but
  // re-run on the real device to confirm cross-platform parity).

  testWidgets('executeScalar typed returns + null cases', (tester) async {
    final db = await newDb('autoroute_int_scalar_smoke.db');
    await runSql(db, 'CREATE TABLE t (i INTEGER, d REAL, s TEXT)');
    await runSql(db, 'INSERT INTO t VALUES (?, ?, ?)',
        params: [42, 3.14, 'hello']);

    expect(await (await db.prepareQuery('SELECT i FROM t')).executeScalar(),
        42);
    expect(await (await db.prepareQuery('SELECT d FROM t')).executeScalar(),
        closeTo(3.14, 1e-9));
    expect(await (await db.prepareQuery('SELECT s FROM t')).executeScalar(),
        'hello');

    expect(
        await (await db.prepareQuery('SELECT i FROM t WHERE i < 0'))
            .executeScalar(),
        isNull,
        reason: 'no rows → null');

    await runSql(db, 'UPDATE t SET s = NULL');
    expect(await (await db.prepareQuery('SELECT s FROM t')).executeScalar(),
        isNull,
        reason: 'first column NULL → null');

    await db.closeDb();
    await db.dropDb();
  });
}
