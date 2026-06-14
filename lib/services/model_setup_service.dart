import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/model_manager.dart';
import 'package:ffi_learn/models/model_presets.dart';
import 'package:ffi_learn/providers/settings_provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';

enum SplashMode {
  /// First launch: full quest UI, may download model.
  firstLaunch,

  /// Return visit: compact splash, load from disk only.
  quickLoad,
}

enum ModelSetupPhase {
  checking,
  downloading,
  loading,
  ready,
  failed,
}

class ModelSetupProgress {
  const ModelSetupProgress({
    required this.phase,
    required this.progress,
    required this.message,
    this.detail,
  });

  final ModelSetupPhase phase;
  /// 0.0 – 1.0 overall progress.
  final double progress;
  final String message;
  final String? detail;
}

class ModelSetupService {
  static String formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  /// Downloads default preset if missing, loads into native bridge, returns local path.
  Future<String> ensureModelReady({
    required SettingsProvider settings,
    required SummarizationProvider summarization,
    required void Function(ModelSetupProgress progress) onProgress,
    SplashMode mode = SplashMode.firstLaunch,
  }) async {
    final preset = AppModelPresets.resolveById(settings.selectedModelPresetId);
    final manager = ModelManager(modelName: preset.fileName);
    final quickLoad = mode == SplashMode.quickLoad;

    if (summarization.isModelLoaded) {
      final cachedPath =
          summarization.currentModelPath ?? settings.resolvedModelPath;
      if (cachedPath != null) {
        onProgress(
          const ModelSetupProgress(
            phase: ModelSetupPhase.ready,
            progress: 1.0,
            message: 'Ready!',
            detail: 'Model already loaded',
          ),
        );
        return cachedPath;
      }
    }

    onProgress(
      ModelSetupProgress(
        phase: ModelSetupPhase.checking,
        progress: quickLoad ? 0.15 : 0.02,
        message: quickLoad ? 'Checking model...' : 'Scanning save data...',
        detail: preset.label,
      ),
    );

    var modelPath = settings.resolvedModelPath;

    if (modelPath == null || !await manager.checkIfDownloaded()) {
      if (quickLoad) {
        throw Exception(
          'Model file missing. Connect to Wi‑Fi and restart to re-download.',
        );
      }
      AppLogger.log('BOOT', 'First-time download preset=${preset.id}');
      onProgress(
        ModelSetupProgress(
          phase: ModelSetupPhase.downloading,
          progress: 0.05,
          message: 'Downloading AI model...',
          detail: 'This happens once — ${formatBytes(preset.expectedBytes ?? 0)}',
        ),
      );

      final file = await manager.ensureModelDownloaded(
        downloadUrl: Uri.parse(preset.downloadUrl),
        expectedSha: preset.expectedSha256,
        expectedBytes: preset.expectedBytes,
        progress: (downloaded, total) {
          final fraction = total > 0 ? downloaded / total : 0.0;
          final overall = 0.05 + fraction * 0.65;
          onProgress(
            ModelSetupProgress(
              phase: ModelSetupPhase.downloading,
              progress: overall,
              message: 'Downloading AI model...',
              detail: total > 0
                  ? '${(fraction * 100).round()}% · '
                      '${formatBytes(downloaded)} / ${formatBytes(total)}'
                  : formatBytes(downloaded),
            ),
          );
        },
      );
      modelPath = file.path;
      await settings.refreshModelPath();
    } else {
      AppLogger.log('BOOT', 'Model already on disk path=$modelPath');
    }

    onProgress(
      ModelSetupProgress(
        phase: ModelSetupPhase.loading,
        progress: quickLoad ? 0.35 : 0.75,
        message: quickLoad ? 'Warming up AI...' : 'Loading neural engine...',
        detail: quickLoad ? 'Almost there' : 'Warming up on-device AI',
      ),
    );

    await summarization.updateModelPath(modelPath);
    final loaded = await summarization.loadModel();
    if (!loaded) {
      throw Exception(
        summarization.errorMessage ?? 'Failed to load summarization model',
      );
    }

    await settings.markInitialSetupComplete();

    onProgress(
      ModelSetupProgress(
        phase: ModelSetupPhase.ready,
        progress: 1.0,
        message: 'Ready!',
        detail: quickLoad
            ? 'Back in action'
            : 'Your offline summarizer is armed',
      ),
    );

    return modelPath;
  }
}
