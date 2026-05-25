import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/model_manager.dart';
import 'package:ffi_learn/models/model_presets.dart';
import 'package:ffi_learn/providers/settings_provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/widgets/dev_mode_panel.dart';

/// Settings screen with developer mode toggle
class SettingsScreen extends StatefulWidget {
  final String? initialModelPath;

  const SettingsScreen({
    super.key,
    this.initialModelPath,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _selectedModelId;
  bool _isDownloadingPreset = false;
  String _downloadStatus = '';
  int _lastLoggedDownloadPercent = -1;

  @override
  void initState() {
    super.initState();
    _selectedModelId = _inferSelectedModelId(widget.initialModelPath);
  }

  String _inferSelectedModelId(String? modelPath) {
    if (modelPath == null || modelPath.isEmpty) {
      return AppModelPresets.defaultModelId;
    }
    final fileName = p.basename(modelPath);
    for (final preset in AppModelPresets.all) {
      if (preset.fileName == fileName) {
        return preset.id;
      }
    }
    return AppModelPresets.defaultModelId;
  }

  String _formatBytes(int bytes) {
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

  Future<void> _applyModelPreset() async {
    final preset = AppModelPresets.resolveById(_selectedModelId);
    AppLogger.log('MODEL', 'Applying preset id=${preset.id} label=${preset.label}');
    setState(() {
      _isDownloadingPreset = true;
      _downloadStatus = 'Preparing ${preset.label}...';
    });

    try {
      final manager = ModelManager(modelName: preset.fileName);
      final file = await manager.ensureModelDownloaded(
        downloadUrl: Uri.parse(preset.downloadUrl),
        progress: (downloaded, total) {
          if (!mounted) {
            return;
          }
          setState(() {
            if (total > 0) {
              final percent = downloaded * 100 ~/ total;
              if (percent == 0 || percent == 25 || percent == 50 || percent == 75 || percent >= 95) {
                if (_lastLoggedDownloadPercent != percent) {
                  _lastLoggedDownloadPercent = percent;
                  AppLogger.log(
                    'MODEL',
                    'Download progress $percent% (${_formatBytes(downloaded)} / ${_formatBytes(total)})',
                  );
                }
              }
              _downloadStatus =
                  'Downloading $percent% (${_formatBytes(downloaded)} / ${_formatBytes(total)})';
            } else {
              _downloadStatus = 'Downloading ${_formatBytes(downloaded)}';
            }
          });
        },
      );

      if (!mounted) {
        return;
      }

      final summarization = context.read<SummarizationProvider>();
      AppLogger.log('MODEL', 'Preset downloaded at path=${file.path}');
      await summarization.updateModelPath(file.path);
      final loaded = await summarization.loadModel();
      if (!loaded) {
        final message = summarization.errorMessage ?? 'Unknown model load error';
        AppLogger.log('MODEL', 'Preset apply finished, but load failed: $message');
        throw Exception(message);
      }
      AppLogger.log('MODEL', 'Preset applied and model loaded.');

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model switched to ${preset.label}')),
      );
      setState(() {
        _downloadStatus = 'Using ${preset.label}';
      });
    } catch (error) {
      AppLogger.log('MODEL', 'Applying preset failed: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model switch failed: $error')),
      );
      setState(() {
        _downloadStatus = 'Failed to switch model';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingPreset = false;
          _lastLoggedDownloadPercent = -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Developer Mode',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Enable FFI Debug Tools'),
                          Switch(
                            value: settings.devModeEnabled,
                            onChanged: (_) => settings.toggleDevMode(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'When enabled, you can access the FFI debugging interface to test the native bridge and model loading.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Consumer<SummarizationProvider>(
                builder: (context, summarization, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Model Preset',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedModelId,
                        items: AppModelPresets.all.map((preset) {
                          return DropdownMenuItem<String>(
                            value: preset.id,
                            child: Text(preset.label),
                          );
                        }).toList(),
                        onChanged: _isDownloadingPreset
                            ? null
                            : (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _selectedModelId = value;
                                });
                              },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Select model',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_downloadStatus.isNotEmpty)
                        Text(
                          _downloadStatus,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_isDownloadingPreset ||
                                  summarization.isLoadingModel)
                              ? null
                              : _applyModelPreset,
                          child: Text(
                            _isDownloadingPreset
                                ? 'Downloading Model...'
                                : 'Apply Selected Model',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Consumer<SummarizationProvider>(
                builder: (context, summarization, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Model Control',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Model path',
                        summarization.currentModelPath ?? 'Unavailable',
                      ),
                      _buildInfoRow(
                        'Model status',
                        summarization.isModelLoaded ? 'Loaded' : 'Not loaded',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        summarization.modelInfo,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (summarization.errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          summarization.errorMessage!,
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: summarization.isLoadingModel
                                  ? null
                                  : summarization.loadModel,
                              child: Text(
                                summarization.isLoadingModel
                                    ? 'Loading...'
                                    : 'Load Model',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: summarization.isLoadingModel
                                  ? null
                                  : summarization.unloadModel,
                              child: const Text('Unload Model'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick Access',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!settings.devModeEnabled)
                        const Text(
                          'Enable developer mode to access FFI debug tools.',
                          style: TextStyle(color: Colors.grey),
                        )
                      else
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => DevModePanel(
                                  initialModelPath: widget.initialModelPath,
                                ),
                              ),
                            );
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bug_report),
                              SizedBox(width: 8),
                              Text('Open FFI Debug Tools'),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('App Name', 'Offline Meeting Summarizer'),
                  _buildInfoRow('Version', '1.0.0'),
                  _buildInfoRow('Build', '1'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
