import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/screens/game_splash_screen.dart';
import 'package:ffi_learn/screens/meeting_summarizer_screen.dart';
import 'package:ffi_learn/services/model_setup_service.dart';

/// Hosts splash (download + load on first launch, quick load on return) then main app.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialModelPath,
    this.splashMode = SplashMode.firstLaunch,
    this.skipInitialSetup = false,
  });

  final String? initialModelPath;

  /// [SplashMode.quickLoad] when model file already on disk.
  final SplashMode splashMode;

  /// When true, skips splash (widget tests).
  final bool skipInitialSetup;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _setupComplete = false;
  String? _modelPath;

  @override
  void initState() {
    super.initState();
    _modelPath = widget.initialModelPath;
    _setupComplete = widget.skipInitialSetup;
  }

  void _onSetupComplete(String path) {
    setState(() {
      _modelPath = path;
      _setupComplete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Offline Meeting Summarizer',
      theme: ThemeData.dark(useMaterial3: true),
      home: Consumer<SummarizationProvider>(
        builder: (context, summarization, _) {
          final modelAlreadyWarm = summarization.isModelLoaded;
          final showMain =
              _setupComplete || modelAlreadyWarm || widget.skipInitialSetup;

          if (showMain) {
            final path = _modelPath ??
                summarization.currentModelPath ??
                widget.initialModelPath;
            return MeetingSummarizerScreen(initialModelPath: path);
          }

          return GameSplashScreen(
            mode: widget.splashMode,
            onComplete: _onSetupComplete,
          );
        },
      ),
    );
  }
}
