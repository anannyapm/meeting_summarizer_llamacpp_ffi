class AppModelPreset {
  const AppModelPreset({
    required this.id,
    required this.label,
    required this.fileName,
    required this.downloadUrl,
    this.expectedSha256,
    this.expectedBytes,
    this.recommendedForMobile = false,
  });

  final String id;
  final String label;
  final String fileName;
  final String downloadUrl;
  final String? expectedSha256;
  final int? expectedBytes;

  /// True for ≤1.1B models that prefill quickly on phone CPU.
  final bool recommendedForMobile;
}

class AppModelPresets {
  static const String defaultModelId = 'llama3_2_1b_q4_k_m';

  // Replace `main` with an immutable HF commit revision once SHA256 is recorded.
  static const List<AppModelPreset> all = <AppModelPreset>[
    AppModelPreset(
      id: 'llama3_2_1b_q4_k_m',
      label: 'Llama 3.2 1B Instruct (Q4_K_M)',
      fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      expectedBytes: 807694464,
      recommendedForMobile: true,
    ),
    AppModelPreset(
      id: 'tinyllama_1_1b_q4_k_m',
      label: 'TinyLlama 1.1B Chat (Q4_K_M)',
      fileName: 'tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
      expectedBytes: 668788096,
      recommendedForMobile: true,
    ),
    AppModelPreset(
      id: 'qwen2_5_1_5b_q4_k_m',
      label: 'Qwen2.5 1.5B Instruct (Q4_K_M)',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      expectedBytes: 1068800000,
    ),
    AppModelPreset(
      id: 'smollm2_1_7b_q4_k_m',
      label: 'SmolLM2 1.7B Instruct (Q4_K_M)',
      fileName: 'smollm2-1.7b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf',
      expectedBytes: 1073741824,
    ),
  ];

  static AppModelPreset resolveById(String id) {
    for (final preset in all) {
      if (preset.id == id) {
        return preset;
      }
    }
    return all.first;
  }

  static AppModelPreset? findByFilePath(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    for (final preset in all) {
      if (path.endsWith(preset.fileName)) {
        return preset;
      }
    }
    return null;
  }

  static bool isMobileRecommendedPath(String? path) {
    return findByFilePath(path)?.recommendedForMobile ?? false;
  }
}
