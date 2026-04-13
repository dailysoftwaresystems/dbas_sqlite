# DBAS.SQLite.Flutter

Flutter plugin that provides access to SQLite databases for Android, iOS, macOS, Linux, Windows and Web platforms.

## Features

### Cross-Platform Support
- **Android** - Native library integration
- **iOS** - xcframework with optimized performance  
- **macOS** - xcframework for both development and production
- **Linux** - Native shared libraries
- **Windows** - DLL integration
- **Web** - WASM SQLite via dedicated Web Worker with OPFS persistence

### Connection Pool (WAL Mode)
- `openDb()` automatically creates a C-level connection pool with 1 writer + 4 readers (configurable)
- WAL mode enables concurrent reads and writes
- Pool is fully transparent -- no API changes needed
- Reads automatically use pool readers; writes use the dedicated writer
- Falls back to single connection if pool creation fails or `readerPoolSize = 0`
- Native pool has mutex-protected reader acquire/release for thread safety

### Thread Safety & Parallel Readers
- **Writer lock**: serializes all write operations (`executeSql`, transactions) on both web and native
- **Independent readers**: each `executeReader` call returns a `DbasSqliteReader` with its own pool connection -- multiple readers can be active simultaneously
- Pool readers are acquired non-blocking; if all are busy, the reader falls back to the writer connection
- Transactions hold the writer lock for their full duration
- Reads within a transaction use the writer connection to see uncommitted data
- Readers must be closed explicitly via `reader.close()` (or auto-closed when `readRow()` returns `false`) before the connection can be reused
- `closeDb()` automatically closes all active readers, then releases all locks and unblocks any pending operations -- no risk of use-after-free on lingering readers

### Background FFI Worker (Native)
- All heavy FFI operations (`executeSql`, `prepareQuery`, `readRow`, `openDb`, `closeDb`) run on a dedicated background isolate
- Column data is pre-fetched into a Dart-side cache after each `readRow` -- `getColumn*` calls are synchronous reads from Dart memory, not FFI round-trips
- Bind operations remain synchronous on the main isolate for performance

### True Streaming I/O (Web)
- **`attachStreamDb(stream)`**: Streams a database to OPFS chunk by chunk via `attachStreamBegin`/`attachStreamChunk`/`attachStreamEnd` with ACK-based backpressure. The complete file is never buffered in Dart memory -- critical for large databases (500 MB+)
- **`getContent()`**: Streams the database from OPFS chunk by chunk. Supports both Transferable Streams (Chrome/Firefox) and chunked postMessage fallback (Safari)
- **`streamCopyDb(destDbName)`**: Copies between OPFS files chunk by chunk

### Database Operations
- **Lifecycle**
  - `getInstance(dbName:)` - Get singleton instance for a database
  - `openDb({readerPoolSize})` - Open database with connection pool
  - `closeDb()` - Close database connection (automatically closes all active readers)
  - `isOpened()` - Check connection status
  - `getAppDatabasePath()` - Get platform-specific database path
  - `databaseExists()` - Check if the database file exists
  - `dropDb()` - Delete the database file (including WAL and SHM)

- **Database Content**
  - `attachDb(bytes)` - Attach a database from raw bytes
  - `attachStreamDb(stream)` - Attach a database from a byte stream
  - `streamCopyDb(destDbName)` - Stream-copy database to a new name
  - `getContent()` - Get the raw bytes of the database file

- **SQL Execution**
  - `executeSql(sql, {params, nameParams})` - Execute DDL/DML statements with optional positional or named parameters
  - `executeReader(sql, {params, nameParams})` - Prepare a SELECT query, returns an independent `DbasSqliteReader`

- **Transactions**
  - `beginTransaction()` - Begin a new transaction (idempotent)
  - `commit()` - Commit the current transaction (idempotent)
  - `rollback()` - Rollback the current transaction (idempotent)
  - `transaction(action)` - Execute an action within a transaction with automatic commit/rollback
  - `isInTransaction` - Check if a transaction is currently active

### Data Retrieval (`DbasSqliteReader`)
- `readRow()` - Advance to next row (`true` if available, `false` and auto-closes when done)
- `close()` - Manually close the reader and release its connection
- **Column Access** (with nullable variants)
  - `getColumnText(index)` / `getColumnNullableText(index)` - Get string value
  - `getColumnInt(index)` / `getColumnNullableInt(index)` - Get integer value
  - `getColumnBool(index)` / `getColumnNullableBool(index)` - Get boolean value
  - `getColumnDouble(index)` / `getColumnNullableDouble(index)` - Get double value
  - `getColumnDecimal(index)` / `getColumnNullableDecimal(index)` - Get decimal value
  - `getColumnDateTime(index)` / `getColumnNullableDateTime(index)` - Get DateTime value
  - `getColumnTime(index)` / `getColumnNullableTime(index)` - Get Duration value
  - `getColumnEnum<T>(index, values)` / `getColumnNullableEnum<T>(index, values)` - Get enum value
  - `getColumnBlob(index)` / `getColumnNullableBlob(index)` - Get binary data
  - `getColumnValue(index)` - Get typed value based on SQLite column type
  - `isColumnNull(index)` - Check if column is NULL
  - `getColumnType(index)` - Get column data type
  - `getColumnName(index)` - Get column name
  - `getColumnCount()` - Get number of columns

### Query Information
- `getLastInsertedId()` - Get last inserted row ID

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dbas_sqlite_flutter: git@github.com:dailysoftwaresystems/DBAS.SQLite.Flutter.git
```

## Setup

### Mobile & Desktop
No additional setup required. Native libraries are automatically bundled.

### Web Setup
The WASM module and Web Worker are bundled as Flutter assets and loaded automatically by the plugin. No manual file copying or `<script>` tags needed.

The worker runs inside a dedicated Web Worker with OPFS persistence. Requires a modern browser with OPFS support (Chrome 86+, Firefox 111+, Safari 15.2+) served over HTTPS or localhost.

## Usage

### Basic Example

```dart
import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';

// Get database instance
final db = await DbasSqlite.getInstance(dbName: 'myapp.db');

// Open database (creates pool with WAL mode)
await db.openDb();

// Create table
await db.executeSql('''
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    age INTEGER
  )
''');

// Insert with positional parameters
await db.executeSql(
  'INSERT INTO users (name, email, age) VALUES (?, ?, ?)',
  params: ['John Doe', 'john@example.com', 30],
);

// Query data
final reader = await db.executeReader('SELECT * FROM users WHERE age > ?', params: [25]);
while (await reader.readRow()) {
  final name = reader.getColumnText(0);
  final email = reader.getColumnNullableText(1);
  final age = reader.getColumnInt(2);
  print('$name ($email) - age: $age');
}
await reader.close();

await db.closeDb();
```

### Named Parameters

```dart
await db.executeSql(
  'INSERT INTO users (name, email, age) VALUES (:name, :email, :age)',
  nameParams: {'name': 'Jane Smith', 'email': 'jane@example.com', 'age': 28},
);

// By default, extra named parameters not present in the SQL are silently
// ignored (C#/SQLite behavior). To throw instead:
db.throwOnMissingNamedParams = true;
```

### Rich Types

```dart
import 'package:decimal/decimal.dart';

// Supports Decimal, bool, DateTime, Duration, Enum and Blob
await db.executeSql(
  'INSERT INTO products (name, price, active) VALUES (?, ?, ?)',
  params: ['Widget', Decimal.parse('19.99'), true],
);

final reader = await db.executeReader('SELECT name, price, active FROM products');
while (await reader.readRow()) {
  final name = reader.getColumnText(0);
  final price = reader.getColumnDecimal(1);
  final active = reader.getColumnBool(2);
  print('$name - \$$price (active: $active)');
}
await reader.close();
```

### Transactions

```dart
// Automatic commit/rollback
await db.transaction((db) async {
  await db.executeSql(
    'INSERT INTO users (name) VALUES (?)', params: ['Alice'],
  );
  await db.executeSql(
    'INSERT INTO users (name) VALUES (?)', params: ['Bob'],
  );
});

// Manual control
await db.beginTransaction();
try {
  await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Alice']);
  await db.commit();
} catch (_) {
  await db.rollback();
  rethrow;
}
```

### Connection Pool

```dart
// Default: 4 readers (WAL mode)
await db.openDb();

// Custom pool size
await db.openDb(readerPoolSize: 8);

// Single connection (no pool)
await db.openDb(readerPoolSize: 0);
```

### Stream Copy

```dart
// Copy database to a backup
await db.streamCopyDb('myapp_backup.db');
```

## Minimum Platform Versions

| Platform | Minimum Version |
|----------|----------------|
| Android  | API 35         |
| iOS      | 16.0           |
| macOS    | 13.0 (Ventura) |
| Linux    | x86_64         |
| Windows  | x86_64         |
| Web      | Modern browsers with OPFS support |

## Platform Notes

- **iOS/macOS**: Uses xcframework for optimal performance
- **Android**: Native library automatically included (NDK r29)
- **Windows/Linux**: Dynamic libraries bundled with app
- **Web**: WASM module runs in a dedicated Web Worker with OPFS persistence. All heavy operations are serialized through the worker — column data is cached in Dart memory after each `readRow` for synchronous access

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.
