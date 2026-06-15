import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ffi_learn/core/app_logger.dart';
import 'package:ffi_learn/core/app_theme.dart';
import 'package:ffi_learn/models/summary_record.dart';
import 'package:ffi_learn/screens/settings_screen.dart';
import 'package:ffi_learn/providers/recording_provider.dart';
import 'package:ffi_learn/providers/summarization_provider.dart';
import 'package:ffi_learn/providers/summary_history_provider.dart';
import 'package:ffi_learn/providers/transcription_provider.dart';

enum _CaptureMode { liveMic, recordAndTranscribe }

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
  _CaptureMode _captureMode = _CaptureMode.liveMic;

  @override
  void initState() {
    super.initState();
    _manualTranscriptController = TextEditingController();
    // Model is loaded during game splash; loadModel here is a no-op if already warm.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final summarization = context.read<SummarizationProvider>();
      if (!summarization.isModelLoaded &&
          widget.initialModelPath != null &&
          widget.initialModelPath!.isNotEmpty) {
        summarization.loadModel();
      }
    });
  }

  @override
  void dispose() {
    _manualTranscriptController.dispose();
    super.dispose();
  }

  Future<void> _startLiveSession() async {
    final transcription = context.read<TranscriptionProvider>();
    AppLogger.log('UI', 'Start live mic session');
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

  Future<void> _stopLiveSession() async {
    final transcription = context.read<TranscriptionProvider>();
    AppLogger.log('UI', 'Stop live mic session');
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

  Future<void> _startRecording() async {
    final recording = context.read<RecordingProvider>();
    AppLogger.log('UI', 'Start recording');
    await recording.startRecording();
    if (!mounted) {
      return;
    }
    if (recording.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(recording.errorMessage!)),
      );
    }
  }

  Future<void> _stopRecordingAndTranscribe() async {
    final recording = context.read<RecordingProvider>();
    final transcription = context.read<TranscriptionProvider>();
    AppLogger.log('UI', 'Stop recording and transcribe');

    final path = await recording.stopRecording();
    if (!mounted) {
      return;
    }
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recording saved.')),
      );
      return;
    }

    await transcription.transcribeRecordingFile(path);
    if (!mounted) {
      return;
    }
    if (transcription.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(transcription.errorMessage!)),
      );
    } else if (transcription.hasTranscript) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording transcribed on-device.')),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Summary History',
                  style: AppTheme.sectionTitle(context).copyWith(fontSize: 18),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 20,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.summarize_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          _formatDateTime(item.createdAt),
                          style: AppTheme.captionMuted(context),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            item.summary,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
          Consumer<SummarizationProvider>(
            builder: (context, summarization, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: _ModelStatusChip(
                    isLoaded: summarization.isModelLoaded,
                    isGenerating: summarization.isGenerating,
                    phase: summarization.phase,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCaptureSection(context),
          const SizedBox(height: 16),
          _buildTranscriptSection(context),
          const SizedBox(height: 16),
          _buildSummarySection(context),
          const SizedBox(height: 16),
          _buildHistorySection(context),
        ],
      ),
    );
  }

  Widget _buildCaptureSection(BuildContext context) {
    return _SectionCard(
      icon: Icons.mic_none_outlined,
      title: 'Capture',
      subtitle: 'Live mic or record, then transcribe on-device',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_CaptureMode>(
            segments: const [
              ButtonSegment(
                value: _CaptureMode.liveMic,
                label: Text('Live mic'),
                icon: Icon(Icons.mic, size: 18),
              ),
              ButtonSegment(
                value: _CaptureMode.recordAndTranscribe,
                label: Text('Record'),
                icon: Icon(Icons.fiber_manual_record, size: 18),
              ),
            ],
            selected: <_CaptureMode>{_captureMode},
            onSelectionChanged: (selection) {
              setState(() => _captureMode = selection.first);
            },
          ),
          const SizedBox(height: 16),
          if (_captureMode == _CaptureMode.liveMic)
            _buildLiveMicCapture(context)
          else
            _buildRecordCapture(context),
        ],
      ),
    );
  }

  Widget _buildLiveMicCapture(BuildContext context) {
    return Consumer<TranscriptionProvider>(
      builder: (context, transcription, _) {
        final isListening = transcription.isListening;

        final statusLabel = switch (transcription.status) {
          TranscriptionStatus.idle => 'Ready — tap Start to begin',
          TranscriptionStatus.listening => 'Listening… speak naturally',
          TranscriptionStatus.transcribingFile => 'Transcribing recording…',
          TranscriptionStatus.stopped => 'Session stopped',
          TranscriptionStatus.error => 'Capture error',
        };

        return Column(
          children: [
            _CaptureStatusPanel(
              active: isListening,
              icon: isListening ? Icons.mic : Icons.mic_none_outlined,
              label: statusLabel,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start'),
                    onPressed:
                        !transcription.isListening ? _startLiveSession : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                    onPressed:
                        transcription.isListening ? _stopLiveSession : null,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecordCapture(BuildContext context) {
    return Consumer2<RecordingProvider, TranscriptionProvider>(
      builder: (context, recording, transcription, _) {
        final isRecording = recording.isRecording;
        final isTranscribing = transcription.isTranscribingFile;

        final label = isTranscribing
            ? 'Transcribing with Whisper…'
            : isRecording
                ? 'Recording ${_formatDuration(recording.elapsed)}'
                : 'Record audio, then stop to transcribe';

        return Column(
          children: [
            _CaptureStatusPanel(
              active: isRecording || isTranscribing,
              icon: isRecording
                  ? Icons.fiber_manual_record
                  : Icons.graphic_eq_outlined,
              label: label,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('Record'),
                    onPressed: recording.canStart && !isTranscribing
                        ? _startRecording
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.transcribe),
                    label: const Text('Stop & Transcribe'),
                    onPressed: recording.canStop && !isTranscribing
                        ? _stopRecordingAndTranscribe
                        : null,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTranscriptSection(BuildContext context) {
    return Consumer<TranscriptionProvider>(
      builder: (context, transcription, _) {
        if (_manualTranscriptController.text != transcription.transcript) {
          _manualTranscriptController
            ..text = transcription.transcript
            ..selection = TextSelection.collapsed(
              offset: transcription.transcript.length,
            );
        }

        final charCount = transcription.transcript.trim().length;
        final statusText = transcription.isListening
            ? 'Listening'
            : transcription.isTranscribingFile
                ? 'Transcribing'
                : charCount > 0
                    ? '$charCount chars'
                    : 'Empty';

        return _SectionCard(
          icon: Icons.notes_outlined,
          title: 'Transcript',
          subtitle: 'Live text appears here — edit or paste manually',
          trailing: _StatusPill(label: statusText),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _manualTranscriptController,
                minLines: 5,
                maxLines: 8,
                onChanged: transcription.setManualTranscript,
                style: const TextStyle(height: 1.45),
                decoration: const InputDecoration(
                  hintText:
                      'Start capture above, or paste a meeting transcript here…',
                  alignLabelWithHint: true,
                ),
              ),
              if (transcription.errorMessage != null) ...[
                const SizedBox(height: 10),
                _InlineNotice(
                  icon: Icons.warning_amber_rounded,
                  message: transcription.errorMessage!,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummarySection(BuildContext context) {
    return Consumer2<SummarizationProvider, TranscriptionProvider>(
      builder: (context, summarization, transcription, _) {
        final summaryText = summarization.summary.trim();
        final isSummaryEmpty = summaryText.isEmpty;
        final phaseLabel = switch (summarization.phase) {
          SummarizationPhase.loadingModel => 'Loading model',
          SummarizationPhase.prefilling => 'Analyzing',
          SummarizationPhase.streaming => 'Writing',
          SummarizationPhase.done => 'Done',
          SummarizationPhase.error => 'Error',
          SummarizationPhase.idle =>
            summarization.isModelLoaded ? 'Ready' : 'Model offline',
        };

        return _SectionCard(
          icon: Icons.auto_awesome_outlined,
          title: 'Summary',
          subtitle: 'On-device AI — streams token by token',
          trailing: summarization.isGenerating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _StatusPill(label: phaseLabel),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (summarization.isSlowModelForMobile &&
                  summarization.isModelLoaded)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: _InlineNotice(
                    icon: Icons.speed_outlined,
                    message:
                        'Tip: Llama 3.2 1B or SmolLM2 360M are faster in Settings.',
                  ),
                ),
              if (summarization.wasTranscriptTruncated)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _InlineNotice(
                    icon: Icons.content_cut_outlined,
                    message:
                        'Transcript trimmed to ~${summarization.maxTranscriptChars} '
                        'chars for on-device speed.',
                  ),
                ),
              Container(
                constraints: const BoxConstraints(minHeight: 140),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: isSummaryEmpty && summarization.isPrefilling
                    ? Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Analyzing transcript…',
                            style: AppTheme.captionMuted(context),
                          ),
                        ],
                      )
                    : SelectableText(
                        isSummaryEmpty
                            ? 'Your summary will appear here after you tap Summarize.'
                            : summaryText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                              color: isSummaryEmpty
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                  : null,
                            ),
                      ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  summarization.isGenerating ? 'Summarizing…' : 'Summarize',
                ),
                onPressed: transcription.hasTranscript &&
                        !summarization.isGenerating
                    ? _summarize
                    : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
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
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bookmark_outline),
                        label: const Text('Save summary'),
                        onPressed: summarization.hasSummary &&
                                !summarization.isGenerating
                            ? _saveSummary
                            : null,
                      ),
                    ),
                ],
              ),
              if (summarization.errorMessage != null) ...[
                const SizedBox(height: 10),
                _InlineNotice(
                  icon: Icons.error_outline,
                  message: summarization.errorMessage!,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistorySection(BuildContext context) {
    return Consumer<SummaryHistoryProvider>(
      builder: (context, history, _) {
        final topItems = history.items.take(3).toList();
        return _SectionCard(
          icon: Icons.history,
          title: 'Recent summaries',
          subtitle: history.items.isEmpty
              ? 'Saved summaries appear here'
              : '${history.items.length} saved locally',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: history.items.isNotEmpty
                    ? () => _showHistorySheet(history.items)
                    : null,
                child: const Text('View all'),
              ),
              IconButton(
                onPressed: history.items.isNotEmpty ? history.clearAll : null,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Clear history',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          child: topItems.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No summaries yet — generate one above and tap Save.',
                    style: AppTheme.captionMuted(context),
                  ),
                )
              : Column(
                  children: topItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDateTime(item.createdAt),
                              style: AppTheme.captionMuted(context),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.summary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTheme.sectionTitle(context)),
                      if (subtitle case final subtitle?) ...[
                        const SizedBox(height: 2),
                        Text(subtitle, style: AppTheme.captionMuted(context)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      labelStyle: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _ModelStatusChip extends StatelessWidget {
  const _ModelStatusChip({
    required this.isLoaded,
    required this.isGenerating,
    required this.phase,
  });

  final bool isLoaded;
  final bool isGenerating;
  final SummarizationPhase phase;

  @override
  Widget build(BuildContext context) {
    final label = switch ((isGenerating, isLoaded, phase)) {
      (true, _, SummarizationPhase.streaming) => 'Writing',
      (true, _, SummarizationPhase.prefilling) => 'Analyzing',
      (true, _, _) => 'Busy',
      (_, true, _) => 'AI ready',
      _ => 'Offline',
    };

    return _StatusPill(label: label);
  }
}

class _CaptureStatusPanel extends StatelessWidget {
  const _CaptureStatusPanel({
    required this.active,
    required this.icon,
    required this.label,
  });

  final bool active;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 88,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 24,
            color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: active
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
