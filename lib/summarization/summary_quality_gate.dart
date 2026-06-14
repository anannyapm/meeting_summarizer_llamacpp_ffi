/// Heuristic quality checks for on-device meeting summaries.
class SummaryQualityGate {
  static const List<String> instructionEchoPhrases = <String>[
    'summarize this meeting transcript',
    'write 2 to 4 sentences',
    'write 2-4 sentences',
    'about the main points',
    'merge these partial summaries',
  ];

  static const List<String> templateLeaks = <String>[
    '<|im_start|>',
    '\x3C|im_end|>',
    '<|endoftext|>',
    '<|eot_id|>',
    '[/INST]',
    '</s>',
    '<s>',
  ];

  static String clean(String raw) {
    var summary = raw.trim();
    for (final leak in templateLeaks) {
      summary = summary.replaceAll(leak, '');
    }
    summary = summary.replaceFirst(
      RegExp(r'^(assistant|user)\s*:\s*', caseSensitive: false),
      '',
    );
    summary = summary.replaceFirst(
      RegExp(r'^(summary|transcript)\s*:\s*', caseSensitive: false),
      '',
    );
    final lower = summary.toLowerCase();
    for (final prefix in instructionEchoPhrases) {
      if (lower.startsWith(prefix)) {
        summary = summary.substring(prefix.length).trimLeft();
      }
    }
    return summary.trim();
  }

  static bool isBadSummary(String summary, String source) {
    final trimmed = summary.trim();
    if (trimmed.length < 12) {
      return true;
    }
    final lower = trimmed.toLowerCase();
    for (final phrase in instructionEchoPhrases) {
      if (lower.contains(phrase)) {
        return true;
      }
    }
    if (lower.startsWith('summarize ') || lower.startsWith('write ')) {
      return true;
    }
    final normSummary = lower.replaceAll(RegExp(r'\s+'), ' ');
    final normSource =
        source.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normSummary.length >= 20 && normSource.contains(normSummary)) {
      return true;
    }
    final probeLen = normSummary.length < 48 ? normSummary.length : 48;
    return normSource.contains(normSummary.substring(0, probeLen));
  }

  /// Rubric score 0–1 for benchmark regression tests.
  static double rubricScore({
    required String summary,
    required List<String> expectedKeywords,
  }) {
    if (summary.trim().length < 20) {
      return 0;
    }
    final lower = summary.toLowerCase();
    if (isBadSummary(summary, '')) {
      return 0.1;
    }
    var hits = 0;
    for (final keyword in expectedKeywords) {
      if (lower.contains(keyword.toLowerCase())) {
        hits += 1;
      }
    }
    final coverage = expectedKeywords.isEmpty
        ? 0.5
        : hits / expectedKeywords.length;
    final lengthScore = summary.length.clamp(40, 400) / 400.0;
    return (coverage * 0.7 + lengthScore * 0.3).clamp(0.0, 1.0);
  }
}
