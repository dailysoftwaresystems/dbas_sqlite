import 'dart:ffi';
import 'package:ffi/ffi.dart';

class DbasSqliteDb {
  final Pointer<DbasSqliteDbStruct> ptr;
  DbasSqliteDb(this.ptr);
}

final class DbasSqliteDbStruct extends Struct {
  external Pointer<Void> db;
  external Pointer<Void> stmt;
  external Pointer<Utf8> lastError;
  external Pointer<Utf8> fileName;
}