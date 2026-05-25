import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/models/summary_record.dart';
import 'package:ffi_learn/screens/settings_screen.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/providers/summary_history_provider.dart';
import 'package:ffi_learn/providers/transcription_provider.dart';

/// Main meeting summarizer screen
/// This is the primary UI for recording, transcribing, and summarizing meetings
class MeetingSummarizerScreen extends StatefulWidget {
  final String? initialModelPath;

  const MeetingSummarizerScreen({
    super.key,
    this.initialModelPath,
  });

  @override
  State<MeetingSummarizerScreen> createState() =>
      _MeetingSummarizerScreenState();
}

class _MeetingSummarizerScreenState extends State<MeetingSummarizerScreen> {
  late final TextEditingController _manualTranscriptController;

  @override
  void initState() {
    super.initState();
    _manualTranscriptController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<SummarizationProvider>().loadModel();
    });
  }

  @override
  void dispose() {
    _manualTranscriptController.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    final transcription = context.read<TranscriptionProvider>();
    AppLogger.log('UI', 'Start Meeting tapped');

    // On many devices, speech_to_text and audio recording cannot run together.
    // Prioritize live transcript capture for summarization workflow.
    await transcription.startListening();
    if (!mounted) {
      return;
    }
    if (transcription.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(transcription.errorMessage!)),
      );
      return;
    }
  }

  Future<void> _stopSession() async {
    final transcription = context.read<TranscriptionProvider>();
    AppLogger.log('UI', 'Stop Meeting tapped');

    await transcription.stopListening();
    if (!mounted) {
      return;
    }

    if (transcription.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(transcription.errorMessage!)),
      );
    }
  }

  Future<void> _summarize() async {
    final transcription = context.read<TranscriptionProvider>();
    final summarization = context.read<SummarizationProvider>();
    AppLogger.log('UI', 'Summarize tapped');

    final transcript = transcription.transcript.trim();
    if (transcript.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transcript is empty. Record first.')),
      );
      return;
    }

    await summarization.summarize(transcript);
    if (!mounted) {
      return;
    }

    if (summarization.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(summarization.errorMessage!)),
      );
    }
  }

  Future<void> _saveSummary() async {
    final transcription = context.read<TranscriptionProvider>();
    final summarization = context.read<SummarizationProvider>();
    final history = context.read<SummaryHistoryProvider>();

    AppLogger.log('UI', 'Save Summary tapped');
    if (!summarization.hasSummary) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No summary to save yet.')),
      );
      return;
    }

    await history.add(
      transcript: transcription.transcript,
      summary: summarization.summary,
      duration: Duration.zero,
    );

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Summary saved locally.')),
    );
  }

  void _showHistorySheet(List<SummaryRecord> items) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Summary History',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDateTime(item.createdAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.summary,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final h = dateTime.hour.toString().padLeft(2, '0');
    final min = dateTime.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting Summarizer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    initialModelPath: widget.initialModelPath,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Recording Section
            Consumer<TranscriptionProvider>(
              builder: (context, transcription, _) {
                final isListening = transcription.isListening;
                final statusLabel = switch (transcription.status) {
                  TranscriptionStatus.idle => 'Ready to capture speech',
                  TranscriptionStatus.listening => 'Listening in progress',
                  TranscriptionStatus.stopped => 'Capture stopped',
                  TranscriptionStatus.error => 'Capture error',
                };

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recording',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isListening ? Colors.greenAccent : Colors.grey,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isListening ? Icons.mic : Icons.mic_none,
                                  size: 32,
                                  color: isListening
                                      ? Colors.greenAccent
                                      : Colors.white70,
                                ),
                                const SizedBox(height: 8),
                                Text(statusLabel),
                                const SizedBox(height: 4),
                                const Text(
                                  'Live transcript mode (mic)',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.mic),
                                label: const Text('Start Meeting'),
                                onPressed: !transcription.isListening
                                    ? _startSession
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.stop),
                                label: const Text('Stop Meeting'),
                                onPressed: transcription.isListening
                                    ? _stopSession
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Transcript Section
            Consumer<TranscriptionProvider>(
              builder: (context, transcription, _) {
                final transcriptText = transcription.transcript.trim();
                final isEmpty = transcriptText.isEmpty;
                if (_manualTranscriptController.text != transcription.transcript) {
                  _manualTranscriptController
                    ..text = transcription.transcript
                    ..selection = TextSelection.collapsed(
                      offset: transcription.transcript.length,
                    );
                }
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Transcript',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              transcription.isListening ? 'Listening...' : 'Stopped',
                              style: TextStyle(
                                fontSize: 12,
                                color: transcription.isListening
                                    ? Colors.greenAccent
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          constraints: const BoxConstraints(minHeight: 120),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isEmpty
                                ? 'Transcript will appear here while you speak...'
                                : transcriptText,
                            style: TextStyle(
                              color: isEmpty ? Colors.grey : Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _manualTranscriptController,
                          minLines: 2,
                          maxLines: 5,
                          onChanged: transcription.setManualTranscript,
                          decoration: const InputDecoration(
                            labelText: 'Manual transcript (fallback)',
                            hintText: 'Type or paste meeting transcript here...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (transcription.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Transcription error: ${transcription.errorMessage}',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Summary Section
            Consumer2<SummarizationProvider, TranscriptionProvider>(
              builder: (context, summarization, transcription, _) {
                final summaryText = summarization.summary.trim();
                final isSummaryEmpty = summaryText.isEmpty;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Summary',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (summarization.isGenerating)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          summarization.isLoadingModel
                              ? 'Model loading...'
                              : (summarization.isModelLoaded
                                    ? 'Model ready'
                                    : 'Model not loaded'),
                          style: TextStyle(
                            fontSize: 12,
                            color: summarization.isModelLoaded
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          constraints: const BoxConstraints(minHeight: 150),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isSummaryEmpty
                                ? 'Summary will appear here...'
                                : summaryText,
                            style: TextStyle(
                              color: isSummaryEmpty ? Colors.grey : Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: transcription.hasTranscript &&
                                        !summarization.isGenerating
                                    ? _summarize
                                    : null,
                                child: const Text('Summarize'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (summarization.isGenerating)
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: const Text('Cancel'),
                                  onPressed: () => context
                                      .read<SummarizationProvider>()
                                      .cancelGeneration(),
                                ),
                              )
                            else
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: summarization.hasSummary &&
                                          !summarization.isGenerating
                                      ? _saveSummary
                                      : null,
                                  child: const Text('Save'),
                                ),
                              ),
                          ],
                        ),
                        if (summarization.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Summary error: ${summarization.errorMessage}',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // History Section
            Consumer<SummaryHistoryProvider>(
              builder: (context, history, _) {
                final topItems = history.items.take(3).toList();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Recent Summaries',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: history.items.isNotEmpty
                                      ? () => _showHistorySheet(history.items)
                                      : null,
                                  child: const Text('View All'),
                                ),
                                IconButton(
                                  onPressed: history.items.isNotEmpty
                                      ? history.clearAll
                                      : null,
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Clear history',
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (topItems.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No summaries yet',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else
                          ...topItems.map((item) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatDateTime(item.createdAt),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.summary,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          }),
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
}
