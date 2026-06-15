import 'dart:io';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/services/whisper_transcript_sanitizer.dart';
import 'package:path/path.dart' as p;
import 'package:whisper_ggml/whisper_ggml.dart';

class FileTranscriptionException implements Exception {
  const FileTranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FileTranscriptionService {
  FileTranscriptionService({this.model = WhisperModel.tiny});

  final WhisperModel model;
  final WhisperController _controller = WhisperController();

  Future<void> ensureModelDownloaded() async {
    AppLogger.log('STT', 'Ensuring whisper model ${model.modelName} is downloaded');
    await _controller.downloadModel(model);
  }

  Future<String> transcribe(String audioPath) async {
    final source = File(audioPath);
    if (!await source.exists()) {
      throw FileTranscriptionException('Recording file not found: $audioPath');
    }

    await ensureModelDownloaded();

    final wavPath = p.join(
      p.dirname(audioPath),
      '${p.basenameWithoutExtension(audioPath)}_whisper.wav',
    );
    final converted = await WhisperAudioConvert(
      audioInput: source,
      audioOutput: File(wavPath),
    ).convert();
    if (converted == null) {
      throw const FileTranscriptionException(
        'Failed to convert recording to WAV for Whisper.',
      );
    }

    AppLogger.log('STT', 'Transcribing file with whisper_ggml path=${converted.path}');
    final result = await _controller.transcribe(
      model: model,
      audioPath: converted.path,
      lang: 'en',
    );

    if (result == null) {
      throw const FileTranscriptionException('Whisper transcription returned no result.');
    }

    final rawText = result.transcription.text.trim();
    final text = WhisperTranscriptSanitizer.clean(rawText);
    AppLogger.log(
      'STT',
      'Whisper transcription done in ${result.time.inMilliseconds} ms '
      'rawChars=${rawText.length} cleanChars=${text.length}',
    );

    if (text.isEmpty) {
      throw const FileTranscriptionException(
        'No speech detected in the recording. '
        'Speak closer to the mic, record for a few seconds, or on an emulator '
        'enable mic input (Extended controls → Microphone). '
        'You can also paste a transcript manually.',
      );
    }

    return text;
  }
}
