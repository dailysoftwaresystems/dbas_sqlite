// Conditional export: web → stub, every other Flutter platform → FFI.
//
// `dart.library.ffi` is present on every platform Flutter targets that
// is not web, so the FFI variant is the canonical native impl. The
// stub stays for any non-Flutter target that consumes this package
// (e.g. command-line Dart that doesn't need FFI).
export 'stub/dbas_sqlite_native_app_stub.dart'
    if (dart.library.js_interop) 'stub/dbas_sqlite_native_app_stub.dart'
    if (dart.library.ffi) 'dbas_sqlite_native_app_ffi.dart';
