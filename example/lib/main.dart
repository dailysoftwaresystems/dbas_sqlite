import 'package:dbas_sqlite/dbas_sqlite.dart';
import 'package:flutter/material.dart';

import 'src/tabs/tab_crud.dart';
import 'src/tabs/tab_db_ops.dart';
import 'src/tabs/tab_setup.dart';
import 'src/widgets/log_panel.dart';

void main() {
  runApp(const DbasExampleApp());
}

class DbasExampleApp extends StatelessWidget {
  const DbasExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DBAS SQLite Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  DbasSqlite? _db;
  bool _isLoading = false;
  final List<String> _log = [];
  final ScrollController _logScrollController = ScrollController();

  Future<void> _runOp(Future<void> Function() op) async {
    setState(() => _isLoading = true);
    try {
      await op();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addLog(String message) {
    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    setState(() {
      // Lines starting with spaces are continuation lines (e.g. row data), no timestamp
      if (message.startsWith(' ')) {
        _log.add('         $message');
      } else {
        _log.add('$timestamp $message');
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _clearLog() {
    setState(() {
      _log.clear();
    });
  }

  void _onDbChanged(DbasSqlite? newDb) {
    setState(() {
      _db = newDb;
    });
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _db?.closeDb();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DBAS SQLite Example'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.settings), text: 'Setup'),
              Tab(icon: Icon(Icons.table_chart), text: 'CRUD'),
              Tab(icon: Icon(Icons.storage), text: 'DB Ops'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  SetupTab(
                    db: _db,
                    isLoading: _isLoading,
                    onLog: _addLog,
                    onDbChanged: _onDbChanged,
                    runOp: _runOp,
                  ),
                  CrudTab(
                    db: _db,
                    isLoading: _isLoading,
                    onLog: _addLog,
                    runOp: _runOp,
                  ),
                  DbOpsTab(
                    db: _db,
                    isLoading: _isLoading,
                    onLog: _addLog,
                    onDbChanged: _onDbChanged,
                    runOp: _runOp,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: LogPanel(
                entries: _log,
                controller: _logScrollController,
                onClear: _clearLog,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
