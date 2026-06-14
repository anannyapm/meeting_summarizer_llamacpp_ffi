import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/providers/settings_provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/services/model_setup_service.dart';

/// Game-style first-launch splash: auto-download + load default model.
class GameSplashScreen extends StatefulWidget {
  const GameSplashScreen({
    super.key,
    required this.onComplete,
    this.mode = SplashMode.firstLaunch,
  });

  final void Function(String modelPath) onComplete;
  final SplashMode mode;

  @override
  State<GameSplashScreen> createState() => _GameSplashScreenState();
}

class _GameSplashScreenState extends State<GameSplashScreen>
    with SingleTickerProviderStateMixin {
  final ModelSetupService _setup = ModelSetupService();
  late final AnimationController _pulseController;

  ModelSetupProgress _progress = const ModelSetupProgress(
    phase: ModelSetupPhase.checking,
    progress: 0,
    message: 'Booting...',
  );
  String? _error;
  int _tipIndex = 0;
  Timer? _tipTimer;

  static const List<String> _loadingTips = <String>[
    'Tip: Everything runs on your phone — no cloud needed.',
    'Tip: Summaries stream token-by-token like a typewriter quest.',
    'Tip: Use Live mic or Record mode to capture meetings.',
    'Tip: Smaller models = faster; Llama 1B = best balance.',
    'Tip: First download is large — grab a coffee, hero!',
  ];

  static const List<String> _quickTips = <String>[
    'Loading your offline AI from disk...',
    'One moment while the neural engine warms up.',
  ];

  bool get _isQuick => widget.mode == SplashMode.quickLoad;

  Duration get _completeDelay =>
      _isQuick ? const Duration(milliseconds: 200) : const Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _tipTimer = Timer.periodic(
      Duration(seconds: _isQuick ? 3 : 4),
      (_) {
        if (!mounted) {
          return;
        }
        final tips = _isQuick ? _quickTips : _loadingTips;
        setState(() {
          _tipIndex = (_tipIndex + 1) % tips.length;
        });
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSetup());
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _runSetup() async {
    final settings = context.read<SettingsProvider>();
    final summarization = context.read<SummarizationProvider>();
    setState(() {
      _error = null;
    });
    try {
      final path = await _setup.ensureModelReady(
        settings: settings,
        summarization: summarization,
        mode: widget.mode,
        onProgress: (update) {
          if (!mounted) {
            return;
          }
          setState(() => _progress = update);
        },
      );
      await Future<void>.delayed(_completeDelay);
      if (!mounted) {
        return;
      }
      widget.onComplete(path);
    } catch (error) {
      AppLogger.log('BOOT', 'Setup failed: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _progress = ModelSetupProgress(
          phase: ModelSetupPhase.failed,
          progress: _progress.progress,
          message: 'Setup failed',
          detail: _error,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tips = _isQuick ? _quickTips : _loadingTips;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isQuick
                ? const <Color>[
                    Color(0xFF0D1B2A),
                    Color(0xFF1B263B),
                  ]
                : const <Color>[
                    Color(0xFF0D1B2A),
                    Color(0xFF1B263B),
                    Color(0xFF415A77),
                  ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _isQuick ? 32 : 28,
              vertical: _isQuick ? 32 : 24,
            ),
            child: Column(
              children: [
                const Spacer(flex: 1),
                _buildHeroIcon(),
                SizedBox(height: _isQuick ? 20 : 24),
                if (_isQuick) ...[
                  const Text(
                    'Meeting Summarizer',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Starting offline AI',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ] else ...[
                  Text(
                    'MEETING SUMMARIZER',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.amber.shade200,
                      shadows: <Shadow>[
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          offset: const Offset(2, 2),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'OFFLINE AI QUEST',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 4,
                      color: Colors.cyan.shade200.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                const Spacer(flex: 1),
                _buildXpBar(),
                const SizedBox(height: 16),
                Text(
                  _progress.message,
                  style: TextStyle(
                    fontSize: _isQuick ? 15 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (_progress.detail != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _progress.detail!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
                SizedBox(height: _isQuick ? 16 : 20),
                if (!_isQuick || _error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 18,
                          color: Colors.amber.shade300,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error ?? tips[_tipIndex],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _runSetup,
                    icon: const Icon(Icons.refresh),
                    label: Text(_isQuick ? 'Retry' : 'Retry quest'),
                  ),
                ],
                const Spacer(flex: 1),
                if (!_isQuick)
                  Text(
                    _phaseLabel(_progress.phase),
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _phaseLabel(ModelSetupPhase phase) {
    return switch (phase) {
      ModelSetupPhase.checking => 'CHECKPOINT · INIT',
      ModelSetupPhase.downloading => 'CHECKPOINT · DOWNLOAD',
      ModelSetupPhase.loading => 'CHECKPOINT · LOAD',
      ModelSetupPhase.ready => 'QUEST COMPLETE',
      ModelSetupPhase.failed => 'QUEST FAILED',
    };
  }

  Widget _buildHeroIcon() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = _isQuick
            ? 1.0 + _pulseController.value * 0.04
            : 1.0 + _pulseController.value * 0.08;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
        width: _isQuick ? 72 : 100,
        height: _isQuick ? 72 : 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              Colors.cyan.shade400,
              Colors.deepPurple.shade700,
            ],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.cyan.withValues(alpha: _isQuick ? 0.25 : 0.45),
              blurRadius: _isQuick ? 12 : 24,
              spreadRadius: _isQuick ? 0 : 2,
            ),
          ],
          border: Border.all(color: Colors.white24, width: _isQuick ? 2 : 3),
        ),
        child: Icon(
          _progress.phase == ModelSetupPhase.ready
              ? Icons.check_rounded
              : Icons.psychology_alt_outlined,
          size: _isQuick ? 36 : 52,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildXpBar() {
    final pct = (_progress.progress * 100).clamp(0, 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _isQuick ? 'STARTING' : 'LOADING',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Colors.amber.shade200,
              ),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade200,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth * _progress.progress;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  height: 22,
                  width: math.max(width, _progress.progress > 0 ? 8 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.green.shade600,
                        Colors.lightGreen.shade400,
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.lightGreen.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
