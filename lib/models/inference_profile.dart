import 'package:ffi_learn/models/model_presets.dart';

/// Device-oriented inference tier (mirrors mature plugin preset patterns).
enum ModelTier { fast, balanced, slow }

/// Per-model runtime profile used at load and generation time.
class InferenceProfile {
  const InferenceProfile({
    required this.tier,
    required this.nCtx,
    required this.maxOutputTokens,
    required this.maxTranscriptChars,
    required this.nGpuLayers,
    required this.nBatch,
    required this.nThreads,
    required this.combineMaxOutputTokens,
    required this.promptMode,
  });

  final ModelTier tier;
  final int nCtx;
  final int maxOutputTokens;
  final int maxTranscriptChars;
  final int nGpuLayers;
  final int nBatch;
  final int nThreads;
  final int combineMaxOutputTokens;
  final ModelPromptMode promptMode;

  static InferenceProfile fromPreset(AppModelPreset preset) {
    final tier = preset.recommendedForMobile
        ? (preset.id == AppModelPresets.defaultModelId
            ? ModelTier.balanced
            : ModelTier.fast)
        : ModelTier.slow;

    return InferenceProfile(
      tier: tier,
      nCtx: preset.mobileNCtx,
      maxOutputTokens: preset.mobileMaxOutputTokens,
      maxTranscriptChars: preset.mobileMaxTranscriptChars,
      nGpuLayers: preset.mobileGpuLayers,
      nBatch: preset.mobileNBatch,
      nThreads: preset.mobileNThreads,
      combineMaxOutputTokens: preset.mobileCombineMaxOutputTokens,
      promptMode: preset.promptMode,
    );
  }
}
