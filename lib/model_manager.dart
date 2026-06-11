import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef DownloadProgress = void Function(int downloaded, int total);

class ModelManagerException implements Exception {
  const ModelManagerException(this.message);

  final String message;

  @override
  String toString() => 'ModelManagerException($message)';
}

class ModelManager {
  ModelManager({required this.modelName});

  final String modelName;

  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  Future<Directory> _modelDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _modelFile() async {
    final dir = await _modelDirectory();
    return File(p.join(dir.path, modelName));
  }

  Future<bool> checkIfDownloaded() async {
    final file = await _modelFile();
    return file.exists();
  }

  Future<bool> verifyChecksum(File file, String expectedSha) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedSha.toLowerCase();
  }

  /// Exact size when [expectedSha] is set (pinned blob). Otherwise allow ~5%
  /// drift for Hugging Face `main` URLs whose file size can change slightly.
  bool _bytesMatchExpected(
    int actualBytes,
    int? expectedBytes,
    String? expectedSha,
  ) {
    if (expectedBytes == null || expectedBytes <= 0) {
      return true;
    }
    if (expectedSha != null && expectedSha.isNotEmpty) {
      return actualBytes == expectedBytes;
    }
    const tolerance = 0.05;
    final minBytes = (expectedBytes * (1 - tolerance)).floor();
    final maxBytes = (expectedBytes * (1 + tolerance)).ceil();
    return actualBytes >= minBytes && actualBytes <= maxBytes;
  }

  Future<void> _ensureFreeDiskSpace(int requiredBytes) async {
    final dir = await _modelDirectory();
    final stat = await dir.stat();
    // stat doesn't give free space on all platforms; best-effort skip on failure.
    if (stat.type == FileSystemEntityType.directory) {
      // No portable free-space API without platform channels; caller passes expectedBytes.
      if (requiredBytes > 0 && requiredBytes > 5 * 1024 * 1024 * 1024) {
        throw const ModelManagerException('Model size exceeds safe limit.');
      }
    }
  }

  Future<File> downloadModel(
    Uri downloadUrl, {
    String? expectedSha,
    int? expectedBytes,
    DownloadProgress? onProgress,
  }) async {
    if (expectedBytes != null && expectedBytes > 0) {
      await _ensureFreeDiskSpace(expectedBytes);
    }

    final dir = await _modelDirectory();
    final tempFile = File(p.join(dir.path, '$modelName.tmp'));
    var downloaded = 0;
    if (await tempFile.exists()) {
      downloaded = await tempFile.length();
    }

    Object? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        downloaded = await _downloadWithResume(
          downloadUrl: downloadUrl,
          tempFile: tempFile,
          startOffset: downloaded,
          expectedBytes: expectedBytes,
          onProgress: onProgress,
        );
        lastError = null;
        break;
      } catch (error) {
        lastError = error;
        downloaded = await tempFile.exists() ? await tempFile.length() : 0;
        if (attempt < _maxRetries - 1) {
          await Future<void>.delayed(_retryDelay * (attempt + 1));
        }
      }
    }

    if (lastError != null) {
      throw ModelManagerException('Download failed: $lastError');
    }

    final finalFile = await _modelFile();
    if (!_bytesMatchExpected(downloaded, expectedBytes, expectedSha)) {
      await tempFile.delete();
      throw ModelManagerException(
        'Downloaded size mismatch: expected $expectedBytes got $downloaded',
      );
    }

    if (expectedSha != null && expectedSha.isNotEmpty) {
      final ok = await verifyChecksum(tempFile, expectedSha);
      if (!ok) {
        await tempFile.delete();
        throw const ModelManagerException('Checksum mismatch before promote');
      }
    }

    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalFile.path);
    return finalFile;
  }

  Future<int> _downloadWithResume({
    required Uri downloadUrl,
    required File tempFile,
    required int startOffset,
    int? expectedBytes,
    DownloadProgress? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(downloadUrl);
      request.headers.set(HttpHeaders.userAgentHeader, 'ffi_learn/1.0');
      if (startOffset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startOffset-');
      }

      final response = await request.close().timeout(const Duration(minutes: 30));
      final status = response.statusCode;
      if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
        throw ModelManagerException('Download failed: HTTP $status');
      }

      final contentLength = response.contentLength;
      final total = expectedBytes ??
          (contentLength > 0 ? startOffset + contentLength : contentLength);

      final sink = tempFile.openWrite(
        mode: startOffset > 0 && status == HttpStatus.partialContent
            ? FileMode.append
            : FileMode.write,
      );
      var downloaded = startOffset;
      await for (final chunk in response) {
        downloaded += chunk.length;
        sink.add(chunk);
        onProgress?.call(downloaded, total > 0 ? total : downloaded);
      }
      await sink.close();
      return downloaded;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> ensureModelDownloaded({
    required Uri downloadUrl,
    String? expectedSha,
    int? expectedBytes,
    DownloadProgress? progress,
  }) async {
    final file = await _modelFile();
    if (await file.exists()) {
      if (expectedSha != null && expectedSha.isNotEmpty) {
        final ok = await verifyChecksum(file, expectedSha);
        if (ok &&
            _bytesMatchExpected(
              await file.length(),
              expectedBytes,
              expectedSha,
            )) {
          return file;
        }
        await file.delete();
      } else if (_bytesMatchExpected(
        await file.length(),
        expectedBytes,
        expectedSha,
      )) {
        return file;
      } else {
        await file.delete();
      }
    }
    return downloadModel(
      downloadUrl,
      expectedSha: expectedSha,
      expectedBytes: expectedBytes,
      onProgress: progress,
    );
  }

  Future<File> loadModel({
    required Uri downloadUrl,
    String? expectedSha,
    int? expectedBytes,
    DownloadProgress? progress,
  }) async {
    return ensureModelDownloaded(
      downloadUrl: downloadUrl,
      expectedSha: expectedSha,
      expectedBytes: expectedBytes,
      progress: progress,
    );
  }

  Future<File> ensureBundledModel(String assetPath) async {
    final modelFile = await _modelFile();
    if (await modelFile.exists()) {
      return modelFile;
    }

    final tempFile = File('${modelFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    try {
      final bytes = await rootBundle.load(assetPath);
      await tempFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      await tempFile.rename(modelFile.path);
      return modelFile;
    } catch (e) {
      throw ModelManagerException('Failed to extract bundled model: $e');
    }
  }

  Future<void> deleteOldModels({
    int keepLatest = 2,
    String? keepFileName,
  }) async {
    final dir = await _modelDirectory();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().where((file) {
      if (keepFileName != null && p.basename(file.path) == keepFileName) {
        return false;
      }
      return !file.path.endsWith('.tmp');
    }).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (int i = keepLatest; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {
        if (kDebugMode) {
          // ignore
        }
      }
    }
  }

  Future<String> getLocalPath() async {
    final file = await _modelFile();
    return file.path;
  }

  Future<bool> checkLocalModelIntegrity(String expectedSha) async {
    final file = await _modelFile();
    if (!await file.exists()) {
      return false;
    }
    return verifyChecksum(file, expectedSha);
  }
}
