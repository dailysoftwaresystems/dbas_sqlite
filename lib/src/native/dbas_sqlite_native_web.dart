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
  external int executeSql(int dbPtr, JSString sql);
  external int prepareQuery(int dbPtr, JSString sql);

  external void bindNull(int stmt, int index);
  external void bindInt(int stmt, int index, int value);
  external void bindFloat(int stmt, int index, double value);
  external void bindDouble(int stmt, int index, double value);
  external void bindText(int stmt, int index, String value);
  external void bindBlob(int stmt, int index, JSArray<JSNumber> value);

  external void bindNameNull(int stmt, JSString name);
  external void bindNameInt(int stmt, JSString name, int value);
  external void bindNameFloat(int stmt, JSString name, double value);
  external void bindNameDouble(int stmt, JSString name, double value);
  external void bindNameText(int stmt, JSString name, JSString value);
  external void bindNameBlob(int stmt, JSString name, JSArray<JSNumber> value);

  external int readRow(int stmt);
  external int isNull(int stmt, int colIndex);

  external JSString getColumnText(int stmt, int colIndex);
  external int getColumnInt(int stmt, int colIndex);
  external double getColumnFloat(int stmt, int colIndex);
  external double getColumnDouble(int stmt, int colIndex);
  external JSArray<JSNumber> getColumnBlob(int stmt, int columnIndex);
  external int getColumnBytes(int stmt, int columnIndex);
  external JSString getColumnName(int stmt, int colIndex);
  external int getColumnType(int stmt, int colIndex);
  external int getColumnCount(int stmt);

  external JSString getLastDbError(int dbPtr);
  external int getAffectedRows(int dbPtr);
  external int getLastInsertedId(int dbPtr);

  external void closeReader(int stmt);
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
  Future<int> executeSql(int dbPtr, String sql) async {
    return _js.executeSql(dbPtr, sql.toJS);
  }

  @override
  Future<int> prepareQuery(int dbPtr, String sql) async {
    return _js.prepareQuery(dbPtr, sql.toJS);
  }

  @override
  void bindNull(int stmt, int index) => _js.bindNull(stmt, index);

  @override
  void bindInt(int stmt, int index, int value) => _js.bindInt(stmt, index, value);

  @override
  void bindFloat(int stmt, int index, double value) => _js.bindFloat(stmt, index, value);

  @override
  void bindDouble(int stmt, int index, double value) => _js.bindDouble(stmt, index, value);

  @override
  void bindText(int stmt, int index, String value) => _js.bindText(stmt, index, value);

  JSArray<JSNumber> _jsArrayFromIntList(List<int> value) =>
      (value.map((e) => e.toJS).toList()).toJS;

  List<int> _intListFromJSArray(JSArray<JSNumber> jsArray) =>
      jsArray.toDart.cast<num>().map((e) => e.toInt()).toList();

  @override
  void bindBlob(int stmt, int index, List<int> value) {
    _js.bindBlob(stmt, index, _jsArrayFromIntList(value));
  }

  @override
  void bindNameNull(int stmt, String name) => _js.bindNameNull(stmt, name.toJS);

  @override
  void bindNameInt(int stmt, String name, int value) => _js.bindNameInt(stmt, name.toJS, value);

  @override
  void bindNameFloat(int stmt, String name, double value) => _js.bindNameFloat(stmt, name.toJS, value);

  @override
  void bindNameDouble(int stmt, String name, double value) => _js.bindNameDouble(stmt, name.toJS, value);

  @override
  void bindNameText(int stmt, String name, String value) => _js.bindNameText(stmt, name.toJS, value.toJS);

  @override
  void bindNameBlob(int stmt, String name, List<int> value) {
    _js.bindNameBlob(stmt, name.toJS, _jsArrayFromIntList(value));
  }

  @override
  Future<int> readRow(int stmt) async {
    return _js.readRow(stmt);
  }

  @override
  bool isNull(int stmt, int colIndex) => _js.isNull(stmt, colIndex) == 1;

  @override
  String getColumnText(int stmt, int colIndex) => _js.getColumnText(stmt, colIndex).toDart;

  @override
  int getColumnInt(int stmt, int colIndex) => _js.getColumnInt(stmt, colIndex);

  @override
  double getColumnFloat(int stmt, int colIndex) => _js.getColumnFloat(stmt, colIndex);

  @override
  double getColumnDouble(int stmt, int colIndex) => _js.getColumnDouble(stmt, colIndex);

  @override
  List<int> getColumnBlob(int stmt, int columnIndex) {
    return _intListFromJSArray(_js.getColumnBlob(stmt, columnIndex));
  }

  @override
  int getColumnBytes(int stmt, int columnIndex) => _js.getColumnBytes(stmt, columnIndex);

  @override
  String getColumnName(int stmt, int colIndex) => _js.getColumnName(stmt, colIndex).toDart;

  @override
  int getColumnType(int stmt, int colIndex) => _js.getColumnType(stmt, colIndex);

  @override
  int getColumnCount(int stmt) => _js.getColumnCount(stmt);

  @override
  String getLastDbError(int dbPtr) {
    return _js.getLastDbError(dbPtr).toDart;
  }

  @override
  int getAffectedRows(int dbPtr) => _js.getAffectedRows(dbPtr);

  @override
  int getLastInsertedId(int dbPtr) => _js.getLastInsertedId(dbPtr);

  @override
  Future closeReader(int stmt) async {
    _js.closeReader(stmt);
  }

  @override
  Future<void> closeDb(int dbPtr) async {
    await _js.closeDb(dbPtr).toDart;
  }
}
