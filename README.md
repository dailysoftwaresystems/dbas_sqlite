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
- `openDb()` automatically creates a connection pool with 1 writer + 4 readers (configurable)
- WAL mode enables concurrent reads and writes
- Pool is fully transparent -- no API changes needed
- Reads automatically use pool readers; writes use the dedicated writer
- Falls back to single connection if pool creation fails or `readerPoolSize = 0`

### Thread Safety
- **Writer mutex**: serializes all write operations (`executeSql`, transactions)
- **Reader mutex**: serializes read sessions (`executeReader` through `closeReader`)
- Writer and reader locks are independent -- concurrent reads and writes via WAL mode
- Transactions hold the writer lock for their full duration
- Reads within a transaction use the writer connection to see uncommitted data
- Pending reader sessions are automatically closed when a new `executeSql` or `executeReader` is called -- no need to manually close readers before starting a new operation
- `closeDb()` safely releases all locks and unblocks any pending operations

### Database Operations
- **Lifecycle**
  - `getInstance(dbName:)` - Get singleton instance for a database
  - `openDb({readerPoolSize})` - Open database with connection pool
  - `closeDb()` - Close database connection  
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
  - `executeReader(sql, {params, nameParams})` - Prepare a SELECT query with optional positional or named parameters
  - `readRow()` - Read query results row by row
  - `closeReader()` - Manually close the current prepared statement

- **Transactions**
  - `beginTransaction()` - Begin a new transaction (idempotent)
  - `commit()` - Commit the current transaction (idempotent)
  - `rollback()` - Rollback the current transaction (idempotent)
  - `transaction(action)` - Execute an action within a transaction with automatic commit/rollback
  - `isInTransaction` - Check if a transaction is currently active

### Data Retrieval
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
  dbas_sqlite_flutter: ^2.0.9
```

## Setup

### Mobile & Desktop
No additional setup required. Native libraries are automatically bundled.

### Web Setup
For web support, copy the following files to your project's `web/libs/` directory:

1. [`dbas_sqlite.js`](https://github.com/dailysoftwaresystems/DBAS.SQLite.Flutter/blob/main/web/libs/dbas_sqlite.js) - Auto-generated WASM SQLite module
2. [`dbas_sqlite_worker.js`](https://github.com/dailysoftwaresystems/DBAS.SQLite.Flutter/blob/main/web/libs/dbas_sqlite_worker.js) - Web Worker entry point

```bash
mkdir -p web/libs
# Copy both files to web/libs/
```

The WASM module runs inside a dedicated Web Worker for OPFS support. No `<script>` tags needed in `index.html` -- the plugin loads the worker automatically.

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
await db.executeReader('SELECT * FROM users WHERE age > ?', params: [25]);
while (await db.readRow()) {
  final name = db.getColumnText(0);
  final email = db.getColumnNullableText(1);
  final age = db.getColumnInt(2);
  print('$name ($email) - age: $age');
}

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

await db.executeReader('SELECT name, price, active FROM products');
while (await db.readRow()) {
  final name = db.getColumnText(0);
  final price = db.getColumnDecimal(1);
  final active = db.getColumnBool(2);
  print('$name - \$$price (active: $active)');
}
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
- **Web**: WASM module runs in a dedicated Web Worker with OPFS persistence. Requires `dbas_sqlite.js` and `dbas_sqlite_worker.js` in `web/libs/`

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.
