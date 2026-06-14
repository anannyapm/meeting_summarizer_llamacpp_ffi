import 'dart:convert';

import 'package:ffi_learn/core/app_logger.dart';

/// Structured telemetry for summarization runs (speed + quality signals).
class SummarizationRunMetrics {
  SummarizationRunMetrics({
    required this.presetId,
    required this.transcriptChars,
    this.chunkCount = 1,
    this.wasTruncated = false,
    this.retryCount = 0,
  }) : startedAt = DateTime.now();

  final String presetId;
  final int transcriptChars;
  final int chunkCount;
  final bool wasTruncated;
  int retryCount;
  final DateTime startedAt;

  int? ttftMs;
  int? totalMs;
  int tokenCount = 0;
  int summaryChars = 0;
  bool qualityGatePassed = false;
  String? timeoutReason;
  double? prefillTokPerSec;

  void recordFirstToken(int elapsedMs) {
    ttftMs ??= elapsedMs;
  }

  void recordDone({
    required int tokens,
    required int summaryLength,
    required bool qualityPassed,
  }) {
    tokenCount = tokens;
    summaryChars = summaryLength;
    qualityGatePassed = qualityPassed;
    totalMs = DateTime.now().difference(startedAt).inMilliseconds;
    _emit();
  }

  void recordTimeout(String reason) {
    timeoutReason = reason;
    totalMs = DateTime.now().difference(startedAt).inMilliseconds;
    _emit();
  }

  void _emit() {
    AppLogger.log('METRICS', toJsonString());
  }

  Map<String, Object?> toJson() => {
        'presetId': presetId,
        'transcriptChars': transcriptChars,
        'chunkCount': chunkCount,
        'wasTruncated': wasTruncated,
        'retryCount': retryCount,
        'ttftMs': ttftMs,
        'totalMs': totalMs,
        'tokenCount': tokenCount,
        'summaryChars': summaryChars,
        'qualityGatePassed': qualityGatePassed,
        'timeoutReason': timeoutReason,
        'prefillTokPerSec': prefillTokPerSec,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// In-memory ring buffer for dev-mode metrics inspection.
class SummarizationMetricsStore {
  SummarizationMetricsStore._();
  static final SummarizationMetricsStore instance = SummarizationMetricsStore._();

  final List<Map<String, Object?>> _runs = <Map<String, Object?>>[];
  static const int _maxRuns = 20;

  void add(SummarizationRunMetrics metrics) {
    _runs.insert(0, metrics.toJson());
    if (_runs.length > _maxRuns) {
      _runs.removeLast();
    }
  }

  List<Map<String, Object?>> get recentRuns => List.unmodifiable(_runs);
}
