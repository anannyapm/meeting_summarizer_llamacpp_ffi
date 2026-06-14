class GenerationOptions {
  const GenerationOptions({
    this.maxTokens = 80,
    this.systemPrompt = '',
    this.useChatTemplate = true,
  });

  final int maxTokens;
  final String systemPrompt;
  final bool useChatTemplate;
}

enum GenerationEventType { token, done, error, cancelled }

class GenerationEvent {
  const GenerationEvent.token(this.text)
      : type = GenerationEventType.token,
        error = null;

  const GenerationEvent.done()
      : type = GenerationEventType.done,
        text = null,
        error = null;

  const GenerationEvent.error(this.error)
      : type = GenerationEventType.error,
        text = null;

  const GenerationEvent.cancelled()
      : type = GenerationEventType.cancelled,
        text = null,
        error = null;

  final GenerationEventType type;
  final String? text;
  final Object? error;
}
