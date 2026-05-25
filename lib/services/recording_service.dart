import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();

  Future<String> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const RecordingException('Microphone permission denied.');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(appDir.path, 'recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final fileName =
        'meeting_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final outputPath = p.join(recordingsDir.path, fileName);

    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      sampleRate: 16000,
      bitRate: 128000,
    );

    await _recorder.start(config, path: outputPath);
    return outputPath;
  }

  Future<String?> stopRecording() {
    return _recorder.stop();
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

class RecordingException implements Exception {
  final String message;

  const RecordingException(this.message);

  @override
  String toString() => message;
}
