import 'package:ffi_learn/core/app_logger.dart';
import 'package:speech_to_text/speech_to_text.dart';

class TranscriptionServiceException implements Exception {
  const TranscriptionServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TranscriptionService {
  final SpeechToText _speechToText = SpeechToText();
  bool _isInitialized = false;

  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(String error)? onError,
  }) async {
    if (!_isInitialized) {
      AppLogger.log('STT', 'Initializing speech recognizer...');
      final available = await _speechToText.initialize(
        onError: (error) => onError?.call(error.errorMsg),
      );
      _isInitialized = available;
      AppLogger.log('STT', 'Speech recognizer available=$available');
      if (!available) {
        throw const TranscriptionServiceException(
          'Speech recognition is not available on this device.',
        );
      }
    }

    Future<void> listenWithOptions(SpeechListenOptions options) {
      return _speechToText.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        listenOptions: options,
      );
    }

    try {
      // Prefer on-device recognition for privacy.
      AppLogger.log('STT', 'Starting on-device listening...');
      await listenWithOptions(
        SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          onDevice: true,
          listenFor: Duration(minutes: 30),
          pauseFor: Duration(seconds: 30),
        ),
      );
      AppLogger.log('STT', 'On-device listening started.');
    } catch (_) {
      // Fallback for devices without downloadable offline language packs.
      AppLogger.log('STT', 'On-device start failed, falling back to non-device STT...');
      await listenWithOptions(
        SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          onDevice: false,
          listenFor: Duration(minutes: 30),
          pauseFor: Duration(seconds: 30),
        ),
      );
      AppLogger.log('STT', 'Fallback listening started.');
    }
  }

  Future<void> stopListening() async {
    AppLogger.log('STT', 'Stopping listening...');
    await _speechToText.stop();
    AppLogger.log('STT', 'Listening stopped.');
  }
}
