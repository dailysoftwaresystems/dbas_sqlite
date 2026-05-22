/// Stable identifiers for every throw site in DbasSqlite,
/// DbasSqliteStatement, and DbasSqliteReader. Each value is used by
/// exactly one throw so callers can branch on a specific failure
/// without parsing message text.
enum DbasSqliteErrorCode {
  // DbasSqlite — lifecycle
  closeDbBusyWithStmtFinalizeFailures,
  closeDbBusyLeakedHandle,
  prepareQueryDatabaseNotOpened,

  // DbasSqlite — busy timeout
  setBusyTimeoutDatabaseNotOpened,
  setBusyTimeoutWriterFailed,
  setBusyTimeoutReaderBusy,
  setBusyTimeoutReaderFailed,

  // DbasSqlite — WAL
  enableWalDatabaseNotOpened,
  enableWalFailed,

  // DbasSqlite — transactions
  beginTransactionDatabaseNotOpened,
  beginTransactionDatabaseClosedWaitingLock,
  beginTransactionFailed,
  commitFailed,
  rollbackFailed,
  transactionAlreadyActive,
  transactionRollbackAlsoFailed,

  // DbasSqlite — vacuum
  vacuumDatabaseNotOpened,
  vacuumInsideTransaction,
  vacuumDatabaseClosedWaitingLock,
  vacuumFailed,

  // DbasSqlite — locks / queues
  writerLockWaitCancelled,
  readerSlotWaitTimeout,
  readerSlotWaitCancelled,
  acquireReaderConnectionNoPool,

  // DbasSqliteStatement
  executeSqlPrepareFailed,
  executeSqlStepFailed,
  bindPositionalFailed,
  bindNamedParameterNotFound,
  bindNamedFailed,
  unsupportedPositionalBindType,
  unsupportedNamedBindType,
  readerAlreadyActive,
  executeReaderPoolAcquireTimeout,
  executeReaderPrepareFailed,
  statementClosed,
  statementDatabaseNotOpened,

  // DbasSqliteReader
  readRowFailed,
  invalidDecimalFormat,
  invalidTimeFormat,
  invalidTimeComponent,
  invalidEnumIndex,
}

/// Single exception type thrown by the public API of [DbasSqlite],
/// [DbasSqliteStatement], and [DbasSqliteReader].
///
/// [code] identifies the throw site uniquely. [sqliteCode] carries the
/// underlying SQLite result code (or step rc) when one is available;
/// it is `null` for purely Dart-side conditions (e.g. closed database,
/// invalid format, timeouts).
class DbasSqliteException implements Exception {
  final DbasSqliteErrorCode code;
  final int? sqliteCode;
  final String message;

  const DbasSqliteException(this.code, this.sqliteCode, this.message);

  @override
  String toString() {
    final base = 'DbasSqliteException(${code.name})';
    if (sqliteCode != null) {
      return '$base [sqliteCode=$sqliteCode]: $message';
    }
    return '$base: $message';
  }
}
