import 'dart:async';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/core/summarization_metrics.dart';
import 'package:ffi_learn/models/inference_profile.dart';
import 'package:ffi_learn/models/model_presets.dart';
import 'package:ffi_learn/native/native_bridge_worker.dart';
import 'package:ffi_learn/summarization/chunking_policy.dart';
import 'package:ffi_learn/summarization/summary_quality_gate.dart';

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
    this.metrics,
  });

  final String summary;
  final bool wasChunked;
  final bool wasTruncated;
  final SummarizationRunMetrics? metrics;
}

class SummarizationService {
  SummarizationService({required String? modelPath}) : _modelPath = modelPath;

  String? _modelPath;

  static const int summarizeChunkChars = 600;
  static const int chunkOverlapChars = 80;

  final ChunkingPolicy _chunking = const ChunkingPolicy(
    maxChunkChars: summarizeChunkChars,
    overlapChars: chunkOverlapChars,
  );

  int? _loadedNCtx;
  String? _loadedPresetId;
  bool _lastInputWasTruncated = false;
  SummarizationRunMetrics? _lastRunMetrics;

  bool get lastInputWasTruncated => _lastInputWasTruncated;
  SummarizationRunMetrics? get lastRunMetrics => _lastRunMetrics;

  AppModelPreset get _activePreset =>
      AppModelPresets.findByFilePath(_modelPath) ??
      AppModelPresets.resolveById(AppModelPresets.defaultModelId);

  InferenceProfile get _profile => InferenceProfile.fromPreset(_activePreset);

  int get effectiveMaxTranscriptChars => _profile.maxTranscriptChars;
  bool get isMobileRecommendedModel => _activePreset.recommendedForMobile;
  String? get modelPath => _modelPath;
  String get activePresetId => _activePreset.id;
  bool get isModelLoaded => _modelLoaded;

  String _buildEchoPrompt(
    String transcriptSlice, {
    String systemPrompt = AppModelPreset.systemPrompt,
  }) {
    return '''$systemPrompt

Transcript:
$transcriptSlice

Summary:''';
  }

  String _userPromptForSlice(String transcriptSlice) => transcriptSlice;
  String _userPromptForCombine(String partialSummaries) => partialSummaries;

  ({String text, bool wasTruncated}) _prepareTranscript(String transcript) {
    final cleaned = transcript.trim();
    final maxChars = _profile.maxTranscriptChars;
    if (cleaned.length <= maxChars) {
      _lastInputWasTruncated = false;
      return (text: cleaned, wasTruncated: false);
    }
    const headChars = 140;
    final tailBudget = maxChars - headChars - 5;
    final head = cleaned.substring(0, headChars).trimRight();
    final tail = cleaned.substring(cleaned.length - tailBudget).trimLeft();
    final trimmed = '$head ... $tail';
    _lastInputWasTruncated = true;
    AppLogger.log(
      'SUMMARIZE',
      'Transcript truncated from=${cleaned.length} to=${trimmed.length} (head+tail)',
    );
    return (text: trimmed, wasTruncated: true);
  }

  NativeBridgeWorkerClient? _worker;
  bool _sessionReady = false;
  bool _modelLoaded = false;

  Future<void> _ensureSessionReady() async {
    if (_sessionReady && _worker != null) {
      return;
    }
    if (_modelPath == null || _modelPath!.isEmpty) {
      throw const SummarizationServiceException(
        'Model path is unavailable. Download a model in Settings first.',
      );
    }
    _worker ??= await NativeBridgeWorkerClient.start();
    if (!_sessionReady) {
      await _worker!.createSession(tag: 'meeting_summarizer');
      _sessionReady = true;
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
    if (_loadedNCtx != _profile.nCtx) {
      return true;
    }
    return false;
  }

  Future<void> _loadModelNative() async {
    final p = _profile;
    await _worker!.loadModel(
      modelPath: _modelPath!,
      nCtx: p.nCtx,
      nGpuLayers: p.nGpuLayers,
      nBatch: p.nBatch,
      nThreads: p.nThreads,
    );
  }

  Future<void> ensureModelLoaded() async {
    await _ensureSessionReady();
    if (_modelLoaded) {
      try {
        final info = await _worker!.modelInfo();
        final runtimeNCtx = _parseRuntimeNCtx(info);
        if (runtimeNCtx != null && runtimeNCtx != _profile.nCtx) {
          await unloadModel();
        } else if (_loadedPresetId != _activePreset.id) {
          await unloadModel();
        }
      } catch (_) {
        await unloadModel();
      }
    }
    if (_needsReload()) {
      await _loadModelNative();
      _modelLoaded = true;
      _loadedNCtx = _profile.nCtx;
      _loadedPresetId = _activePreset.id;
    }
  }

  Future<void> unloadModel() async {
    await _ensureSessionReady();
    if (!_modelLoaded) {
      return;
    }
    await _worker!.unloadModel();
    _modelLoaded = false;
    _loadedNCtx = null;
    _loadedPresetId = null;
  }

  Future<void> abortStream() async {
    if (_worker == null || !_sessionReady) {
      return;
    }
    try {
      await _worker!.abortStream();
    } catch (_) {}
  }

  /// Soft recovery: abort in-flight decode but keep worker + loaded model.
  Future<void> softRecoverFromStuckGeneration() async {
    AppLogger.log('SUMMARIZE', 'Soft recovery — abort only, keep model loaded');
    await abortStream();
  }

  Future<void> recoverFromStuckGeneration() async {
    AppLogger.log('SUMMARIZE', 'Hard recovery — kill worker');
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
    return _worker!.modelInfo();
  }

  Stream<String> _streamSummary(
    String userPrompt, {
    String systemPrompt = AppModelPreset.systemPrompt,
    int? maxTokens,
  }) {
    final preset = _activePreset;
    final cap = maxTokens ?? _profile.maxOutputTokens;
    if (preset.promptMode == ModelPromptMode.nativeChatTemplate) {
      return _worker!.streamChat(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxTokens: cap,
      );
    }
    return _worker!.streamEcho(
      _buildEchoPrompt(userPrompt, systemPrompt: systemPrompt),
      maxTokens: cap,
    );
  }

  Future<String> _generateSummary(
    String transcriptSlice, {
    String systemPrompt = AppModelPreset.systemPrompt,
    bool isCombinePass = false,
    SummarizationRunMetrics? metrics,
    int? maxTokens,
  }) async {
    final userPrompt = isCombinePass
        ? _userPromptForCombine(transcriptSlice)
        : _userPromptForSlice(transcriptSlice);
    final buffer = StringBuffer();
    await for (final token in _streamSummary(
      userPrompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
    )) {
      if (metrics != null) {
        metrics.tokenCount += 1;
        metrics.recordFirstToken(
          DateTime.now().difference(metrics.startedAt).inMilliseconds,
        );
      }
      buffer.write(token);
    }
    var summary = SummaryQualityGate.clean(buffer.toString());
    if (SummaryQualityGate.isBadSummary(summary, transcriptSlice)) {
      metrics?.retryCount += 1;
      AppLogger.log('SUMMARIZE', 'Quality gate failed — retrying');
      final retrySystem = isCombinePass
          ? '${AppModelPreset.combineSystemPrompt} Start directly with the summary.'
          : 'Reply with only the summary sentences. Do not repeat any instructions.';
      final retryBuffer = StringBuffer();
      await for (final token in _streamSummary(
        transcriptSlice,
        systemPrompt: retrySystem,
        maxTokens: maxTokens,
      )) {
        retryBuffer.write(token);
      }
      summary = SummaryQualityGate.clean(retryBuffer.toString());
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
    final chunks = _chunking.chunk(cleaned);
    final metrics = SummarizationRunMetrics(
      presetId: _activePreset.id,
      transcriptChars: cleaned.length,
      chunkCount: chunks.length,
      wasTruncated: prepared.wasTruncated,
    );
    _lastRunMetrics = metrics;

    if (chunks.length == 1) {
      final summary = await _generateSummary(
        chunks.first,
        metrics: metrics,
      );
      metrics.recordDone(
        tokens: metrics.tokenCount,
        summaryLength: summary.length,
        qualityPassed: !SummaryQualityGate.isBadSummary(summary, chunks.first),
      );
      SummarizationMetricsStore.instance.add(metrics);
      return SummarizationResult(
        summary: summary,
        wasTruncated: prepared.wasTruncated,
        metrics: metrics,
      );
    }

    final partialSummaries = <String>[];
    for (final chunk in chunks) {
      final partial = await _generateSummary(chunk, metrics: metrics);
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
      metrics.recordDone(
        tokens: metrics.tokenCount,
        summaryLength: partialSummaries.first.length,
        qualityPassed: true,
      );
      SummarizationMetricsStore.instance.add(metrics);
      return SummarizationResult(
        summary: partialSummaries.first,
        wasChunked: true,
        wasTruncated: prepared.wasTruncated,
        metrics: metrics,
      );
    }

    final combined = _chunking.formatCombineInput(partialSummaries);
    final finalSummary = await _generateSummary(
      combined,
      systemPrompt: AppModelPreset.combineSystemPrompt,
      isCombinePass: true,
      metrics: metrics,
      maxTokens: _profile.combineMaxOutputTokens,
    );
    metrics.recordDone(
      tokens: metrics.tokenCount,
      summaryLength: finalSummary.length,
      qualityPassed: !SummaryQualityGate.isBadSummary(finalSummary, combined),
    );
    SummarizationMetricsStore.instance.add(metrics);
    return SummarizationResult(
      summary: finalSummary,
      wasChunked: true,
      wasTruncated: prepared.wasTruncated,
      metrics: metrics,
    );
  }

  String prepareInput(String transcript) => _prepareTranscript(transcript).text;

  /// True token streaming: yields tokens as native generates them.
  Stream<String> summarize(String transcript) async* {
    final prepared = _prepareTranscript(transcript);
    final cleaned = prepared.text;
    if (cleaned.isEmpty) {
      throw const SummarizationServiceException(
        'Transcript is empty. Record and transcribe first.',
      );
    }
    await ensureModelLoaded();
    final chunks = _chunking.chunk(cleaned);
    final metrics = SummarizationRunMetrics(
      presetId: _activePreset.id,
      transcriptChars: cleaned.length,
      chunkCount: chunks.length,
      wasTruncated: prepared.wasTruncated,
    );
    _lastRunMetrics = metrics;

    AppLogger.log(
      'SUMMARIZE',
      'Streaming preset=${_activePreset.id} chars=${cleaned.length} chunks=${chunks.length}',
    );

    if (chunks.length == 1) {
      final userPrompt = _userPromptForSlice(chunks.first);
      final buffer = StringBuffer();
      await for (final token in _streamSummary(userPrompt)) {
        metrics.tokenCount += 1;
        metrics.recordFirstToken(
          DateTime.now().difference(metrics.startedAt).inMilliseconds,
        );
        buffer.write(token);
        yield token;
      }
      var summary = SummaryQualityGate.clean(buffer.toString());
      if (SummaryQualityGate.isBadSummary(summary, chunks.first)) {
        metrics.retryCount += 1;
        buffer.clear();
        await for (final token in _streamSummary(
          chunks.first,
          systemPrompt:
              'Reply with only the summary sentences. Do not repeat any instructions.',
        )) {
          buffer.write(token);
          yield token;
        }
        summary = SummaryQualityGate.clean(buffer.toString());
      }
      metrics.recordDone(
        tokens: metrics.tokenCount,
        summaryLength: summary.length,
        qualityPassed: !SummaryQualityGate.isBadSummary(summary, chunks.first),
      );
      SummarizationMetricsStore.instance.add(metrics);
      return;
    }

    final partialSummaries = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      AppLogger.log('SUMMARIZE', 'Map chunk ${i + 1}/${chunks.length}');
      final partial = await _generateSummary(chunks[i], metrics: metrics);
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
      metrics.recordDone(
        tokens: metrics.tokenCount,
        summaryLength: partialSummaries.first.length,
        qualityPassed: true,
      );
      SummarizationMetricsStore.instance.add(metrics);
      return;
    }

    final combined = _chunking.formatCombineInput(partialSummaries);
    final combineBuffer = StringBuffer();
    await for (final token in _streamSummary(
      _userPromptForCombine(combined),
      systemPrompt: AppModelPreset.combineSystemPrompt,
      maxTokens: _profile.combineMaxOutputTokens,
    )) {
      metrics.recordFirstToken(
        DateTime.now().difference(metrics.startedAt).inMilliseconds,
      );
      combineBuffer.write(token);
      yield token;
    }
    final finalSummary = SummaryQualityGate.clean(combineBuffer.toString());
    metrics.recordDone(
      tokens: metrics.tokenCount,
      summaryLength: finalSummary.length,
      qualityPassed: !SummaryQualityGate.isBadSummary(finalSummary, combined),
    );
    SummarizationMetricsStore.instance.add(metrics);
  }

  Future<void> dispose() async {
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
      return;
    }
    await dispose();
    _modelPath = newPath;
  }
}
