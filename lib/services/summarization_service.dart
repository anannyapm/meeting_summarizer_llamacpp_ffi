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
  SummarizationService({required String? modelPath}) : _modelPath = modelPath;

  String? _modelPath;

  /// Per-pass transcript cap for map-reduce on very long meetings.
  static const int summarizeChunkChars = 600;

  int? _loadedNCtx;
  String? _loadedPresetId;
  bool _lastInputWasTruncated = false;

  bool get lastInputWasTruncated => _lastInputWasTruncated;

  AppModelPreset get _activePreset =>
      AppModelPresets.findByFilePath(_modelPath) ??
      AppModelPresets.resolveById(AppModelPresets.defaultModelId);

  int get _effectiveNCtx => _activePreset.mobileNCtx;
  int get _effectiveMaxOutput => _activePreset.mobileMaxOutputTokens;
  int get _effectiveMaxTranscriptChars => _activePreset.mobileMaxTranscriptChars;
  int get _effectiveGpuLayers => _activePreset.mobileGpuLayers;

  int get effectiveMaxTranscriptChars => _effectiveMaxTranscriptChars;

  bool get isMobileRecommendedModel => _activePreset.recommendedForMobile;

  String _buildEchoPrompt(
    String transcriptSlice, {
    String systemPrompt = AppModelPreset.systemPrompt,
  }) {
    return '''$systemPrompt

Transcript:
$transcriptSlice

Summary:''';
  }

  /// Chat-template user turn: transcript only (instructions live in system).
  String _userPromptForSlice(String transcriptSlice) => transcriptSlice;

  String _userPromptForCombine(String partialSummaries) => partialSummaries;

  ({String text, bool wasTruncated}) _prepareTranscript(String transcript) {
    final cleaned = transcript.trim();
    final maxChars = _effectiveMaxTranscriptChars;
    if (cleaned.length <= maxChars) {
      _lastInputWasTruncated = false;
      return (text: cleaned, wasTruncated: false);
    }
    // Opening + recent context beats tail-only (reduces "continue the text" behavior).
    const headChars = 140;
    final tailBudget = maxChars - headChars - 5;
    final head = cleaned.substring(0, headChars).trimRight();
    final tail = cleaned.substring(cleaned.length - tailBudget).trimLeft();
    final trimmed = '$head ... $tail';
    _lastInputWasTruncated = true;
    AppLogger.log(
      'SUMMARIZE',
      'Transcript truncated for CPU budget '
      'from=${cleaned.length} to=${trimmed.length} chars (head+tail)',
    );
    return (text: trimmed, wasTruncated: true);
  }

  static const String _chatMlImEnd = '\x3C|im_end|>';

  String _cleanSummary(String raw) {
    var summary = raw.trim();
    const templateLeaks = <String>[
      '<|im_start|>',
      _chatMlImEnd,
      '<|endoftext|>',
      '<|eot_id|>',
      '[/INST]',
      '</s>',
      '<s>',
    ];
    for (final leak in templateLeaks) {
      summary = summary.replaceAll(leak, '');
    }
    summary = summary.replaceFirst(RegExp(r'^(assistant|user)\s*:\s*', caseSensitive: false), '');
    summary = summary.replaceFirst(RegExp(r'^(summary|transcript)\s*:\s*', caseSensitive: false), '');
    for (final prefix in _instructionEchoPrefixes) {
      if (summary.toLowerCase().startsWith(prefix)) {
        summary = summary.substring(prefix.length).trimLeft();
      }
    }
    return summary.trim();
  }

  static const List<String> _instructionEchoPrefixes = <String>[
    'summarize this meeting transcript',
    'write 2 to 4 sentences',
    'write 2-4 sentences',
    'about the main points',
    'merge these partial summaries',
  ];

  bool _looksLikeBadSummary(String summary, String source) {
    final trimmed = summary.trim();
    if (trimmed.length < 12) {
      return true;
    }
    final lower = trimmed.toLowerCase();
    for (final phrase in _instructionEchoPrefixes) {
      if (lower.contains(phrase)) {
        return true;
      }
    }
    if (lower.startsWith('summarize ') || lower.startsWith('write ')) {
      return true;
    }
    final normSummary = lower.replaceAll(RegExp(r'\s+'), ' ');
    final normSource = source.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normSummary.length >= 20 && normSource.contains(normSummary)) {
      return true;
    }
    final probeLen = normSummary.length < 48 ? normSummary.length : 48;
    return normSource.contains(normSummary.substring(0, probeLen));
  }

  NativeBridgeWorkerClient? _worker;
  bool _sessionReady = false;
  bool _modelLoaded = false;
  bool get isModelLoaded => _modelLoaded;
  String? get modelPath => _modelPath;
  String get activePresetId => _activePreset.id;

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

  bool _needsReload() {
    if (!_modelLoaded) {
      return true;
    }
    if (_loadedPresetId != _activePreset.id) {
      return true;
    }
    if (_loadedNCtx != _effectiveNCtx) {
      return true;
    }
    return false;
  }

  Future<void> _loadModelNative() async {
    await _worker!.loadModel(
      modelPath: _modelPath!,
      nCtx: _effectiveNCtx,
      nGpuLayers: _effectiveGpuLayers,
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
        if (runtimeNCtx != null && runtimeNCtx != _effectiveNCtx) {
          AppLogger.log(
            'MODEL',
            'Runtime n_ctx=$runtimeNCtx != configured $_effectiveNCtx — reloading',
          );
          await unloadModel();
        } else if (_loadedPresetId != _activePreset.id) {
          AppLogger.log(
            'MODEL',
            'Preset changed ($_loadedPresetId -> ${_activePreset.id}) — reloading',
          );
          await unloadModel();
        }
      } catch (error) {
        AppLogger.log('MODEL', 'modelInfo failed ($error) — reloading model');
        await unloadModel();
      }
    }

    if (_needsReload()) {
      final watch = Stopwatch()..start();
      final preset = _activePreset;
      AppLogger.log(
        'MODEL',
        'Loading preset=${preset.id} path=$_modelPath '
        'nCtx=${preset.mobileNCtx} maxOut=${preset.mobileMaxOutputTokens} '
        'gpuLayers=${preset.mobileGpuLayers} promptMode=${preset.promptMode}',
      );
      await _loadModelWithRetry();
      _modelLoaded = true;
      _loadedNCtx = _effectiveNCtx;
      _loadedPresetId = preset.id;
      AppLogger.log('MODEL', 'Model loaded in ${watch.elapsedMilliseconds} ms');
    } else {
      AppLogger.log(
        'MODEL',
        'Model ready preset=$_loadedPresetId nCtx=$_loadedNCtx',
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
    _loadedPresetId = null;
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

  Future<void> recoverFromStuckGeneration() async {
    AppLogger.log('SUMMARIZE', 'Recovering from stuck generation (kill worker)');
    try {
      await abortStream();
    } catch (_) {}
    final worker = _worker;
    _worker = null;
    _sessionReady = false;
    _modelLoaded = false;
    _loadedNCtx = null;
    _loadedPresetId = null;
    if (worker != null) {
      await worker.close();
    }
  }

  Future<String> modelInfo() async {
    await ensureModelLoaded();
    AppLogger.log('MODEL', 'Fetching model info...');
    return _worker!.modelInfo();
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

  Stream<String> _streamSummary(
    String userPrompt, {
    String systemPrompt = AppModelPreset.systemPrompt,
  }) {
    final preset = _activePreset;
    final maxTokens = _effectiveMaxOutput;
    if (preset.promptMode == ModelPromptMode.nativeChatTemplate) {
      return _worker!.streamChat(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxTokens: maxTokens,
      );
    }
    return _worker!.streamEcho(
      _buildEchoPrompt(userPrompt, systemPrompt: systemPrompt),
      maxTokens: maxTokens,
    );
  }

  Future<String> _generateSummary(
    String transcriptSlice, {
    String systemPrompt = AppModelPreset.systemPrompt,
    bool isCombinePass = false,
  }) async {
    final userPrompt = isCombinePass
        ? _userPromptForCombine(transcriptSlice)
        : _userPromptForSlice(transcriptSlice);
    final buffer = StringBuffer();
    await for (final token in _streamSummary(userPrompt, systemPrompt: systemPrompt)) {
      buffer.write(token);
    }
    var summary = _cleanSummary(buffer.toString());
    if (_looksLikeBadSummary(summary, transcriptSlice)) {
      AppLogger.log('SUMMARIZE', 'Bad summary (echo/instruction) — retrying');
      final retrySystem = isCombinePass
          ? '${AppModelPreset.combineSystemPrompt} Start directly with the summary.'
          : 'Reply with only the summary sentences. Do not repeat any instructions.';
      final retryBuffer = StringBuffer();
      await for (final token in _streamSummary(
        transcriptSlice,
        systemPrompt: retrySystem,
      )) {
        retryBuffer.write(token);
      }
      summary = _cleanSummary(retryBuffer.toString());
    }
    return summary;
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
      'Requested summary. preset=${_activePreset.id} transcriptChars=${cleaned.length} '
      'chunks=${chunks.length} nCtx=$_effectiveNCtx',
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
      combined,
      systemPrompt: AppModelPreset.combineSystemPrompt,
      isCombinePass: true,
    );

    return SummarizationResult(
      summary: finalSummary,
      wasChunked: true,
      wasTruncated: prepared.wasTruncated,
    );
  }

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
      'Streaming summary. preset=${_activePreset.id} transcriptChars=${cleaned.length} '
      'chunks=${chunks.length} nCtx=$_effectiveNCtx',
    );

    if (chunks.length == 1) {
      final summary = await _generateSummary(chunks.first);
      if (summary.isNotEmpty) {
        yield summary;
      }
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

    final finalSummary = await _generateSummary(
      combined,
      systemPrompt: AppModelPreset.combineSystemPrompt,
      isCombinePass: true,
    );
    if (finalSummary.isNotEmpty) {
      yield finalSummary;
    }
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
    _loadedPresetId = null;
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
