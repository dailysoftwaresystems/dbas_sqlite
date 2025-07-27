
import 'dbas_sqlite_native_web.dart';
import 'dbas_sqlite_platform_interface.dart';

class DbasSqliteWeb extends DbasSqlitePlatform {
  static DbasSqliteNativeWeb? _sqlite;

  @override
  Future<void> initialize() async {
    if (DbasSqliteWeb._sqlite == null) {
      DbasSqliteWeb._sqlite = DbasSqliteNativeWeb();
      await DbasSqliteWeb._sqlite?.initialize();
    }
  }

  @override
  Future<int> executeSql(String sql) {
    return Future.value(0);
  }

  @override
  Future<int> prepareQuery(String sql) {
    return Future.value(0);
  }
}