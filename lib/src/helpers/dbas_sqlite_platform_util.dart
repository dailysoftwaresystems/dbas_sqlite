import 'package:flutter/foundation.dart';
import 'dart:io';

class DbasSqlitePlatformUtil {
  static bool isTest() {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  }
}
