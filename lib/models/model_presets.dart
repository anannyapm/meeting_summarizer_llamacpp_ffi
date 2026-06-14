/// How summarization builds the prompt before native generation.
enum ModelPromptMode {
  /// Raw string passed to [bridge_session_stream].
  plainEcho,

  /// [llama_chat_apply_template] via [bridge_session_stream_chat].
  nativeChatTemplate,
}

class AppModelPreset {
  const AppModelPreset({
    required this.id,
    required this.label,
    required this.fileName,
    required this.downloadUrl,
    this.expectedSha256,
    this.expectedBytes,
    this.recommendedForMobile = false,
    this.mobileNCtx = 256,
    this.mobileMaxOutputTokens = 64,
    this.mobileMaxTranscriptChars = 500,
    this.mobileGpuLayers = 0,
    this.mobileNBatch = 64,
    this.mobileNThreads = 4,
    this.mobileCombineMaxOutputTokens = 96,
    this.promptMode = ModelPromptMode.nativeChatTemplate,
  });

  final String id;
  final String label;
  final String fileName;
  final String downloadUrl;
  final String? expectedSha256;
  final int? expectedBytes;

  /// True for models that prefill quickly on phone CPU.
  final bool recommendedForMobile;

  final int mobileNCtx;
  final int mobileMaxOutputTokens;
  final int mobileMaxTranscriptChars;
  final int mobileGpuLayers;
  final int mobileNBatch;
  final int mobileNThreads;
  final int mobileCombineMaxOutputTokens;
  final ModelPromptMode promptMode;

  static const String systemPrompt =
      'You are a meeting summarizer. The user message is a raw transcript. '
      'Reply with a short summary in 2 to 4 sentences covering main topics, '
      'decisions, and action items. Never repeat instructions or transcript text.';

  static const String combineSystemPrompt =
      'You merge partial meeting summaries into one coherent paragraph. '
      'Write 2 to 5 complete sentences in plain prose. '
      'Do not use bullet lists or labels like Part 1. Output only the final summary.';
}

class AppModelPresets {
  static const String defaultModelId = 'llama3_2_1b_q4_k_m';

  static const List<AppModelPreset> all = <AppModelPreset>[
    AppModelPreset(
      id: 'smollm2_360m_q4_k_m',
      label: 'SmolLM2 360M Instruct (Q4_K_M)',
      fileName: 'SmolLM2-360M-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf',
      expectedBytes: 270590880,
      recommendedForMobile: true,
      mobileNCtx: 512,
      mobileMaxOutputTokens: 80,
      mobileMaxTranscriptChars: 600,
      mobileNBatch: 64,
      mobileNThreads: 4,
      mobileCombineMaxOutputTokens: 96,
      promptMode: ModelPromptMode.plainEcho,
    ),
    AppModelPreset(
      id: 'qwen2_5_0_5b_q4_k_m',
      label: 'Qwen2.5 0.5B Instruct (Q4_K_M)',
      fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      expectedBytes: 417334272,
      recommendedForMobile: true,
      mobileNCtx: 512,
      mobileMaxOutputTokens: 80,
      mobileMaxTranscriptChars: 600,
      mobileNBatch: 64,
      mobileNThreads: 4,
      mobileCombineMaxOutputTokens: 96,
    ),
    AppModelPreset(
      id: 'llama3_2_1b_q4_k_m',
      label: 'Llama 3.2 1B Instruct (Q4_K_M)',
      fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      expectedBytes: 807694464,
      recommendedForMobile: true,
      mobileNCtx: 512,
      mobileMaxOutputTokens: 80,
      mobileMaxTranscriptChars: 600,
    ),
    AppModelPreset(
      id: 'tinyllama_1_1b_q4_k_m',
      label: 'TinyLlama 1.1B Chat (Q4_K_M)',
      fileName: 'tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
      expectedBytes: 668788096,
      recommendedForMobile: true,
      mobileNCtx: 512,
      mobileMaxOutputTokens: 80,
      mobileMaxTranscriptChars: 600,
    ),
    AppModelPreset(
      id: 'qwen2_5_1_5b_q4_k_m',
      label: 'Qwen2.5 1.5B Instruct (Q4_K_M)',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      expectedBytes: 1068800000,
      mobileMaxOutputTokens: 48,
      mobileMaxTranscriptChars: 400,
    ),
    AppModelPreset(
      id: 'smollm2_1_7b_q4_k_m',
      label: 'SmolLM2 1.7B Instruct (Q4_K_M)',
      fileName: 'smollm2-1.7b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf',
      expectedBytes: 1073741824,
      mobileMaxOutputTokens: 48,
      mobileMaxTranscriptChars: 400,
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

  /// Dropdown suffix for Settings UI.
  static String tierLabel(AppModelPreset preset) {
    if (preset.recommendedForMobile) {
      if (preset.id == defaultModelId) {
        return ' — balanced (recommended)';
      }
      return ' — fast on mobile';
    }
    return ' — slow on CPU';
  }
}
