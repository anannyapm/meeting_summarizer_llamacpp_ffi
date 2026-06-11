import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffi_learn/model_manager.dart';
import 'package:ffi_learn/models/model_presets.dart';

/// Manages app-wide settings including developer mode toggle and model selection.
class SettingsProvider extends ChangeNotifier {
  static const String _devModeKey = 'dev_mode_enabled';
  static const String _selectedModelPresetKey = 'selected_model_preset_id';

  late SharedPreferences _prefs;
  bool _devModeEnabled = false;
  String _selectedModelPresetId = AppModelPresets.defaultModelId;
  String? _resolvedModelPath;

  bool get devModeEnabled => _devModeEnabled;
  String get selectedModelPresetId => _selectedModelPresetId;
  String? get resolvedModelPath => _resolvedModelPath;
  bool get hasDownloadedModel => _resolvedModelPath != null;

  /// Initialize preferences (call this on app startup)
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _devModeEnabled = _prefs.getBool(_devModeKey) ?? false;
    _selectedModelPresetId =
        _prefs.getString(_selectedModelPresetKey) ??
        AppModelPresets.defaultModelId;
    await _resolveModelPath();
    notifyListeners();
  }

  Future<void> _resolveModelPath() async {
    final preset = AppModelPresets.resolveById(_selectedModelPresetId);
    final manager = ModelManager(modelName: preset.fileName);
    if (await manager.checkIfDownloaded()) {
      _resolvedModelPath = await manager.getLocalPath();
    } else {
      _resolvedModelPath = null;
    }
  }

  /// Persist the selected model preset and refresh the on-disk path if available.
  Future<void> setSelectedModelPreset(String presetId) async {
    _selectedModelPresetId = presetId;
    await _prefs.setString(_selectedModelPresetKey, presetId);
    await _resolveModelPath();
    notifyListeners();
  }

  /// Refresh resolved path after a download completes.
  Future<void> refreshModelPath() async {
    await _resolveModelPath();
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
