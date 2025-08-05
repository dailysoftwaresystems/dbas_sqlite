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
      final DbasSqlite plugin = await DbasSqlite.getInstance();
      final dbPath = await plugin.getAppDatabasePath('dbas.db');
      print('Opening database at: $dbPath');
      await plugin.openDb(dbPath);
      isOpened = plugin.isOpened();
    } on Exception catch (e) {
      print('Failed to open db: ${e.toString()}');
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
          child: Text('Is opened: $_isOpened\n'),
        ),
      ),
    );
  }
}
