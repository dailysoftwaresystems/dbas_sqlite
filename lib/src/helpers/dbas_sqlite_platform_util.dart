import 'package:dbas_sqlite/src/helpers/test_mode/dbas_sqlite_test_mode.dart';

class DbasSqlitePlatformUtil {
  static bool isTest() => isFlutterTestEnv();
}
