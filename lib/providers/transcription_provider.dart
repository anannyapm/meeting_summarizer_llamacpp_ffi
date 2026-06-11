import 'package:flutter/material.dart';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/services/file_transcription_service.dart';
import 'package:ffi_learn/services/transcription_service.dart';

enum TranscriptionStatus { idle, listening, transcribingFile, stopped, error }

class TranscriptionProvider extends ChangeNotifier {
  TranscriptionProvider(
    this._transcriptionService, [
    FileTranscriptionService? fileTranscriptionService,
  ]) : _fileTranscriptionService =
           fileTranscriptionService ?? FileTranscriptionService();

  final TranscriptionService _transcriptionService;
  final FileTranscriptionService _fileTranscriptionService;

  TranscriptionStatus _status = TranscriptionStatus.idle;
  final List<String> _finalizedSegments = <String>[];
  String _partialTranscript = '';
  String _transcript = '';
  String? _errorMessage;

  TranscriptionStatus get status => _status;
  bool get isListening => _status == TranscriptionStatus.listening;
  bool get isTranscribingFile =>
      _status == TranscriptionStatus.transcribingFile;
  String get transcript => _transcript;
  String? get errorMessage => _errorMessage;
  bool get hasTranscript => _transcript.trim().isNotEmpty;

  void _rebuildTranscript() {
    final finalized = _finalizedSegments.join(' ').trim();
    if (_partialTranscript.isEmpty) {
      _transcript = finalized;
      return;
    }
    _transcript = finalized.isEmpty
        ? _partialTranscript
        : '$finalized $_partialTranscript';
  }

  Future<void> startListening() async {
    AppLogger.log('STT', 'Provider.startListening invoked');
    _errorMessage = null;
    _finalizedSegments.clear();
    _partialTranscript = '';
    _transcript = '';
    _status = TranscriptionStatus.listening;
    notifyListeners();

    try {
      await _transcriptionService.startListening(
        onResult: (text, isFinal) {
          if (isFinal) {
            final segment = text.trim();
            if (segment.isNotEmpty) {
              _finalizedSegments.add(segment);
            }
            _partialTranscript = '';
            AppLogger.log(
              'STT',
              'Final segment chars=${segment.length} totalSegments=${_finalizedSegments.length}',
            );
          } else {
            _partialTranscript = text.trim();
          }
          _rebuildTranscript();
          notifyListeners();
        },
        onError: (message) {
          if (_isIgnorableTimeout(message)) {
            _status = TranscriptionStatus.stopped;
            _errorMessage = null;
            AppLogger.log(
              'STT',
              'Ignoring timeout and moving to stopped state',
            );
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
      AppLogger.log(
        'STT',
        'Provider stopped. transcriptChars=${_transcript.length}',
      );
      notifyListeners();
    } catch (error) {
      _status = TranscriptionStatus.error;
      _errorMessage = error.toString();
      AppLogger.log('STT', 'Provider stop failed: $error');
      notifyListeners();
    }
  }

  Future<void> transcribeRecordingFile(String audioPath) async {
    AppLogger.log('STT', 'Provider.transcribeRecordingFile path=$audioPath');
    _errorMessage = null;
    _finalizedSegments.clear();
    _partialTranscript = '';
    _transcript = '';
    _status = TranscriptionStatus.transcribingFile;
    notifyListeners();

    try {
      final text = await _fileTranscriptionService.transcribe(audioPath);
      _transcript = text;
      _status = TranscriptionStatus.stopped;
      AppLogger.log('STT', 'File transcription complete chars=${text.length}');
      notifyListeners();
    } catch (error) {
      _status = TranscriptionStatus.error;
      _errorMessage = error.toString();
      AppLogger.log('STT', 'File transcription failed: $error');
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
    _finalizedSegments.clear();
    _partialTranscript = '';
    _transcript = '';
    _errorMessage = null;
    notifyListeners();
  }

  void setManualTranscript(String value) {
    _finalizedSegments.clear();
    _partialTranscript = '';
    _transcript = value;
    AppLogger.log('STT', 'Manual transcript updated chars=${value.length}');
    AppLogger.log('STT', 'Manual transcript: $value');
    notifyListeners();
  }

  bool _isIgnorableTimeout(String message) {
    final text = message.toLowerCase();
    return text.contains('timeout') ||
        text.contains('speech timeout') ||
        text.contains('error_speech_timeout');
  }
}
