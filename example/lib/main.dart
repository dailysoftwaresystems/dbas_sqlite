import 'package:flutter/material.dart';
import 'dart:async';

import 'package:dbas_sqlite_flutter/dbas_sqlite.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isOpened = false;
  bool _exists = false;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    bool isOpened = false;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      final DbasSqlite plugin = await DbasSqlite.getInstance(dbName: 'dbas.db');
      print('Opening database');
      await plugin.openDb();
      isOpened = plugin.isOpened();
      _exists = await plugin.databaseExists();
      print('Running create table');
      await plugin.executeSql('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT UNIQUE NOT NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    } on Exception catch (e) {
      print('Failed: ${e.toString()}');
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _isOpened = isOpened;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Text('Is opened: $_isOpened, exists: $_exists\n'),
        ),
      ),
    );
  }
}
