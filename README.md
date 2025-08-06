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
  - `openDb(path)` - Open database connection
  - `closeDb()` - Close database connection  
  - `isOpened()` - Check connection status
  - `getAppDatabasePath()` - Get platform-specific database path

- **SQL Execution**
  - `executeSql(sql)` - Execute DDL/DML statements
  - `prepareQuery(sql)` - Prepare parameterized queries
  - `readRow()` - Read query results row by row

### 🔗 **Parameter Binding**
- **By Index** (1-based indexing)
  - `bindNull(index)` - Bind NULL value
  - `bindInt(index, value)` - Bind integer
  - `bindFloat(index, value)` - Bind float
  - `bindDouble(index, value)` - Bind double
  - `bindDecimal(index, value)` - Bind decimal numbers
  - `bindText(index, value)` - Bind string
  - `bindBlob(index, value)` - Bind binary data

- **By Name** (named parameters)
  - `bindNameNull(name)` - Bind NULL by name
  - `bindNameInt(name, value)` - Bind integer by name
  - `bindNameFloat(name, value)` - Bind float by name
  - `bindNameDouble(name, value)` - Bind double by name
  - `bindNameDecimal(name, value)` - Bind decimal by name
  - `bindNameText(name, value)` - Bind string by name
  - `bindNameBlob(name, value)` - Bind binary data by name

### 📊 **Data Retrieval**
- **Column Access**
  - `getColumnText(index)` - Get string value
  - `getColumnInt(index)` - Get integer value
  - `getColumnFloat(index)` - Get float value
  - `getColumnDouble(index)` - Get double value
  - `getColumnDecimal(index)` - Get decimal value
  - `getColumnBlob(index)` - Get binary data
  - `isColumnNull(index)` - Check if column is NULL
  - `getColumnType(index)` - Get column data type
  - `getColumnCount()` - Get number of columns

### 🔍 **Query Information**
- `getLastDbError()` - Get last database error
- `getAffectedRows()` - Get number of affected rows
- `getLastInsertedId()` - Get last inserted row ID

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dbas_sqlite_flutter: ^0.0.1
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

// Get database path and open
final String dbPath = await db.getAppDatabasePath();
await db.openDb(dbPath);

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

// Insert data with parameters
await db.prepareQuery('INSERT INTO users (name, email, age) VALUES (?, ?, ?)');
await db.bindText(1, 'John Doe');
await db.bindText(2, 'john@example.com');
await db.bindInt(3, 30);
await db.executeSql('');

// Query data
await db.prepareQuery('SELECT * FROM users WHERE age > ?');
await db.bindInt(1, 25);

List<Map<String, dynamic>> users = [];
while (await db.readRow()) {
  Map<String, dynamic> user = {};
  for (int i = 0; i < await db.getColumnCount(); i++) {
    String columnName = // Get column name from your schema
    
    if (await db.isColumnNull(i)) {
      user[columnName] = null;
    } else {
      switch (await db.getColumnType(i)) {
        case SqliteColumnType.integer:
          user[columnName] = await db.getColumnInt(i);
          break;
        case SqliteColumnType.real:
          user[columnName] = await db.getColumnDouble(i);
          break;
        case SqliteColumnType.text:
          user[columnName] = await db.getColumnText(i);
          break;
        case SqliteColumnType.blob:
          user[columnName] = await db.getColumnBlob(i);
          break;
      }
    }
  }
  users.add(user);
}

// Close database
await db.closeDb();
```

### Named Parameters Example

```dart
await db.prepareQuery('INSERT INTO users (name, email, age) VALUES (:name, :email, :age)');
await db.bindNameText(':name', 'Jane Smith');
await db.bindNameText(':email', 'jane@example.com');
await db.bindNameInt(':age', 28);
await db.executeSql('');
```

## 📱 Platform Notes

- **iOS/macOS**: Uses xcframework for optimal performance
- **Android**: Native library automatically included
- **Windows/Linux**: Dynamic libraries bundled with app
- **Web**: Requires manual setup of JavaScript SQLite library

## 🔧 Development

To contribute or build from source, see the [example app](example/) for a complete implementation.

## 📄 License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.