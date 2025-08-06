import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'dbas_sqlite_native_interface.dart';

@JS('globalThis')
external JSObject get _globalThis;

@JS()
@staticInterop
class DbasSqliteNativeWebJS {}

extension DbasSqliteNativeWebJSExtension on DbasSqliteNativeWebJS {
  external int _OpenDb(String path);
  external int _IsOpened(int dbPtr);
  external int _ExecuteSql(int dbPtr, String sql);
  external int _PrepareQuery(int dbPtr, String sql);

  external void _BindNull(int stmt, int index);
  external void _BindInt(int stmt, int index, int value);
  external void _BindFloat(int stmt, int index, double value);
  external void _BindDouble(int stmt, int index, double value);
  external void _BindText(int stmt, int index, String value);
  external void _BindBlob(int stmt, int index, JSArray<JSNumber> value);

  external void _BindNameNull(int stmt, String name);
  external void _BindNameInt(int stmt, String name, int value);
  external void _BindNameFloat(int stmt, String name, double value);
  external void _BindNameDouble(int stmt, String name, double value);
  external void _BindNameText(int stmt, String name, String value);
  external void _BindNameBlob(int stmt, String name, JSArray<JSNumber> value);

  external int _ReadRow(int stmt);
  external int _IsNull(int stmt, int colIndex);

  external String _GetColumnText(int stmt, int colIndex);
  external int _GetColumnInt(int stmt, int colIndex);
  external double _GetColumnFloat(int stmt, int colIndex);
  external double _GetColumnDouble(int stmt, int colIndex);
  external JSArray<JSNumber> _GetColumnBlob(int stmt, int columnIndex);
  external int _GetColumnBytes(int stmt, int columnIndex);
  external int _GetColumnType(int stmt, int colIndex);
  external int _GetColumnCount(int stmt);

  external String _GetLastDbError(int dbPtr);
  external int _GetAffectedRows(int dbPtr);
  external int _GetLastInsertedId(int dbPtr);

  external void _CloseReader(int stmt);
  external void _CloseDb(int dbPtr);
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
  int openDb(String path) => _js._OpenDb(path);

  @override
  bool isOpened(int dbPtr) => _js._IsOpened(dbPtr) == 1;

  @override
  int executeSql(int dbPtr, String sql) => _js._ExecuteSql(dbPtr, sql);

  @override
  int prepareQuery(int dbPtr, String sql) => _js._PrepareQuery(dbPtr, sql);

  @override
  void bindNull(int stmt, int index) => _js._BindNull(stmt, index);

  @override
  void bindInt(int stmt, int index, int value) => _js._BindInt(stmt, index, value);

  @override
  void bindFloat(int stmt, int index, double value) => _js._BindFloat(stmt, index, value);

  @override
  void bindDouble(int stmt, int index, double value) => _js._BindDouble(stmt, index, value);

  @override
  void bindText(int stmt, int index, String value) => _js._BindText(stmt, index, value);

  JSArray<JSNumber> _jsArrayFromIntList(List<int> value) =>
      (value.map((e) => e.toJS).toList()).toJS;

  List<int> _intListFromJSArray(JSArray<JSNumber> jsArray) =>
      jsArray.toDart.cast<num>().map((e) => e.toInt()).toList();

  @override
  void bindBlob(int stmt, int index, List<int> value) {
    _js._BindBlob(stmt, index, _jsArrayFromIntList(value));
  }

  @override
  void bindNameNull(int stmt, String name) => _js._BindNameNull(stmt, name);

  @override
  void bindNameInt(int stmt, String name, int value) => _js._BindNameInt(stmt, name, value);

  @override
  void bindNameFloat(int stmt, String name, double value) => _js._BindNameFloat(stmt, name, value);

  @override
  void bindNameDouble(int stmt, String name, double value) => _js._BindNameDouble(stmt, name, value);

  @override
  void bindNameText(int stmt, String name, String value) => _js._BindNameText(stmt, name, value);

  @override
  void bindNameBlob(int stmt, String name, List<int> value) {
    _js._BindNameBlob(stmt, name, _jsArrayFromIntList(value));
  }

  @override
  int readRow(int stmt) => _js._ReadRow(stmt);

  @override
  bool isNull(int stmt, int colIndex) => _js._IsNull(stmt, colIndex) == 1;

  @override
  String getColumnText(int stmt, int colIndex) => _js._GetColumnText(stmt, colIndex);

  @override
  int getColumnInt(int stmt, int colIndex) => _js._GetColumnInt(stmt, colIndex);

  @override
  double getColumnFloat(int stmt, int colIndex) => _js._GetColumnFloat(stmt, colIndex);

  @override
  double getColumnDouble(int stmt, int colIndex) => _js._GetColumnDouble(stmt, colIndex);

  @override
  List<int> getColumnBlob(int stmt, int columnIndex) {
    return _intListFromJSArray(_js._GetColumnBlob(stmt, columnIndex));
  }

  @override
  int getColumnBytes(int stmt, int columnIndex) => _js._GetColumnBytes(stmt, columnIndex);

  @override
  int getColumnType(int stmt, int colIndex) => _js._GetColumnType(stmt, colIndex);

  @override
  int getColumnCount(int stmt) => _js._GetColumnCount(stmt);

  @override
  String getLastDbError(int dbPtr) => _js._GetLastDbError(dbPtr);

  @override
  int getAffectedRows(int dbPtr) => _js._GetAffectedRows(dbPtr);

  @override
  int getLastInsertedId(int dbPtr) => _js._GetLastInsertedId(dbPtr);

  @override
  void closeReader(int stmt) => _js._CloseReader(stmt);

  @override
  Future<void> closeDb(int dbPtr) async {
    _js._CloseDb(dbPtr);

    final persistDB = _globalThis.getProperty('persistDB'.toJS) as JSFunction?;
    if (persistDB != null && _module != null) {
      persistDB.callAsFunction(_globalThis, _module!);
    }
  }
}
