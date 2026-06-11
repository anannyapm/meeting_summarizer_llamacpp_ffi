import 'dart:async';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:ffi_learn/services/summarization_service.dart';

enum SummarizationStatus { idle, generating, done, error }

enum SummarizationPhase {
  idle,
  loadingModel,
  prefilling,
  streaming,
  done,
  error,
}

const Duration kFirstTokenTimeoutBase = Duration(seconds: 120);
const Duration kFirstTokenTimeoutMax = Duration(seconds: 420);
const Duration kTotalGenerationTimeout = Duration(seconds: 420);
const Duration kPostAbortGracePeriod = Duration(seconds: 5);

Duration firstTokenTimeoutForTranscript(int transcriptChars) {
  final estimatedPromptTokens = (transcriptChars / 2.5).round() + 20;
  final seconds = (estimatedPromptTokens * 2.5).clamp(
    kFirstTokenTimeoutBase.inSeconds.toDouble(),
    kFirstTokenTimeoutMax.inSeconds.toDouble(),
  ).round();
  return Duration(seconds: seconds);
}

class SummarizationProvider extends ChangeNotifier {
  SummarizationProvider(this._summarizationService);

  final SummarizationService _summarizationService;

  SummarizationStatus _status = SummarizationStatus.idle;
  SummarizationPhase _phase = SummarizationPhase.idle;
  String _summary = '';
  String? _errorMessage;
  bool _isLoadingModel = false;
  bool _isModelLoaded = false;
  String _modelInfo = 'Not loaded';
  bool _wasTranscriptTruncated = false;
  StreamSubscription<String>? _streamSubscription;
  Timer? _generationDeadlineTimer;
  Timer? _firstTokenDeadlineTimer;
  bool _firstTokenGraceActive = false;

  SummarizationStatus get status => _status;
  SummarizationPhase get phase => _phase;
  bool get isGenerating =>
      _phase == SummarizationPhase.loadingModel ||
      _phase == SummarizationPhase.prefilling ||
      _phase == SummarizationPhase.streaming;
  bool get isPrefilling => _phase == SummarizationPhase.prefilling;
  bool get isStreaming => _phase == SummarizationPhase.streaming;
  String get summary => _summary;
  String? get errorMessage => _errorMessage;
  bool get hasSummary => _summary.trim().isNotEmpty;
  bool get isLoadingModel => _isLoadingModel;
  bool get isModelLoaded => _isModelLoaded;
  String get modelInfo => _modelInfo;
  bool get wasTranscriptTruncated => _wasTranscriptTruncated;
  bool get isSlowModelForMobile =>
      !_summarizationService.isMobileRecommendedModel;
  int get maxTranscriptChars =>
      _summarizationService.effectiveMaxTranscriptChars;
  String? get currentModelPath => _summarizationService.modelPath;

  void _setPhase(SummarizationPhase phase) {
    _phase = phase;
    _status = switch (phase) {
      SummarizationPhase.idle => SummarizationStatus.idle,
      SummarizationPhase.loadingModel ||
      SummarizationPhase.prefilling ||
      SummarizationPhase.streaming =>
        SummarizationStatus.generating,
      SummarizationPhase.done => SummarizationStatus.done,
      SummarizationPhase.error => SummarizationStatus.error,
    };
  }

  Future<bool> loadModel() async {
    AppLogger.log('MODEL', 'Provider.loadModel invoked');
    _errorMessage = null;
    _isLoadingModel = true;
    notifyListeners();
    try {
      await _summarizationService.ensureModelLoaded();
      _isModelLoaded = true;
      _modelInfo = await _summarizationService.modelInfo();
      AppLogger.log('MODEL', 'Provider.loadModel success');
      return true;
    } catch (error) {
      _isModelLoaded = false;
      _errorMessage = error.toString();
      _modelInfo = 'Failed to load model';
      AppLogger.log('MODEL', 'Provider.loadModel failed: $error');
      return false;
    } finally {
      _isLoadingModel = false;
      notifyListeners();
    }
  }

  Future<void> unloadModel() async {
    AppLogger.log('MODEL', 'Provider.unloadModel invoked');
    _errorMessage = null;
    _isLoadingModel = true;
    notifyListeners();
    try {
      await _summarizationService.unloadModel();
      _isModelLoaded = false;
      _modelInfo = 'Not loaded';
      AppLogger.log('MODEL', 'Provider.unloadModel success');
    } catch (error) {
      _errorMessage = error.toString();
      AppLogger.log('MODEL', 'Provider.unloadModel failed: $error');
    } finally {
      _isLoadingModel = false;
      notifyListeners();
    }
  }

  Future<void> updateModelPath(String? modelPath) async {
    AppLogger.log('MODEL', 'Provider.updateModelPath path=$modelPath');
    _errorMessage = null;
    _isLoadingModel = true;
    notifyListeners();
    try {
      await _summarizationService.updateModelPath(modelPath);
      _isModelLoaded = false;
      _modelInfo = 'Not loaded';
      _summary = '';
      _setPhase(SummarizationPhase.idle);
    } catch (error) {
      _errorMessage = error.toString();
      AppLogger.log('MODEL', 'Provider.updateModelPath failed: $error');
    } finally {
      _isLoadingModel = false;
      notifyListeners();
    }
  }

  Future<void> summarize(String transcript) async {
    AppLogger.log(
      'SUMMARIZE',
      'Provider.summarize invoked transcriptChars=${transcript.length}',
    );
    await _streamSubscription?.cancel();
    _generationDeadlineTimer?.cancel();
    _firstTokenDeadlineTimer?.cancel();
    _firstTokenGraceActive = false;
    _summary = '';
    _errorMessage = null;
    _wasTranscriptTruncated = false;
    _setPhase(SummarizationPhase.prefilling);
    notifyListeners();

    try {
      if (!_isModelLoaded) {
        _setPhase(SummarizationPhase.loadingModel);
        notifyListeners();
        await loadModel();
        if (!_isModelLoaded) {
          _setPhase(SummarizationPhase.error);
          notifyListeners();
          return;
        }
        _setPhase(SummarizationPhase.prefilling);
        notifyListeners();
      }
      _summarizationService.prepareInput(transcript);
      _wasTranscriptTruncated = _summarizationService.lastInputWasTruncated;
      notifyListeners();
      final firstTokenTimeout = firstTokenTimeoutForTranscript(transcript.length);
      AppLogger.log(
        'SUMMARIZE',
        'First-token timeout=${firstTokenTimeout.inSeconds}s '
        'slowModel=$isSlowModelForMobile',
      );
      final stream = _summarizationService.summarize(transcript);
      final streamWatch = Stopwatch()..start();
      var tokenCount = 0;
      var firstTokenLogged = false;
      _streamSubscription = stream.listen(
        (token) {
          tokenCount += 1;
          if (!firstTokenLogged) {
            firstTokenLogged = true;
            _firstTokenDeadlineTimer?.cancel();
            _firstTokenGraceActive = false;
            _setPhase(SummarizationPhase.streaming);
            AppLogger.log(
              'SUMMARIZE',
              'First token in ${streamWatch.elapsedMilliseconds} ms',
            );
          }
          if (tokenCount % 20 == 0) {
            AppLogger.log(
              'SUMMARIZE',
              'Streaming progress tokenCount=$tokenCount summaryChars=${_summary.length}',
            );
          }
          _summary += token;
          notifyListeners();
        },
        onError: (Object error) {
          if (_firstTokenGraceActive && _summary.trim().isNotEmpty) {
            _setPhase(SummarizationPhase.done);
            AppLogger.log(
              'SUMMARIZE',
              'Stream error after partial output — accepting summary: $error',
            );
            notifyListeners();
            return;
          }
          _setPhase(SummarizationPhase.error);
          _errorMessage = error.toString();
          AppLogger.log('SUMMARIZE', 'Stream error: $error');
          notifyListeners();
        },
        onDone: () {
          _generationDeadlineTimer?.cancel();
          _firstTokenDeadlineTimer?.cancel();
          _firstTokenGraceActive = false;
          _streamSubscription = null;
          if (_phase != SummarizationPhase.error) {
            _setPhase(SummarizationPhase.done);
            AppLogger.log(
              'SUMMARIZE',
              'Stream done tokens=$tokenCount totalMs=${streamWatch.elapsedMilliseconds} summaryChars=${_summary.length}',
            );
            notifyListeners();
          }
        },
        cancelOnError: true,
      );

      _firstTokenDeadlineTimer = Timer(firstTokenTimeout, () {
        if (firstTokenLogged || _phase != SummarizationPhase.prefilling) {
          return;
        }
        unawaited(_handleFirstTokenGrace(firstTokenTimeout));
      });

      _generationDeadlineTimer = Timer(kTotalGenerationTimeout, () async {
        _firstTokenDeadlineTimer?.cancel();
        if (isGenerating) {
          AppLogger.log(
            'SUMMARIZE',
            'Total deadline reached (${kTotalGenerationTimeout.inSeconds}s), aborting...',
          );
          await _resetGeneration('total timeout');
          if (_summary.trim().isNotEmpty) {
            _setPhase(SummarizationPhase.done);
            _errorMessage =
                'Generation stopped after ${kTotalGenerationTimeout.inSeconds} s. Showing partial summary.';
          } else {
            _setPhase(SummarizationPhase.error);
            _errorMessage =
                'Summarization exceeded ${kTotalGenerationTimeout.inSeconds} s without output. Try a shorter transcript.';
          }
          AppLogger.log(
            'SUMMARIZE',
            'Provider deadline reached phase=$_phase summaryChars=${_summary.length}',
          );
          notifyListeners();
        }
      });
    } catch (error) {
      _setPhase(SummarizationPhase.error);
      _errorMessage = error.toString();
      AppLogger.log(
        'SUMMARIZE',
        'Provider.summarize failed before stream: $error',
      );
      notifyListeners();
    }
  }

  Future<void> _handleFirstTokenGrace(Duration firstTokenTimeout) async {
    if (_phase != SummarizationPhase.prefilling) {
      return;
    }
    _firstTokenGraceActive = true;
    AppLogger.log(
      'SUMMARIZE',
      'First-token deadline (${firstTokenTimeout.inSeconds}s) — '
      'waiting ${kPostAbortGracePeriod.inSeconds}s for late tokens',
    );
    await Future<void>.delayed(kPostAbortGracePeriod);

    if (_phase != SummarizationPhase.prefilling) {
      _firstTokenGraceActive = false;
      return;
    }
    if (_summary.trim().isNotEmpty) {
      _firstTokenGraceActive = false;
      _setPhase(SummarizationPhase.streaming);
      AppLogger.log('SUMMARIZE', 'Late first token accepted during grace period');
      notifyListeners();
      return;
    }

    AppLogger.log('SUMMARIZE', 'Grace expired — aborting stream');
    try {
      await _summarizationService.abortStream();
    } catch (_) {}

    await Future<void>.delayed(kPostAbortGracePeriod);
    _firstTokenGraceActive = false;

    if (_summary.trim().isNotEmpty) {
      _setPhase(
        _streamSubscription != null
            ? SummarizationPhase.streaming
            : SummarizationPhase.done,
      );
      AppLogger.log('SUMMARIZE', 'Partial summary accepted after abort grace');
      notifyListeners();
      return;
    }

    if (_phase != SummarizationPhase.prefilling) {
      return;
    }

    _setPhase(SummarizationPhase.error);
    _errorMessage = isSlowModelForMobile
        ? 'No output in ${firstTokenTimeout.inSeconds} s. '
            'Switch to Llama 3.2 1B or SmolLM2 360M in Settings for faster CPU summarization.'
        : 'No output in ${firstTokenTimeout.inSeconds} s — model too slow or stuck. '
            'Try a shorter transcript.';
    notifyListeners();
    await _resetGeneration('first-token timeout');
  }

  Future<void> _resetGeneration(String reason) async {
    AppLogger.log('SUMMARIZE', 'Resetting generation ($reason)');
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    try {
      await _summarizationService.recoverFromStuckGeneration();
      _isModelLoaded = false;
      _modelInfo = 'Not loaded';
    } catch (_) {
      // Ignore recovery errors.
    }
  }

  void clear() {
    _generationDeadlineTimer?.cancel();
    _firstTokenDeadlineTimer?.cancel();
    _firstTokenGraceActive = false;
    _summary = '';
    _errorMessage = null;
    _wasTranscriptTruncated = false;
    _setPhase(SummarizationPhase.idle);
    notifyListeners();
  }

  Future<void> cancelGeneration() async {
    if (!isGenerating) {
      return;
    }
    AppLogger.log('SUMMARIZE', 'User requested cancel generation');
    _generationDeadlineTimer?.cancel();
    _firstTokenDeadlineTimer?.cancel();
    _firstTokenGraceActive = false;
    _setPhase(SummarizationPhase.idle);
    _errorMessage = null;
    notifyListeners();
    unawaited(_summarizationService.abortStream());
    unawaited(_streamSubscription?.cancel());
  }

  @override
  void dispose() {
    _generationDeadlineTimer?.cancel();
    _firstTokenDeadlineTimer?.cancel();
    unawaited(_streamSubscription?.cancel());
    unawaited(_summarizationService.dispose());
    super.dispose();
  }
}
