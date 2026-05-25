import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ffi_learn/app.dart';
import 'package:ffi_learn/models/model_presets.dart';
import 'package:ffi_learn/providers/recording_provider.dart';
import 'package:ffi_learn/providers/settings_provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/providers/summary_history_provider.dart';
import 'package:ffi_learn/providers/transcription_provider.dart';
import 'package:ffi_learn/services/recording_service.dart';
import 'package:ffi_learn/services/summarization_service.dart';
import 'package:ffi_learn/services/transcription_service.dart';

AppModelPreset _resolveBootstrapModel() {
  const requestedId = String.fromEnvironment(
    'MODEL_PRESET',
    defaultValue: AppModelPresets.defaultModelId,
  );
  return AppModelPresets.resolveById(requestedId);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize settings provider
  final settingsProvider = SettingsProvider();
  await settingsProvider.init();
  final summaryHistoryProvider = SummaryHistoryProvider();
  await summaryHistoryProvider.init();

  // Select default model preset.
  final selectedModel = _resolveBootstrapModel();
  debugPrint('Using model preset: ${selectedModel.id}');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProvider,
        ),
        ChangeNotifierProvider<RecordingProvider>(
          create: (_) => RecordingProvider(RecordingService()),
        ),
        ChangeNotifierProvider<TranscriptionProvider>(
          create: (_) => TranscriptionProvider(TranscriptionService()),
        ),
        ChangeNotifierProvider<SummarizationProvider>(
          create: (_) => SummarizationProvider(
            SummarizationService(modelPath: null),
          ),
        ),
        ChangeNotifierProvider<SummaryHistoryProvider>.value(
          value: summaryHistoryProvider,
        ),
      ],
      child: const App(),
    ),
  );
}

