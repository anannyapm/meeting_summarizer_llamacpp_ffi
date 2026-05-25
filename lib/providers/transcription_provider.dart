import 'package:flutter/material.dart';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/services/transcription_service.dart';

enum TranscriptionStatus { idle, listening, stopped, error }

class TranscriptionProvider extends ChangeNotifier {
  TranscriptionProvider(this._transcriptionService);

  final TranscriptionService _transcriptionService;

  TranscriptionStatus _status = TranscriptionStatus.idle;
  String _transcript = '';
  String? _errorMessage;

  TranscriptionStatus get status => _status;
  bool get isListening => _status == TranscriptionStatus.listening;
  String get transcript => _transcript;
  String? get errorMessage => _errorMessage;
  bool get hasTranscript => _transcript.trim().isNotEmpty;

  Future<void> startListening() async {
    AppLogger.log('STT', 'Provider.startListening invoked');
    _errorMessage = null;
    _transcript = '';
    _status = TranscriptionStatus.listening;
    notifyListeners();

    try {
      await _transcriptionService.startListening(
        onResult: (text, isFinal) {
          _transcript = text;
          if (isFinal) {
            AppLogger.log(
              'STT',
              'Final result chars=${text.length} preview="${text.length > 80 ? text.substring(0, 80) : text}"',
            );
          }
          notifyListeners();
        },
        onError: (message) {
          if (_isIgnorableTimeout(message)) {
            // Timeout/silence is common on-device and should not block flow.
            _status = TranscriptionStatus.stopped;
            _errorMessage = null;
            AppLogger.log('STT', 'Ignoring timeout and moving to stopped state');
            notifyListeners();
            return;
          }
          _status = TranscriptionStatus.error;
          _errorMessage = message;
          AppLogger.log('STT', 'Provider error: $message');
          notifyListeners();
        },
      );
    } catch (error) {
      _status = TranscriptionStatus.error;
      _errorMessage = error.toString();
      AppLogger.log('STT', 'Provider start failed: $error');
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    AppLogger.log('STT', 'Provider.stopListening invoked');
    try {
      await _transcriptionService.stopListening();
      if (_status != TranscriptionStatus.error) {
        _status = TranscriptionStatus.stopped;
      }
      AppLogger.log('STT', 'Provider stopped. transcriptChars=${_transcript.length}');
      notifyListeners();
    } catch (error) {
      _status = TranscriptionStatus.error;
      _errorMessage = error.toString();
      AppLogger.log('STT', 'Provider stop failed: $error');
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    if (_status == TranscriptionStatus.error) {
      _status = TranscriptionStatus.idle;
    }
    notifyListeners();
  }

  void reset() {
    _status = TranscriptionStatus.idle;
    _transcript = '';
    _errorMessage = null;
    notifyListeners();
  }

  void setManualTranscript(String value) {
    _transcript = value;
    AppLogger.log('STT', 'Manual transcript updated chars=${value.length}');
    notifyListeners();
  }

  bool _isIgnorableTimeout(String message) {
    final text = message.toLowerCase();
    return text.contains('timeout') ||
        text.contains('speech timeout') ||
        text.contains('error_speech_timeout');
  }
}
