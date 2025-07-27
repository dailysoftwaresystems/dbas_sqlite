import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class DbasSqliteDb extends Struct {
  external Pointer<Void> db;
  external Pointer<Void> stmt;
  external Pointer<Utf8> lastError;
  external Pointer<Utf8> fileName;
}