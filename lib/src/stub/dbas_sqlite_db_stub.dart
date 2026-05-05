/// Web-side stub for `lib/src/dbas_sqlite_db.dart`. Web doesn't use
/// the FFI structs but still needs the [DbasSqliteDb] handle class
/// and the SQLite return-code constants used by `DbasSqliteStatement`
/// and `DbasSqliteReader` (which compile on web).
class DbasSqliteDb {
  final String name;
  final int ptr;
  DbasSqliteDb(this.name, this.ptr);
}

const int sqliteOk = 0;
const int sqliteBusy = 5;
const int sqliteRange = 25;
const int sqliteMisuse = 21;
const int sqliteRow = 100;
const int sqliteDone = 101;
const int sqliteInvalidStmtHandle = 0;
