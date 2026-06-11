import 'dart:async';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/models/model_presets.dart';
import 'package:ffi_learn/native/native_bridge_worker.dart';

class SummarizationServiceException implements Exception {
  const SummarizationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SummarizationResult {
  const SummarizationResult({
    required this.summary,
    this.wasChunked = false,
    this.wasTruncated = false,
  });

  final String summary;
  final bool wasChunked;
  final bool wasTruncated;
}

class SummarizationService {
  SummarizationService({
    required String? modelPath,
    this.nCtx = 256,
    this.nGpuLayers = 0,
    this.maxOutputTokens = 16,
  }) : _modelPath = modelPath;

  String? _modelPath;
  final int nCtx;
  final int nGpuLayers;
  final int maxOutputTokens;

  /// Per-pass transcript cap for map-reduce on very long meetings.
  static const int summarizeChunkChars = 500;

  /// Mobile CPU budget — last N chars (matches original fast path).
  static const int summarizeMaxTranscriptChars = 250;

  int? _loadedNCtx;
  bool _lastInputWasTruncated = false;

  /// Whether the most recent summarize call trimmed the transcript for CPU budget.
  bool get lastInputWasTruncated => _lastInputWasTruncated;

  /// Minimal prompt — fewer tokens than chat templates.
  String _buildSummaryPrompt(String content) {
    return 'Summarize in one sentence:\n$content';
  }

  bool get isMobileRecommendedModel =>
      AppModelPresets.isMobileRecommendedPath(_modelPath);

  ({String text, bool wasTruncated}) _prepareTranscript(String transcript) {
    final cleaned = _sanitizeTranscript(transcript.trim());
    if (cleaned.length <= summarizeMaxTranscriptChars) {
      _lastInputWasTruncated = false;
      return (text: cleaned, wasTruncated: false);
    }
    final tail = cleaned.substring(cleaned.length - summarizeMaxTranscriptChars);
    final trimmed = tail.trimLeft();
    _lastInputWasTruncated = true;
    AppLogger.log(
      'SUMMARIZE',
      'Transcript truncated for CPU budget '
      'from=${cleaned.length} to=${trimmed.length} chars',
    );
    return (text: trimmed, wasTruncated: true);
  }

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
        'Model path is unavailable. Download a model in Settings first.',
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

  int? _parseRuntimeNCtx(String info) {
    final match = RegExp(r'n_ctx_runtime=(\d+)').firstMatch(info);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  Future<void> _loadModelNative() async {
    await _worker!.loadModel(
      modelPath: _modelPath!,
      nCtx: nCtx,
      nGpuLayers: nGpuLayers,
    );
  }

  Future<void> _loadModelWithRetry() async {
    try {
      await _loadModelNative();
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('model_already_loaded')) {
        AppLogger.log('MODEL', 'Model already loaded in worker — unloading and retrying');
        await _worker!.unloadModel();
        await _loadModelNative();
        return;
      }
      rethrow;
    }
  }

  Future<void> ensureModelLoaded() async {
    await _ensureSessionReady();

    if (_modelLoaded) {
      try {
        final info = await _worker!.modelInfo();
        final runtimeNCtx = _parseRuntimeNCtx(info);
        AppLogger.log('MODEL', 'Runtime info: $info');
        if (runtimeNCtx != null && runtimeNCtx != nCtx) {
          AppLogger.log(
            'MODEL',
            'Runtime n_ctx=$runtimeNCtx != configured $nCtx — reloading',
          );
          await unloadModel();
        }
      } catch (error) {
        AppLogger.log('MODEL', 'modelInfo failed ($error) — reloading model');
        await unloadModel();
      }
    }

    if (!_modelLoaded) {
      final watch = Stopwatch()..start();
      AppLogger.log(
        'MODEL',
        'Loading model from path=$_modelPath nCtx=$nCtx nGpuLayers=$nGpuLayers',
      );
      await _loadModelWithRetry();
      _modelLoaded = true;
      _loadedNCtx = nCtx;
      AppLogger.log('MODEL', 'Model loaded in ${watch.elapsedMilliseconds} ms');
    } else {
      AppLogger.log(
        'MODEL',
        'Model ready (configured nCtx=$nCtx, tracked=$_loadedNCtx)',
      );
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
    _loadedNCtx = null;
    AppLogger.log('MODEL', 'Model unloaded.');
  }

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

  /// Kills the worker isolate when native generation is blocked and cannot
  /// process abort/unload commands on the command port.
  Future<void> recoverFromStuckGeneration() async {
    AppLogger.log('SUMMARIZE', 'Recovering from stuck generation (kill worker)');
    try {
      await abortStream();
    } catch (_) {
      // Best effort — worker may not be listening.
    }
    final worker = _worker;
    _worker = null;
    _sessionReady = false;
    _modelLoaded = false;
    _loadedNCtx = null;
    if (worker != null) {
      await worker.close();
    }
  }

  Future<String> modelInfo() async {
    await ensureModelLoaded();
    AppLogger.log('MODEL', 'Fetching model info...');
    return _worker!.modelInfo();
  }

  String _sanitizeTranscript(String transcript) {
    return transcript
        .replaceAll(r'\$', '')
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '');
  }

  List<String> _chunkTranscript(String transcript) {
    final maxChars = summarizeChunkChars;
    if (transcript.length <= maxChars) {
      return <String>[transcript];
    }

    final chunks = <String>[];
    var start = 0;
    while (start < transcript.length) {
      var end = (start + maxChars).clamp(0, transcript.length);
      if (end < transcript.length) {
        final lastSpace = transcript.lastIndexOf(' ', end);
        if (lastSpace > start) {
          end = lastSpace;
        }
      }
      chunks.add(transcript.substring(start, end).trim());
      start = end;
    }
    return chunks.where((chunk) => chunk.isNotEmpty).toList();
  }

  Future<String> _generateSummary(String transcriptSlice) async {
    final buffer = StringBuffer();
    await for (final token in _worker!.streamEcho(
      _buildSummaryPrompt(transcriptSlice),
      maxTokens: maxOutputTokens,
    )) {
      buffer.write(token);
    }
    return buffer.toString().trim();
  }

  Future<SummarizationResult> summarizeToResult(String transcript) async {
    final prepared = _prepareTranscript(transcript);
    final cleaned = prepared.text;
    if (cleaned.isEmpty) {
      throw const SummarizationServiceException(
        'Transcript is empty. Record and transcribe first.',
      );
    }

    await ensureModelLoaded();

    final chunks = _chunkTranscript(cleaned);
    final wasChunked = chunks.length > 1;

    AppLogger.log(
      'SUMMARIZE',
      'Requested summary. transcriptChars=${cleaned.length} '
      'chunks=${chunks.length} chunkCap=$summarizeChunkChars nCtx=$nCtx',
    );

    if (!wasChunked) {
      final summary = await _generateSummary(chunks.first);
      return SummarizationResult(
        summary: summary,
        wasChunked: false,
        wasTruncated: prepared.wasTruncated,
      );
    }

    final partialSummaries = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      AppLogger.log('SUMMARIZE', 'Summarizing chunk ${i + 1}/${chunks.length}');
      final partial = await _generateSummary(chunks[i]);
      if (partial.isNotEmpty) {
        partialSummaries.add(partial);
      }
    }

    if (partialSummaries.isEmpty) {
      throw const SummarizationServiceException(
        'Failed to summarize any transcript chunks.',
      );
    }

    if (partialSummaries.length == 1) {
      return SummarizationResult(
        summary: partialSummaries.first,
        wasChunked: true,
        wasTruncated: prepared.wasTruncated,
      );
    }

    final combined = partialSummaries
        .asMap()
        .entries
        .map((e) => 'Part ${e.key + 1}: ${e.value}')
        .join('\n\n');

    final finalSummary = await _generateSummary(
      'Combine these partial summaries into one:\n\n$combined',
    );

    return SummarizationResult(
      summary: finalSummary,
      wasChunked: true,
      wasTruncated: prepared.wasTruncated,
    );
  }

  /// Synchronous prep so callers can read [lastInputWasTruncated] before streaming.
  String prepareInput(String transcript) {
    return _prepareTranscript(transcript).text;
  }

  Stream<String> summarize(String transcript) async* {
    final cleaned = prepareInput(transcript);
    if (cleaned.isEmpty) {
      throw const SummarizationServiceException(
        'Transcript is empty. Record and transcribe first.',
      );
    }

    await ensureModelLoaded();

    final chunks = _chunkTranscript(cleaned);
    AppLogger.log(
      'SUMMARIZE',
      'Streaming summary. transcriptChars=${cleaned.length} '
      'chunks=${chunks.length} chunkCap=$summarizeChunkChars nCtx=$nCtx',
    );

    if (chunks.length == 1) {
      yield* _worker!.streamEcho(
        _buildSummaryPrompt(chunks.first),
        maxTokens: maxOutputTokens,
      );
      return;
    }

    final partialSummaries = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final partial = await _generateSummary(chunks[i]);
      if (partial.isNotEmpty) {
        partialSummaries.add(partial);
      }
    }

    if (partialSummaries.isEmpty) {
      throw const SummarizationServiceException(
        'Failed to summarize any transcript chunks.',
      );
    }

    if (partialSummaries.length == 1) {
      yield partialSummaries.first;
      return;
    }

    final combined = partialSummaries
        .asMap()
        .entries
        .map((e) => 'Part ${e.key + 1}: ${e.value}')
        .join('\n\n');

    yield* _worker!.streamEcho(
      _buildSummaryPrompt(
        'Combine these partial summaries into one:\n\n$combined',
      ),
      maxTokens: maxOutputTokens,
    );
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
    _loadedNCtx = null;
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
