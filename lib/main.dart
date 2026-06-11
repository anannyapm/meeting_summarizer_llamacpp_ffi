import 'package:flutter/material.dart';

import 'package:ffi_learn/app_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Platform channels (e.g. shared_preferences Pigeon) are not ready until after
  // runApp — bootstrap loads prefs inside the widget tree.
  runApp(const AppBootstrap());
}
