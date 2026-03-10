import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'dbas_sqlite_native_interface.dart';

@JS('globalThis')
external JSObject get _globalThis;

@JS()
@staticInterop
class IndexedDB {}

@JS()
@staticInterop
class IDBInfo {}

@JS()
@staticInterop
class IDBDatabase {}

@JS()
@staticInterop
class IDBTransaction {}

@JS()
@staticInterop
class IDBObjectStore {}

@JS()
@staticInterop
class DbasSqliteNativeWebJS {}

extension DbasSqliteNativeWebJSExtension on DbasSqliteNativeWebJS {
  external JSPromise databaseExists();
  external JSPromise attachDb(JSArray<JSNumber> content);
  external JSPromise openDb();
  external int isOpened(int dbPtr);
  external int executeSql(int dbPtr, JSString sql, [bool syncDb = false]);
  external int prepareQuery(int dbPtr, JSString sql);

  external int bindNull(int dbPtr, int index);
  external int bindInt(int dbPtr, int index, int value);
  external int bindFloat(int dbPtr, int index, double value);
  external int bindDouble(int dbPtr, int index, double value);
  external int bindText(int dbPtr, int index, String value);
  external int bindBlob(int dbPtr, int index, JSArray<JSNumber> value);

  external int bindNameNull(int dbPtr, JSString name);
  external int bindNameInt(int dbPtr, JSString name, int value);
  external int bindNameFloat(int dbPtr, JSString name, double value);
  external int bindNameDouble(int dbPtr, JSString name, double value);
  external int bindNameText(int dbPtr, JSString name, JSString value);
  external int bindNameBlob(int dbPtr, JSString name, JSArray<JSNumber> value);

  external int readRow(int dbPtr, [bool syncDb = false]);
  external int isNull(int dbPtr, int colIndex);

  external JSString getColumnText(int dbPtr, int colIndex);
  external int getColumnInt(int dbPtr, int colIndex);
  external double getColumnFloat(int dbPtr, int colIndex);
  external double getColumnDouble(int dbPtr, int colIndex);
  external JSArray<JSNumber> getColumnBlob(int dbPtr, int columnIndex);
  external int getColumnBytes(int dbPtr, int columnIndex);
  external JSString getColumnName(int dbPtr, int colIndex);
  external int getColumnType(int dbPtr, int colIndex);
  external int getColumnCount(int dbPtr);

  external JSString getLastDbError(int dbPtr);
  external int getAffectedRows(int dbPtr);
  external int getLastInsertedId(int dbPtr);

  external void closeReader(int dbPtr);
  external JSPromise closeDb(int dbPtr);
}

extension GlobalThisExt on JSObject {
  external IndexedDB get indexedDB;
}

extension IndexedDBExt on IndexedDB {
  external JSPromise databases();
  external JSPromise open(String name, int version, JSAny? options);
}

extension IDBInfoExt on IDBInfo {
  external String? get name;
}

extension IDBDatabaseExt on IDBDatabase {
  external IDBTransaction transaction(String storeName, String mode);
}

extension IDBTransactionExt on IDBTransaction {
  external IDBObjectStore objectStore(String storeName);
  external void commit();
}

extension IDBObjectStoreExt on IDBObjectStore {
  external void put(JSAny value, JSAny key);
  external void delete(JSAny key);
}

class DbasSqliteNativeWeb extends DbasSqliteNativeInterface {
  late final DbasSqliteNativeWebJS _js;
  static JSObject? _module;

  DbasSqliteNativeWeb(super.dbName);

  static void registerWith(Registrar registrar) {
    // This method is called by the Flutter framework to register the plugin.
  }

  @override
  Future<void> initialize() async {
    if (_module != null) {
      _js = _module! as DbasSqliteNativeWebJS;
      return;
    }

    try {
      _module = await loadDbasSqliteModule();
      _js = _module! as DbasSqliteNativeWebJS;
    } catch (e) {
      throw Exception('Failed to initialize DbasSqliteNativeWeb: ${e.toString()}');
    }
  }

  Future<JSObject> loadDbasSqliteModule() async {
    try {
      final initPersistentFS = _globalThis.getProperty('initPersistentFS'.toJS) as JSFunction?;

      if (initPersistentFS == null) {
        throw Exception('Failed to load DbasSqlite persistence functionality.');
      }

      final modulePromise = initPersistentFS.callAsFunction(_globalThis, dbName.toJS) as JSPromise;
      _module = await modulePromise.toDart as JSObject;
      
      return _module!;
    } catch (e) {
      throw Exception('Failed to load DbasSqlite module: $e');
    }
  }

  @override
  Future<int> openDb(String path) async {
    final result = await _js.openDb().toDart;
    return result.dartify() as int;
  }

  @override
  Future<bool> databaseExists(String fileName) async {
    final result = await _js.databaseExists().toDart;
    return result.dartify() as bool;
  }

  @override
  Future attachDb(String fileName, List<int> content) async {
    await _js.attachDb(_jsArrayFromIntList(content)).toDart;
  }

  @override
  Future<List<int>> getContent(String fileName) async {
    final fs = _module!.getProperty('FS'.toJS);
    final args = JSArray();
    args.add(fileName.toJS);
    final jsBytes = (fs as JSObject).callMethod('readFile'.toJS, args);
    final buffer = (jsBytes as JSUint8Array).toDart;
    return buffer;
  }

  @override
  Future dropDb(String fileName) async {
    try {
      final dropDb = _globalThis.getProperty('dropDb'.toJS) as JSFunction?;

      if (dropDb == null) {
        throw Exception('Failed to load DbasSqlite persistence functionality.');
      }

      final modulePromise = dropDb.callAsFunction(_globalThis) as JSPromise;
      await modulePromise.toDart;
    } catch (e) {
      throw Exception('Failed to load DbasSqlite module: $e');
    }
  }

  @override
  bool isOpened(int dbPtr) => _js.isOpened(dbPtr) == 1;

  @override
  Future<int> executeSql(int dbPtr, String sql, {bool syncWebDb = false}) async {
    return _js.executeSql(dbPtr, sql.toJS, syncWebDb);
  }

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async {
    return _js.prepareQuery(dbPtr, sql.toJS);
  }

  @override
  int bindNull(int dbPtr, int index) => _js.bindNull(dbPtr, index);

  @override
  int bindInt(int dbPtr, int index, int value) => _js.bindInt(dbPtr, index, value);

  @override
  int bindFloat(int dbPtr, int index, double value) => _js.bindFloat(dbPtr, index, value);

  @override
  int bindDouble(int dbPtr, int index, double value) => _js.bindDouble(dbPtr, index, value);

  @override
  int bindText(int dbPtr, int index, String value) => _js.bindText(dbPtr, index, value);

  JSArray<JSNumber> _jsArrayFromIntList(List<int> value) =>
      (value.map((e) => e.toJS).toList()).toJS;

  List<int> _intListFromJSArray(JSArray<JSNumber> jsArray) =>
      jsArray.toDart.cast<num>().map((e) => e.toInt()).toList();

  @override
  int bindBlob(int dbPtr, int index, List<int> value) {
    return _js.bindBlob(dbPtr, index, _jsArrayFromIntList(value));
  }

  @override
  int bindNameNull(int dbPtr, String name) => _js.bindNameNull(dbPtr, name.toJS);

  @override
  int bindNameInt(int dbPtr, String name, int value) => _js.bindNameInt(dbPtr, name.toJS, value);

  @override
  int bindNameFloat(int dbPtr, String name, double value) => _js.bindNameFloat(dbPtr, name.toJS, value);

  @override
  int bindNameDouble(int dbPtr, String name, double value) => _js.bindNameDouble(dbPtr, name.toJS, value);

  @override
  int bindNameText(int dbPtr, String name, String value) => _js.bindNameText(dbPtr, name.toJS, value.toJS);

  @override
  int bindNameBlob(int dbPtr, String name, List<int> value) {
    return _js.bindNameBlob(dbPtr, name.toJS, _jsArrayFromIntList(value));
  }

  @override
  Future<int> readRow(int dbPtr, {bool syncWebDb = false}) async {
    return _js.readRow(dbPtr, syncWebDb);
  }

  @override
  bool isNull(int dbPtr, int colIndex) => _js.isNull(dbPtr, colIndex) == 1;

  @override
  String getColumnText(int dbPtr, int colIndex) => _js.getColumnText(dbPtr, colIndex).toDart;

  @override
  int getColumnInt(int dbPtr, int colIndex) => _js.getColumnInt(dbPtr, colIndex);

  @override
  double getColumnFloat(int dbPtr, int colIndex) => _js.getColumnFloat(dbPtr, colIndex);

  @override
  double getColumnDouble(int dbPtr, int colIndex) => _js.getColumnDouble(dbPtr, colIndex);

  @override
  List<int> getColumnBlob(int dbPtr, int columnIndex) {
    return _intListFromJSArray(_js.getColumnBlob(dbPtr, columnIndex));
  }

  @override
  int getColumnBytes(int dbPtr, int columnIndex) => _js.getColumnBytes(dbPtr, columnIndex);

  @override
  String getColumnName(int dbPtr, int colIndex) => _js.getColumnName(dbPtr, colIndex).toDart;

  @override
  int getColumnType(int dbPtr, int colIndex) => _js.getColumnType(dbPtr, colIndex);

  @override
  int getColumnCount(int dbPtr) => _js.getColumnCount(dbPtr);

  @override
  String? getLastDbError(int dbPtr) {
    final result = _js.getLastDbError(dbPtr).toDart;

    if (result.startsWith('Unknown error:')) {
      return null;
    }

    return result;
  }

  @override
  int getAffectedRows(int dbPtr) => _js.getAffectedRows(dbPtr);

  @override
  int getLastInsertedId(int dbPtr) => _js.getLastInsertedId(dbPtr);

  @override
  Future closeReader(int dbPtr) async {
    _js.closeReader(dbPtr);
  }

  @override
  Future<void> closeDb(int dbPtr) async {
    await _js.closeDb(dbPtr).toDart;
  }
}
