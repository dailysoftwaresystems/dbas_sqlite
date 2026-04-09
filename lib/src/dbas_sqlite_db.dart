import 'dart:ffi';
import 'package:ffi/ffi.dart';

class DbasSqliteDb {
  final String name;
  final int ptr;
  DbasSqliteDb(this.name, this.ptr);
}

final class DbasSqliteDbStruct extends Struct {
  external Pointer<Void> db;
  external Pointer<Void> stmt;
  external Pointer<Utf8> lastError;
  external Pointer<Utf8> fileName;
}

final class DbasSqlitePoolStruct extends Struct {
  external Pointer<DbasSqliteDbStruct> writer;
  external Pointer<Pointer<DbasSqliteDbStruct>> readers;
  external Pointer<Bool> readerBusy;
  @Int32()
  external int readerCount;
  external Pointer<Utf8> fileName;
}
