/// Adaptive timeout budgets by transcript size, chunk count, and model tier.
class TimeoutPolicy {
  const TimeoutPolicy({
    this.firstTokenBaseSeconds = 120,
    this.firstTokenMaxSeconds = 420,
    this.totalBaseSeconds = 420,
    this.secondsPerChunk = 90,
    this.slowModelMultiplier = 1.5,
  });

  final int firstTokenBaseSeconds;
  final int firstTokenMaxSeconds;
  final int totalBaseSeconds;
  final int secondsPerChunk;
  final double slowModelMultiplier;

  Duration firstTokenTimeout({
    required int transcriptChars,
    required int chunkCount,
    required bool slowModel,
  }) {
    final estimatedPromptTokens = (transcriptChars / 2.5).round() + 20;
    var seconds = (estimatedPromptTokens * 2.5).clamp(
      firstTokenBaseSeconds.toDouble(),
      firstTokenMaxSeconds.toDouble(),
    );
    if (slowModel) {
      seconds *= slowModelMultiplier;
    }
    seconds = seconds.clamp(
      firstTokenBaseSeconds.toDouble(),
      firstTokenMaxSeconds.toDouble(),
    );
    return Duration(seconds: seconds.round());
  }

  Duration totalTimeout({
    required int chunkCount,
    required bool slowModel,
  }) {
    var seconds = totalBaseSeconds + (chunkCount - 1) * secondsPerChunk;
    if (slowModel) {
      seconds = (seconds * slowModelMultiplier).round();
    }
    return Duration(seconds: seconds);
  }
}
