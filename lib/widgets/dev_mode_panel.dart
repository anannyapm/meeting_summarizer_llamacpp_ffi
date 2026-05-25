import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';

/// Developer mode debug panel - wraps the existing FFI debugging UI
/// This was previously the main HomePage, now hidden behind dev mode toggle
class DevModePanel extends StatefulWidget {
  final String? initialModelPath;

  const DevModePanel({
    super.key,
    this.initialModelPath,
  });

  @override
  State<DevModePanel> createState() => _DevModePanelState();
}

class _DevModePanelState extends State<DevModePanel> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Tools - FFI Debug'),
        backgroundColor: Colors.deepOrange,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Developer Mode Panel',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This panel contains the original FFI debugging interface. '
                      'You can test the native bridge here.',
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'FFI Debug Tools - Coming from homepage.dart',
                            ),
                          ),
                        );
                      },
                      child: const Text('Test FFI Bridge'),
                    ),
                    const SizedBox(height: 16),
                    if (widget.initialModelPath != null)
                      Text(
                        'Model Path: ${widget.initialModelPath}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Consumer<SummarizationProvider>(
              builder: (context, summarization, _) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FFI Bridge Status',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStatusRow('Bridge Version', 'ffi-bridge-phase8'),
                        _buildStatusRow(
                          'Model Loaded',
                          summarization.isModelLoaded ? 'Yes' : 'No',
                        ),
                        _buildStatusRow(
                          'Model Loading',
                          summarization.isLoadingModel ? 'Yes' : 'No',
                        ),
                        _buildStatusRow('GPU Acceleration', 'Available'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}
