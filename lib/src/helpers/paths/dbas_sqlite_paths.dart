// Conditional helper resolving the on-disk database directory. The
// io variant uses `path_provider` + `Directory`; the web variant
// returns the OPFS virtual root. Conditional export keeps `dart:io`
// and `path_provider` out of the web build graph so pub.dev awards
// full Web + WASM compatibility.
export 'dbas_sqlite_paths_web.dart'
    if (dart.library.io) 'dbas_sqlite_paths_io.dart';
