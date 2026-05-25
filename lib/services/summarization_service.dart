import 'dart:async';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/native/native_bridge_worker.dart';

class SummarizationServiceException implements Exception {
  const SummarizationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SummarizationService {
  SummarizationService({
    required String? modelPath,
    this.nCtx = 256,
    this.nGpuLayers = 999,
  }) : _modelPath = modelPath;

  String? _modelPath;
  final int nCtx;
  final int nGpuLayers;

  NativeBridgeWorkerClient? _worker;
  bool _sessionReady = false;
  bool _modelLoaded = false;
  bool get isModelLoaded => _modelLoaded;
  String? get modelPath => _modelPath;

  Future<void> _ensureSessionReady() async {
    if (_sessionReady && _worker != null) {
      return;
    }
    if (_modelPath == null || _modelPath!.isEmpty) {
      throw const SummarizationServiceException(
        'Model path is unavailable. Restart app after model download completes.',
      );
    }

    final sessionWatch = Stopwatch()..start();
    AppLogger.log('MODEL', 'Ensuring worker/session ready...');
    _worker ??= await NativeBridgeWorkerClient.start();
    if (!_sessionReady) {
      AppLogger.log('MODEL', 'Creating native session...');
      await _worker!.createSession(tag: 'meeting_summarizer');
      _sessionReady = true;
      AppLogger.log(
        'MODEL',
        'Session ready in ${sessionWatch.elapsedMilliseconds} ms',
      );
    }
  }

  Future<void> ensureModelLoaded() async {
    await _ensureSessionReady();
    if (!_modelLoaded) {
      final watch = Stopwatch()..start();
      AppLogger.log(
        'MODEL',
        'Loading model from path=$_modelPath nCtx=$nCtx nGpuLayers=$nGpuLayers',
      );
      await _worker!.loadModel(
        modelPath: _modelPath!,
        nCtx: nCtx,
        nGpuLayers: nGpuLayers,
      );
      _modelLoaded = true;
      AppLogger.log('MODEL', 'Model loaded in ${watch.elapsedMilliseconds} ms');
    } else {
      AppLogger.log('MODEL', 'Model already loaded, skipping load.');
    }
  }

  Future<void> unloadModel() async {
    await _ensureSessionReady();
    if (!_modelLoaded) {
      return;
    }
    AppLogger.log('MODEL', 'Unloading model...');
    await _worker!.unloadModel();
    _modelLoaded = false;
    AppLogger.log('MODEL', 'Model unloaded.');
  }

  /// Signals the native session to stop the current generation at the next
  /// decode boundary. The worker handles this as a fire-and-forget call so it
  /// returns quickly even while bridge_session_stream is blocked.
  Future<void> abortStream() async {
    if (_worker == null || !_sessionReady) {
      return;
    }
    AppLogger.log('SUMMARIZE', 'Sending abort signal to native session...');
    try {
      await _worker!.abortStream();
    } catch (_) {
      // Ignore — worker may already be shutting down.
    }
  }

  Future<String> modelInfo() async {
    await ensureModelLoaded();
    AppLogger.log('MODEL', 'Fetching model info...');
    return _worker!.modelInfo();
  }

  Stream<String> summarize(String transcript) async* {
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) {
      throw const SummarizationServiceException(
        'Transcript is empty. Record and transcribe first.',
      );
    }

    await ensureModelLoaded();

    // Keep prompt tight: prefill decode is the bottleneck on mobile CPU.
    // 500 chars ≈ 125 tokens; total prompt stays well under 200 tokens.
    const maxChars = 500;
    final boundedTranscript = cleaned.length > maxChars
        ? cleaned.substring(cleaned.length - maxChars)
        : cleaned;
    AppLogger.log(
      'SUMMARIZE',
      'Requested summary. transcriptChars=${cleaned.length}, boundedChars=${boundedTranscript.length}',
    );

    final prompt =
        '''
<|im_start|>system
You are a concise summarization assistant.
Return ONLY the summary.
<|im_end|>
<|im_start|>user
Summarize this conversation in one short sentence:

$boundedTranscript
<|im_end|>
<|im_start|>assistant
''';

    final streamStart = DateTime.now();
    AppLogger.log('SUMMARIZE', 'Starting native stream generation...');
    yield* _worker!.streamEcho(prompt);
  }

  Future<void> dispose() async {
    AppLogger.log('MODEL', 'Disposing summarization service...');
    final worker = _worker;
    if (worker != null) {
      await worker.close();
    }
    _worker = null;
    _sessionReady = false;
    _modelLoaded = false;
  }

  Future<void> updateModelPath(String? newPath) async {
    if (_modelPath == newPath) {
      AppLogger.log('MODEL', 'Model path unchanged, skipping update.');
      return;
    }
    AppLogger.log('MODEL', 'Updating model path from $_modelPath to $newPath');
    await dispose();
    _modelPath = newPath;
  }
}
