/// Benchmark corpus for speed/quality regression (no GGUF required).
class BenchmarkTranscript {
  const BenchmarkTranscript({
    required this.id,
    required this.label,
    required this.text,
    required this.expectedKeywords,
  });

  final String id;
  final String label;
  final String text;
  final List<String> expectedKeywords;
}

class BenchmarkCorpus {
  static const shortStandup = BenchmarkTranscript(
    id: 'short_standup',
    label: 'Short standup (~200 chars)',
    text:
        'Team standup: Alice finished the login bug fix and will deploy today. '
        'Bob is blocked on API keys from DevOps. Carol will review the PR by EOD. '
        'Next sprint we prioritize offline mode.',
    expectedKeywords: ['login', 'deploy', 'blocked', 'review', 'offline'],
  );

  static const mediumPlanning = BenchmarkTranscript(
    id: 'medium_planning',
    label: 'Medium planning (~800 chars)',
    text:
        'Product planning meeting. We agreed to ship the offline meeting summarizer '
        'for Android first, with iOS later. Engineering will keep the custom FFI bridge '
        'and extract a plugin in phase two. QA wants benchmark transcripts and TTFT metrics '
        'before release. Marketing asked for a demo video by Friday. '
        'Decision: default model is Llama 3.2 1B for balanced speed and quality. '
        'SmolLM2 360M remains the fast tier for low-end devices. '
        'Action: Ananny to add quality gates and overlap chunking. '
        'Action: DevOps to set up release APK signing. '
        'Risk: long meetings may need map-reduce summarization with a combine pass.',
    expectedKeywords: [
      'android',
      'plugin',
      'llama',
      'quality',
      'action',
    ],
  );

  static const longAllHands = BenchmarkTranscript(
    id: 'long_allhands',
    label: 'Long all-hands (~1800 chars)',
    text:
        'Company all-hands Q2. CEO opened with revenue up twelve percent. '
        'Engineering highlighted on-device AI: speech transcription with Whisper, '
        'summarization with llama.cpp via Dart FFI. The team fixed release splash '
        'issues by deferring SharedPreferences until after runApp. '
        'We discussed model tiers: fast models under one billion parameters, '
        'balanced around one billion, slow tier one point five billion plus on CPU only. '
        'Support reported users want faster first token and clearer progress during prefill. '
        'HR announced summer intern program. Finance reminded everyone about expense policy. '
        'CTO closed with three priorities: speed SLO under thirty seconds TTFT on recommended models, '
        'quality SLO with decisions and action items in every summary, '
        'and reliability with soft timeout recovery without killing the worker. '
        'Parking lot: web feasibility study for WASM WebGPU, not blocking Android ship. '
        'Next all-hands in four weeks.',
    expectedKeywords: [
      'revenue',
      'whisper',
      'speed',
      'quality',
      'web',
    ],
  );

  static const List<BenchmarkTranscript> all = <BenchmarkTranscript>[
    shortStandup,
    mediumPlanning,
    longAllHands,
  ];
}
