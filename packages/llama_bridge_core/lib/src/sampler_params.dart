class SamplerParams {
  const SamplerParams({
    this.repeatPenalty = 1.18,
    this.penaltyLastN = 64,
    this.greedy = true,
  });

  final double repeatPenalty;
  final int penaltyLastN;
  final bool greedy;
}
