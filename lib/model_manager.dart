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
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString().toLowerCase() == expectedSha.toLowerCase();
  }

  Future<File> downloadModel(
    Uri downloadUrl, {
    String? expectedSha,
    DownloadProgress? onProgress,
  }) async {
    final dir = await _modelDirectory();
    final tempFile = File(p.join(dir.path, '$modelName.tmp'));
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final request = await HttpClient().getUrl(downloadUrl);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw ModelManagerException(
        'Download failed: HTTP ${response.statusCode}',
      );
    }

    final sink = tempFile.openWrite();
    int downloaded = 0;
    final total = response.contentLength;
    await for (final chunk in response) {
      downloaded += chunk.length;
      sink.add(chunk);
      onProgress?.call(downloaded, total);
    }
    await sink.close();

    final finalFile = await _modelFile();
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalFile.path);

    if (expectedSha != null && expectedSha.isNotEmpty) {
      final ok = await verifyChecksum(finalFile, expectedSha);
      if (!ok) {
        await finalFile.delete();
        throw ModelManagerException('Checksum mismatch');
      }
    }

    return finalFile;
  }

  Future<File> ensureModelDownloaded({
    required Uri downloadUrl,
    String? expectedSha,
    DownloadProgress? progress,
  }) async {
    final file = await _modelFile();
    if (await file.exists()) {
      if (expectedSha != null && expectedSha.isNotEmpty) {
        final ok = await verifyChecksum(file, expectedSha);
        if (ok) {
          return file;
        }
        await file.delete();
      } else {
        return file;
      }
    }
    return downloadModel(
      downloadUrl,
      expectedSha: expectedSha,
      onProgress: progress,
    );
  }

  Future<File> loadModel({
    required Uri downloadUrl,
    String? expectedSha,
    DownloadProgress? progress,
  }) async {
    final file = await ensureModelDownloaded(
      downloadUrl: downloadUrl,
      expectedSha: expectedSha,
      progress: progress,
    );
    return file;
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

  Future<void> deleteOldModels({int keepLatest = 2}) async {
    final dir = await _modelDirectory();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().toList()
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
