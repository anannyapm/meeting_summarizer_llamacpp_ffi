import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages app-wide settings including developer mode toggle
class SettingsProvider extends ChangeNotifier {
  static const String _devModeKey = 'dev_mode_enabled';

  late SharedPreferences _prefs;
  bool _devModeEnabled = false;

  bool get devModeEnabled => _devModeEnabled;

  /// Initialize preferences (call this on app startup)
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _devModeEnabled = _prefs.getBool(_devModeKey) ?? false;
    notifyListeners();
  }

  /// Toggle developer mode on/off
  Future<void> toggleDevMode() async {
    _devModeEnabled = !_devModeEnabled;
    await _prefs.setBool(_devModeKey, _devModeEnabled);
    notifyListeners();
  }

  /// Explicitly enable dev mode
  Future<void> enableDevMode() async {
    if (!_devModeEnabled) {
      _devModeEnabled = true;
      await _prefs.setBool(_devModeKey, true);
      notifyListeners();
    }
  }

  /// Explicitly disable dev mode
  Future<void> disableDevMode() async {
    if (_devModeEnabled) {
      _devModeEnabled = false;
      await _prefs.setBool(_devModeKey, false);
      notifyListeners();
    }
  }
}
