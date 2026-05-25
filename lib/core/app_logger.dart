import 'package:flutter/foundation.dart';

class AppLogger {
  static void log(String tag, String message) {
    final now = DateTime.now().toIso8601String();
    debugPrint('[$now][$tag] $message');
  }
}
