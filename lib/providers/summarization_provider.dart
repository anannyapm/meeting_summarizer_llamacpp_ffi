import 'dart:async';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:ffi_learn/services/summarization_service.dart';

enum SummarizationStatus { idle, generating, done, error }

class SummarizationProvider extends ChangeNotifier {
  SummarizationProvider(this._summarizationService);

  final SummarizationService _summarizationService;

  SummarizationStatus _status = SummarizationStatus.idle;
  String _summary = '';
  String? _errorMessage;
  bool _isLoadingModel = false;
  bool _isModelLoaded = false;
  String _modelInfo = 'Not loaded';
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

      _firstTokenDeadlineTimer = Timer(const Duration(seconds: 1000), () {
        if (firstTokenLogged || _status != SummarizationStatus.generating) {
          return;
        }
        AppLogger.log(
          'SUMMARIZE',
          'First-token deadline reached (1000s), aborting native stream...',
        );
        _status = SummarizationStatus.error;
        _errorMessage =
            'No output in 1000 s — model too slow or stuck. Try a shorter transcript.';
        notifyListeners();
        // Signal the native generation loop to stop; this unblocks the worker.
        unawaited(_summarizationService.abortStream());
        unawaited(_streamSubscription?.cancel());
      });

      // Hard stop to avoid indefinite loading on slower devices.
      _generationDeadlineTimer = Timer(const Duration(seconds: 300), () async {
        _firstTokenDeadlineTimer?.cancel();
        if (_status == SummarizationStatus.generating) {
          AppLogger.log('SUMMARIZE', 'Hard 300s deadline reached, aborting...');
          unawaited(_summarizationService.abortStream());
          await _streamSubscription?.cancel();
          if (_summary.trim().isNotEmpty) {
            _status = SummarizationStatus.done;
            _errorMessage =
                'Generation stopped after 60 s. Showing partial summary.';
          } else {
            _status = SummarizationStatus.error;
            _errorMessage =
                'Summarization exceeded 60 s without output. Try a shorter transcript.';
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

  void clear() {
    _generationDeadlineTimer?.cancel();
    _firstTokenDeadlineTimer?.cancel();
    _summary = '';
    _errorMessage = null;
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
