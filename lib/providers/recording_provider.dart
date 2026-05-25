import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ffi_learn/services/recording_service.dart';

enum RecordingStatus { idle, recording, stopping, error }

class RecordingProvider extends ChangeNotifier {
  RecordingProvider(this._recordingService);

  final RecordingService _recordingService;

  RecordingStatus _status = RecordingStatus.idle;
  String? _activeRecordingPath;
  String? _lastRecordingPath;
  String? _errorMessage;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;
  Timer? _ticker;

  RecordingStatus get status => _status;
  bool get isRecording => _status == RecordingStatus.recording;
  bool get canStart => _status == RecordingStatus.idle;
  bool get canStop => _status == RecordingStatus.recording;
  String? get lastRecordingPath => _lastRecordingPath;
  String? get errorMessage => _errorMessage;
  Duration get elapsed => _elapsed;

  Future<void> startRecording() async {
    if (!canStart) {
      return;
    }

    _errorMessage = null;
    _elapsed = Duration.zero;
    _status = RecordingStatus.recording;
    notifyListeners();

    try {
      _activeRecordingPath = await _recordingService.startRecording();
      _startedAt = DateTime.now();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final startedAt = _startedAt;
        if (startedAt == null) {
          return;
        }
        _elapsed = DateTime.now().difference(startedAt);
        notifyListeners();
      });
    } catch (error) {
      _status = RecordingStatus.error;
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<String?> stopRecording() async {
    if (!canStop) {
      return null;
    }

    _status = RecordingStatus.stopping;
    notifyListeners();

    _ticker?.cancel();
    _ticker = null;
    if (_startedAt != null) {
      _elapsed = DateTime.now().difference(_startedAt!);
    }

    try {
      final savedPath = await _recordingService.stopRecording();
      _lastRecordingPath = savedPath ?? _activeRecordingPath;
      _activeRecordingPath = null;
      _startedAt = null;
      _status = RecordingStatus.idle;
      notifyListeners();
      return _lastRecordingPath;
    } catch (error) {
      _status = RecordingStatus.error;
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    if (_status == RecordingStatus.error) {
      _status = RecordingStatus.idle;
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_recordingService.dispose());
    super.dispose();
  }
}
