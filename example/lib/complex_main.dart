import 'package:flutter/material.dart';
import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';

void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SQLite Persistence Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const TestPage(),
    );
  }
}

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  String _status = 'Initializing...';
  DbasSqlite? _db;

  @override
  void initState() {
    super.initState();
    _testPersistence();
  }

  Future<void> _testPersistence() async {
    try {
      setState(() {
        _status = 'Getting database instance...';
      });

      _db = await DbasSqlite.getInstance(dbName: 'test_persistence.db');
      
      setState(() {
        _status = 'Getting database path...';
      });

      final dbPath = await _db!.getAppDatabasePath();
      
      setState(() {
        _status = 'Opening database at: $dbPath';
      });

      await _db!.openDb(dbPath);
      
      setState(() {
        _status = 'Creating table...';
      });

      await _db!.executeSql('''
        CREATE TABLE IF NOT EXISTS test_data (
          id INTEGER PRIMARY KEY,
          name TEXT,
          value INTEGER,
          created_at TEXT
        );
      ''');

      setState(() {
        _status = 'Inserting test data...';
      });

      await _db!.executeSql('''
        INSERT OR REPLACE INTO test_data (id, name, value, created_at) 
        VALUES (1, ?, ?, ?);
      ''', params: ['Test Entry', DateTime.now().millisecondsSinceEpoch, DateTime.now().toIso8601String()]);

      setState(() {
        _status = 'Reading data...';
      });

      await _db!.executeReader('SELECT COUNT(*) FROM test_data;');
      int count = 0;
      if (_db!.readRow()) {
        count = _db!.getColumnInt(0);
      }

      setState(() {
        _status = 'Database ready! Found $count records.\nLast update: ${DateTime.now()}';
      });

    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _addData() async {
    try {
      if (_db == null) return;
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await _db!.executeSql('''
        INSERT INTO test_data (name, value, created_at) 
        VALUES (?, ?, ?);
      ''', params: ['New Entry', timestamp, DateTime.now().toIso8601String()]);

      await _db!.executeReader('SELECT COUNT(*) as count FROM test_data;');
      int count = 0;
      if (_db!.readRow()) {
        count = _db!.getColumnInt(0);
      }

      setState(() {
        _status = 'Added new record! Total: $count records.\nLast update: ${DateTime.now()}';
      });
    } catch (e) {
      setState(() {
        _status = 'Error adding data: $e';
      });
    }
  }

  @override
  void dispose() {
    _db?.closeDb();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQLite Persistence Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SQLite Web Persistence Test',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'This test creates a persistent SQLite database on the web using IndexedDB.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            Text(
              'Status: $_status',
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _addData,
              child: const Text('Add Test Data'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _testPersistence,
              child: const Text('Refresh Data'),
            ),
            const SizedBox(height: 20),
            const Text(
              'Instructions:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Text(
              '1. Click "Add Test Data" to insert records\n'
              '2. Refresh the browser page\n'
              '3. Check if data persists after reload\n'
              '4. Check browser console for persistence logs',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
