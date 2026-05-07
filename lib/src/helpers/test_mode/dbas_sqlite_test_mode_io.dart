import 'dart:io';

bool isFlutterTestEnv() =>
    Platform.environment.containsKey('FLUTTER_TEST');
