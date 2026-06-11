import 'dart:async';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:ffi_learn/services/summarization_service.dart';

enum SummarizationStatus { idle, generating, done, error }

// Base timeout; extended automatically for large on-device models.
const Duration kFirstTokenTimeoutBase = Duration(seconds: 120);
const Duration kFirstTokenTimeoutMax = Duration(seconds: 420);
const Duration kTotalGenerationTimeout = Duration(seconds: 420);

/// Rough prefill budget: ~2.5 s per estimated prompt token on 1B-class CPU.
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
  String _summary = '';
  String? _errorMessage;
  bool _isLoadingModel = false;
  bool _isModelLoaded = false;
  String _modelInfo = 'Not loaded';
  bool _wasTranscriptTruncated = false;
  StreamSubscription<String>? _streamSubscription;
  Timer? _generationDeadlineTimer;
  Timer? _firstTokenDeadlineTimer;

  SummarizationStatus get status => _status;
  bool get isGenerating => _status == SummarizationStatus.generating;
  String get summary => _summary;
  String? get errorMessage => _errorMessage;
  bool get hasSummary => _summary.trim().isNotEmpty;
  bool get isLoadingModel => _isLoadingModel;
  bool get isModelLoaded => _isModelLoaded;
  String get modelInfo => _modelInfo;
  bool get wasTranscriptTruncated => _wasTranscriptTruncated;
  bool get isSlowModelForMobile =>
      !_summarizationService.isMobileRecommendedModel;
  String? get currentModelPath => _summarizationService.modelPath;

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
      _status = SummarizationStatus.idle;
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
    _summary = '';
    _errorMessage = null;
    _wasTranscriptTruncated = false;
    _status = SummarizationStatus.generating;
    notifyListeners();

    try {
      if (!_isModelLoaded) {
        await loadModel();
        if (!_isModelLoaded) {
          _status = SummarizationStatus.error;
          notifyListeners();
          return;
        }
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
          debugPrint('[SUMMARIZE] TOKEN RECEIVED="$token"');
          _summary += token;
          notifyListeners();
        },
        onError: (Object error) {
          _status = SummarizationStatus.error;
          _errorMessage = error.toString();
          AppLogger.log('SUMMARIZE', 'Stream error: $error');
          notifyListeners();
        },
        onDone: () {
          _generationDeadlineTimer?.cancel();
          _firstTokenDeadlineTimer?.cancel();
          _streamSubscription = null;
          if (_status != SummarizationStatus.error) {
            _status = SummarizationStatus.done;
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
        if (firstTokenLogged || _status != SummarizationStatus.generating) {
          return;
        }
        AppLogger.log(
          'SUMMARIZE',
          'First-token deadline reached (${firstTokenTimeout.inSeconds}s), aborting...',
        );
        _status = SummarizationStatus.error;
        _errorMessage = isSlowModelForMobile
            ? 'No output in ${firstTokenTimeout.inSeconds} s. '
                'Switch to Llama 3.2 1B or TinyLlama in Settings for faster CPU summarization.'
            : 'No output in ${firstTokenTimeout.inSeconds} s — model too slow or stuck. '
                'Try a shorter transcript.';
        notifyListeners();
        unawaited(_resetGeneration('first-token timeout'));
      });

      _generationDeadlineTimer = Timer(kTotalGenerationTimeout, () async {
        _firstTokenDeadlineTimer?.cancel();
        if (_status == SummarizationStatus.generating) {
          AppLogger.log(
            'SUMMARIZE',
            'Total deadline reached (${kTotalGenerationTimeout.inSeconds}s), aborting...',
          );
          await _resetGeneration('total timeout');
          if (_summary.trim().isNotEmpty) {
            _status = SummarizationStatus.done;
            _errorMessage =
                'Generation stopped after ${kTotalGenerationTimeout.inSeconds} s. Showing partial summary.';
          } else {
            _status = SummarizationStatus.error;
            _errorMessage =
                'Summarization exceeded ${kTotalGenerationTimeout.inSeconds} s without output. Try a shorter transcript.';
          }
          AppLogger.log(
            'SUMMARIZE',
            'Provider deadline reached status=$_status summaryChars=${_summary.length}',
          );
          notifyListeners();
        }
      });
    } catch (error) {
      _status = SummarizationStatus.error;
      _errorMessage = error.toString();
      AppLogger.log(
        'SUMMARIZE',
        'Provider.summarize failed before stream: $error',
      );
      notifyListeners();
    }
  }

  Future<void> _resetGeneration(String reason) async {
    AppLogger.log('SUMMARIZE', 'Resetting generation ($reason)');
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    // Native decode blocks the worker isolate; abort/unload commands queue until
    // it returns. Kill the worker so the next summarize starts fresh.
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
    _summary = '';
    _errorMessage = null;
    _wasTranscriptTruncated = false;
    _status = SummarizationStatus.idle;
    notifyListeners();
  }

  /// Aborts an in-progress generation immediately and transitions to idle.
  Future<void> cancelGeneration() async {
    if (_status != SummarizationStatus.generating) {
      return;
    }
    AppLogger.log('SUMMARIZE', 'User requested cancel generation');
    _generationDeadlineTimer?.cancel();
    _firstTokenDeadlineTimer?.cancel();
    _status = SummarizationStatus.idle;
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
