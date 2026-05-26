// Integration test for the in-flight-reader-during-teardown fix.
//
// When a destructive op (or an error-path teardown) closes the live pool
// and a fresh pool replaces it for the same dbName, a reader that already
// captured its statement state must route its remaining steps to the
// OWNING (now-closed) pool — surfacing a clean "pool closed" error —
// rather than to the new `_pool`, which doesn't know the old cursor and
// would otherwise throw the misleading `UNKNOWN_CURSOR`.
//
// The real teardown drains for 5s and clears `_stmts`, so this exact
// interleaving can't be produced through the public API. The platform's
// `debugSwapLivePoolPreservingStatements()` hook reproduces it
// deterministically: it closes the live pool and boots a new one WITHOUT
// clearing `_stmts`, which is precisely the state an in-flight reader sees.
//
// Run on web:
//   cd example
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/web_pool_teardown_test.dart \
//     -d web-server --browser-name=chrome --headless

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// RowData is pure Dart; the native-web platform + interface are web-safe.
// dbas_sqlite_db.dart is deliberately NOT imported — it pulls in dart:ffi
// (the public API reaches the web stub via a conditional import). The one
// constant we need (SQLITE_ROW) is defined locally instead.
// ignore: implementation_imports
import 'package:dbas_sqlite/src/dbas_sqlite_row_cache.dart' show RowData;
// ignore: implementation_imports
import 'package:dbas_sqlite/src/native/dbas_sqlite_native_interface.dart';
// ignore: implementation_imports
import 'package:dbas_sqlite/src/native/dbas_sqlite_native_web.dart';

const int sqliteRow = 100; // SQLITE_ROW

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'in-flight reader routes to owning pool after swap (closed, not UNKNOWN_CURSOR)',
    (tester) async {
      DbasSqliteNativeInterface.workerPoolSize = 4;
      final web =
          DbasSqliteNativeInterface.getInstance(dbName: 'stale_cursor.db')
              as DbasSqliteNativeWeb;
      await web.initialize();
      final dbPtr = await web.openDb('stale_cursor.db');

      // Seed enough rows that the reader needs a second fetch after the
      // first single-row step — so the post-swap step actually hits the
      // pool rather than draining a buffered chunk.
      await web.executeSql(
          dbPtr, 'CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
      for (var i = 0; i < 20; i++) {
        await web.executeSql(dbPtr, "INSERT INTO t (id, v) VALUES ($i, 'v$i')");
      }

      final prep =
          await web.prepareQuery(dbPtr, 'SELECT id, v FROM t ORDER BY id');
      expect(prep.handle, isNot(0));

      final cache = RowData();
      // First step succeeds against the original pool.
      var rc = await web.readRowAndCache(dbPtr, prep.handle, cache);
      expect(rc, sqliteRow);

      // Reproduce the in-flight teardown race: swap the live pool while
      // the statement's _WebStmtState (referencing the now-CLOSED original
      // pool) survives.
      await web.debugSwapLivePoolPreservingStatements();

      // The next step routes through the statement's owning (closed) pool.
      rc = await web.readRowAndCache(dbPtr, prep.handle, cache);
      expect(rc, isNot(sqliteRow),
          reason: 'a step on a closed owning pool must fail');

      final err = (web.getLastDbError(dbPtr) ?? '').toLowerCase();
      // DISCRIMINATING: with the fix, routing to the owning (closed) pool
      // yields a "closed" error. Pre-fix, the step routed to the NEW pool
      // and surfaced the misleading "unknown ... cursor".
      expect(err, contains('closed'),
          reason: 'expected a pool-closed error, got: "$err"');
      expect(err, isNot(contains('unknown')),
          reason: 'stale cursor must NOT route to the new pool: "$err"');

      // Cleanup. finalizeStmt is tolerant of the closed owning pool.
      await web.finalizeStmt(dbPtr, prep.handle);
      await web.closeDb(dbPtr);
      await web.dropDb('stale_cursor.db');
    },
  );
}
