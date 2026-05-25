import 'package:flutter/material.dart';
import 'package:ffi_learn/screens/meeting_summarizer_screen.dart';

/// Main app widget with theme configuration
class App extends StatelessWidget {
  final String? initialModelPath;

  const App({
    super.key,
    this.initialModelPath,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Offline Meeting Summarizer',
      theme: ThemeData.dark(
        useMaterial3: true,
      ),
      home: MeetingSummarizerScreen(
        initialModelPath: initialModelPath,
      ),
    );
  }
}
