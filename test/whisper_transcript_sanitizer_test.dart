import 'package:flutter_test/flutter_test.dart';

import 'package:ffi_learn/services/whisper_transcript_sanitizer.dart';

void main() {
  group('WhisperTranscriptSanitizer', () {
    test('removes blank audio and playback tokens', () {
      expect(
        WhisperTranscriptSanitizer.clean(
          '[BLANK_AUDIO] [BLANK_AUDIO] [END PLAYBACK]',
        ),
        isEmpty,
      );
    });

    test('preserves real speech', () {
      expect(
        WhisperTranscriptSanitizer.clean(
          '[BLANK_AUDIO] Team standup at nine. [END PLAYBACK]',
        ),
        'Team standup at nine.',
      );
    });

    test('looksLikeSilence detects junk-only output', () {
      expect(
        WhisperTranscriptSanitizer.looksLikeSilence(
          '[BLANK_AUDIO] [END PLAYBACK]',
        ),
        isTrue,
      );
    });
  });
}
