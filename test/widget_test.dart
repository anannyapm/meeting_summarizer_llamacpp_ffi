// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
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

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
          ChangeNotifierProvider<RecordingProvider>(
            create: (_) => RecordingProvider(RecordingService()),
          ),
          ChangeNotifierProvider<TranscriptionProvider>(
            create: (_) => TranscriptionProvider(TranscriptionService()),
          ),
          ChangeNotifierProvider<SummarizationProvider>(
            create: (_) => SummarizationProvider(
              SummarizationService(modelPath: 'test-model-path'),
            ),
          ),
          ChangeNotifierProvider<SummaryHistoryProvider>(
            create: (_) => SummaryHistoryProvider(),
          ),
        ],
        child: const AppShell(
          initialModelPath: 'test-model-path',
          skipInitialSetup: true,
        ),
      ),
    );

    // Verify that the app launches
    expect(find.text('Meeting Summarizer'), findsOneWidget);
  });
}
