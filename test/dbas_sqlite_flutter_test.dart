import 'package:flutter_test/flutter_test.dart';
import 'package:dbas_sqlite_flutter/dbas_sqlite_flutter.dart';
import 'package:dbas_sqlite_flutter/dbas_sqlite_flutter_platform_interface.dart';
import 'package:dbas_sqlite_flutter/dbas_sqlite_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDbasSqliteFlutterPlatform
    with MockPlatformInterfaceMixin
    implements DbasSqliteFlutterPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DbasSqliteFlutterPlatform initialPlatform = DbasSqliteFlutterPlatform.instance;

  test('$MethodChannelDbasSqliteFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDbasSqliteFlutter>());
  });

  test('getPlatformVersion', () async {
    DbasSqliteFlutter dbasSqliteFlutterPlugin = DbasSqliteFlutter();
    MockDbasSqliteFlutterPlatform fakePlatform = MockDbasSqliteFlutterPlatform();
    DbasSqliteFlutterPlatform.instance = fakePlatform;

    expect(await dbasSqliteFlutterPlugin.getPlatformVersion(), '42');
  });
}
