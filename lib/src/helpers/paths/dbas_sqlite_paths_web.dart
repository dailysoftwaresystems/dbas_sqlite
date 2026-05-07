const String _appDbDir = 'dbas_data';

/// Web stub — returns the OPFS virtual root used by the JS pool. The
/// `isTest` flag is ignored on web because Flutter's test runner only
/// sets `FLUTTER_TEST` on native runtimes.
Future<String> resolveDatabaseDirectory({required bool isTest}) async =>
    '/$_appDbDir';
