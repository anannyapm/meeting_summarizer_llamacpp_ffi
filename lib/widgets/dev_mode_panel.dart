import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ffi_learn/providers/settings_provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/widgets/ffi_debug_console.dart';

/// Developer mode debug panel with the full FFI debugging console.
class DevModePanel extends StatelessWidget {
  const DevModePanel({
    super.key,
    this.initialModelPath,
  });

  final String? initialModelPath;

  @override
  Widget build(BuildContext context) {
    final modelPath =
        initialModelPath ?? context.watch<SettingsProvider>().resolvedModelPath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Tools - FFI Debug'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Consumer<SummarizationProvider>(
              builder: (context, summarization, _) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Meeting Summarizer Bridge',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStatusRow(
                          'Model Loaded',
                          summarization.isModelLoaded ? 'Yes' : 'No',
                        ),
                        _buildStatusRow(
                          'Model Loading',
                          summarization.isLoadingModel ? 'Yes' : 'No',
                        ),
                        if (summarization.currentModelPath != null)
                          _buildStatusRow(
                            'Model Path',
                            summarization.currentModelPath!,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Isolated FFI Console',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FfiDebugConsole(initialModelPath: modelPath),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
