import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ffi_learn/app.dart';
import 'package:ffi_learn/providers/recording_provider.dart';
import 'package:ffi_learn/providers/settings_provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/providers/summary_history_provider.dart';
import 'package:ffi_learn/providers/transcription_provider.dart';
import 'package:ffi_learn/services/recording_service.dart';
import 'package:ffi_learn/services/summarization_service.dart';
import 'package:ffi_learn/services/transcription_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsProvider = SettingsProvider();
  await settingsProvider.init();
  final summaryHistoryProvider = SummaryHistoryProvider();
  await summaryHistoryProvider.init();

  final initialModelPath = settingsProvider.resolvedModelPath;
  debugPrint(
    'Bootstrap model preset=${settingsProvider.selectedModelPresetId} '
    'path=${initialModelPath ?? "not downloaded"}',
  );

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
            SummarizationService(modelPath: initialModelPath),
          ),
        ),
        ChangeNotifierProvider<SummaryHistoryProvider>.value(
          value: summaryHistoryProvider,
        ),
      ],
      child: App(initialModelPath: initialModelPath),
    ),
  );
}
