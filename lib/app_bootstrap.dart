import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ffi_learn/app.dart';
import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/providers/recording_provider.dart';
import 'package:ffi_learn/providers/settings_provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/providers/summary_history_provider.dart';
import 'package:ffi_learn/providers/transcription_provider.dart';
import 'package:ffi_learn/services/recording_service.dart';
import 'package:ffi_learn/services/summarization_service.dart';
import 'package:ffi_learn/services/transcription_service.dart';

class _BootstrapData {
  const _BootstrapData({
    required this.settingsProvider,
    required this.summaryHistoryProvider,
    required this.initialModelPath,
  });

  final SettingsProvider settingsProvider;
  final SummaryHistoryProvider summaryHistoryProvider;
  final String? initialModelPath;
}

/// Loads SharedPreferences-backed state after [runApp] so Pigeon platform
/// channels are available (required for release/profile builds).
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<_BootstrapData> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _bootstrap();
  }

  Future<_BootstrapData> _bootstrap() async {
    final settingsProvider = SettingsProvider();
    await settingsProvider.init();
    final summaryHistoryProvider = SummaryHistoryProvider();
    await summaryHistoryProvider.init();

    final initialModelPath = settingsProvider.resolvedModelPath;
    AppLogger.log(
      'BOOT',
      'preset=${settingsProvider.selectedModelPresetId} '
      'path=${initialModelPath ?? "not downloaded"}',
    );

    return _BootstrapData(
      settingsProvider: settingsProvider,
      summaryHistoryProvider: summaryHistoryProvider,
      initialModelPath: initialModelPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapData>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to start app:\n${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final data = snapshot.data!;
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: data.settingsProvider,
            ),
            ChangeNotifierProvider<RecordingProvider>(
              create: (_) => RecordingProvider(RecordingService()),
            ),
            ChangeNotifierProvider<TranscriptionProvider>(
              create: (_) => TranscriptionProvider(TranscriptionService()),
            ),
            ChangeNotifierProvider<SummarizationProvider>(
              create: (_) => SummarizationProvider(
                SummarizationService(modelPath: data.initialModelPath),
              ),
            ),
            ChangeNotifierProvider<SummaryHistoryProvider>.value(
              value: data.summaryHistoryProvider,
            ),
          ],
          child: App(initialModelPath: data.initialModelPath),
        );
      },
    );
  }
}
