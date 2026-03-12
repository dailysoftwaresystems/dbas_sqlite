# DBAS.SQLite.Flutter

Flutter plugin that provides access to SQLite databases for Android, iOS, macOS, Linux, Windows and Web platforms.

## 🚀 Features

### ✅ **Cross-Platform Support**
- **Android** - Native library integration
- **iOS** - xcframework with optimized performance  
- **macOS** - xcframework for both development and production
- **Linux** - Native shared libraries
- **Windows** - DLL integration
- **Web** - JavaScript SQLite implementation

### 🛠️ **Database Operations**
- **Database Management**
  - `getInstance(dbName:)` - Get singleton instance for a database
  - `openDb()` - Open database connection (path resolved internally)
  - `closeDb()` - Close database connection  
  - `isOpened()` - Check connection status
  - `getAppDatabasePath()` - Get platform-specific database path
  - `databaseExists()` - Check if the database file exists
  - `dropDb()` - Delete the database file
  - `attachDb(bytes)` - Attach a database from raw bytes
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

### 📊 **Data Retrieval**
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

### 🔍 **Query Information**
- `getLastDbError()` - Get last database error
- `getAffectedRows()` - Get number of affected rows
- `getLastInsertedId()` - Get last inserted row ID

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dbas_sqlite_flutter: ^1.6.2
```

## ⚙️ Setup

### 📱 **Mobile & Desktop**
No additional setup required. Native libraries are automatically bundled.

### 🌐 **Web Setup**
For web support, you need to download [`dbas_sqlite.js`](https://github.com/dailysoftwaresystems/DBAS.SQLite.Flutter/blob/main/native_libs/sqlite/web/dbas_sqlite.js) and place it in your `web/libs/` folder.

**Manual Setup:**
1. Create `web/libs/` directory in your project
2. Download `dbas_sqlite.js` from the repository
3. Place it in `web/libs/dbas_sqlite.js`

**Automated Setup (Recommended):**
Create a script to automatically copy the latest version:

```bash
# create_web_libs.sh
mkdir -p web/libs
curl -o web/libs/dbas_sqlite.js https://raw.githubusercontent.com/dailysoftwaresystems/DBAS.SQLite.Flutter/main/native_libs/sqlite/web/dbas_sqlite.js
```

## 🎯 Usage

### Basic Example

```dart
import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';

// Get database instance
final DbasSqlite db = await DbasSqlite.getInstance(dbName: 'myapp.db');

// Open database
await db.openDb();

// Create table
await db.executeSql('''
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    age INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
''');

// Insert data with positional parameters
await db.executeSql(
  'INSERT INTO users (name, email, age) VALUES (?, ?, ?)',
  params: ['John Doe', 'john@example.com', 30],
);

// Query data with parameters
await db.executeReader('SELECT * FROM users WHERE age > ?', params: [25]);

while (await db.readRow()) {
  final name = db.getColumnText(0);
  final email = db.getColumnNullableText(1);
  final age = db.getColumnInt(2);
  print('$name ($email) - age: $age');
}

// Close database
await db.closeDb();
```

### Named Parameters Example

```dart
// Insert with named parameters (auto-prefixed with ':' if needed)
await db.executeSql(
  'INSERT INTO users (name, email, age) VALUES (:name, :email, :age)',
  nameParams: {'name': 'Jane Smith', 'email': 'jane@example.com', 'age': 28},
);

// Query with named parameters
await db.executeReader(
  'SELECT * FROM users WHERE age > :minAge AND name != :exclude',
  nameParams: {':minAge': 25, ':exclude': 'admin'},
);

while (await db.readRow()) {
  print(db.getColumnText(0));
}
```

### Rich Types Example

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

### Transactions Example

```dart
// Recommended: use the transaction() helper for automatic commit/rollback
await db.transaction((db) async {
  await db.executeSql(
    'INSERT INTO users (name, email) VALUES (?, ?)',
    params: ['Alice', 'alice@example.com'],
  );
  await db.executeSql(
    'INSERT INTO users (name, email) VALUES (?, ?)',
    params: ['Bob', 'bob@example.com'],
  );
  // Automatically committed if no exception is thrown
  // Automatically rolled back if an exception is thrown
});

// Manual transaction control
await db.beginTransaction();
try {
  await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Alice']);
  await db.executeSql('INSERT INTO users (name) VALUES (?)', params: ['Bob']);
  await db.commit();
} catch (_) {
  await db.rollback();
  rethrow;
}
```

## 📱 Platform Notes

- **iOS/macOS**: Uses xcframework for optimal performance
- **Android**: Native library automatically included
- **Windows/Linux**: Dynamic libraries bundled with app
- **Web**: Requires manual setup of JavaScript SQLite library

## ⚠️ Thread Safety

This plugin is designed to be used from the **main isolate only**. The singleton instances and native database pointers are not shared across Dart isolates.

If you need to perform database operations from a background isolate (e.g. via `Isolate.run` or `compute`), you should:
- Perform all database operations on the main isolate, or
- Open a separate database connection within the background isolate

Concurrent writes from multiple isolates to the same database file may cause corruption.

## 🔧 Development

To contribute or build from source, see the [example app](example/) for a complete implementation.

## 📄 License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.