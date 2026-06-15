/// Strips Whisper meta-tokens that appear for silence or non-speech audio.
abstract final class WhisperTranscriptSanitizer {
  static const List<String> _nonSpeechTokens = <String>[
    '[BLANK_AUDIO]',
    '[END PLAYBACK]',
    '[AUDIO]',
    '(BLANK_AUDIO)',
    '(END PLAYBACK)',
  ];

  static String clean(String raw) {
    var text = raw;
    for (final token in _nonSpeechTokens) {
      text = text.replaceAll(token, ' ');
      text = text.replaceAll(token.toLowerCase(), ' ');
    }
    // Remove any remaining bracketed all-caps meta tokens Whisper sometimes emits.
    text = text.replaceAll(RegExp(r'\[[A-Z_ ]+\]'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool looksLikeSilence(String raw) => clean(raw).isEmpty;
}
