import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('openDb', () async {
    final plugin = DbasSqlite();
    await plugin.openDb('test.db');
    expect(plugin.isOpened, isTrue);
  });
}
