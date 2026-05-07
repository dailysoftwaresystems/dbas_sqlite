import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const String _appDbDir = 'dbas_data';

/// Returns the database directory, creating it if needed. In test
/// mode resolves to `<cwd>/test/db`; otherwise to the per-platform
/// application support directory joined with `/dbas_data`.
Future<String> resolveDatabaseDirectory({required bool isTest}) async {
  if (isTest) {
    final dbPath = path.join(Directory.current.path, 'test', 'db');
    final dbDir = Directory(dbPath);
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    return dbPath;
  }
  final directory = await getApplicationSupportDirectory();
  final dirPath = '${directory.path}/$_appDbDir'.replaceAll('\\', '/');
  final dir = Directory(dirPath);
  if (!await dir.exists()) await dir.create(recursive: true);
  return dirPath;
}
