// Conditional helper — returns whether the running process is the
// Flutter test runner (`FLUTTER_TEST` env var). The web build picks
// the dbas_sqlite_test_mode_web.dart stub (always `false`), keeping
// `dart:io` out of the public-surface reachability graph.
export 'dbas_sqlite_test_mode_web.dart'
    if (dart.library.io) 'dbas_sqlite_test_mode_io.dart';
