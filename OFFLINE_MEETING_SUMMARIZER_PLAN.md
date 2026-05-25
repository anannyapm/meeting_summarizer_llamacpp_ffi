# Offline Meeting Summarizer - Implementation Plan

**Project**: Convert FFI Chat App → Production Offline Meeting Summarizer  
**Architecture**: Provider (lightweight, simple)  
**Timeline**: Incremental phases with clear architecture  
**Constraints**: No cloud services, fully local inference, battery-efficient

---

## 1. Architecture Overview

### 1.1 Core Layers

```
┌─────────────────────────────────────────┐
│       Presentation Layer (UI)           │
│  ┌──────────────────────────────────────┤
│  │ • MeetingSummarizer Screen (main)    │
│  │ • Settings Screen (dev tools hidden) │
│  │ • Recording Controls UI              │
│  │ • Summary Display                    │
└──────────────────────────────────────────┘
         ↑                    ↓
┌─────────────────────────────────────────┐
│    State Management Layer (Providers)   │
│  ┌──────────────────────────────────────┤
│  │ • RecordingProvider (audio state)    │
│  │ • TranscriptionProvider (STT)        │
│  │ • SummarizationProvider (LLM)        │
│  │ • SettingsProvider (dev mode)        │
│  │ • SummaryProvider (history)          │
└──────────────────────────────────────────┘
         ↑                    ↓
┌─────────────────────────────────────────┐
│    Service Layer (Business Logic)       │
│  ┌──────────────────────────────────────┤
│  │ • RecordingService                   │
│  │ • TranscriptionService               │
│  │ • SummarizationService (FFI bridge)  │
│  │ • StorageService                     │
└──────────────────────────────────────────┘
         ↑                    ↓
┌─────────────────────────────────────────┐
│    Infrastructure Layer                 │
│  ┌──────────────────────────────────────┤
│  │ • Audio Recording (record plugin)    │
│  │ • STT (speech_to_text, on-device)    │
│  │ • Native FFI Bridge (llama.cpp)      │
│  │ • File Storage & Hive DB             │
└──────────────────────────────────────────┘
```

### 1.2 Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **No Cloud STT** | Use on-device speech_to_text (offline, free) |
| **Local Summarization** | Use llama.cpp with TinyLlama for fast summarization |
| **Isolate-based Inference** | Prevent UI blocking during generation |
| **Developer Mode** | Move experimental UI behind settings toggle |
| **Provider Architecture** | Lightweight, easy to understand for small apps |

---

## 2. Feature Requirements

### 2.1 Meeting Summarizer Features

**Core MVP:**
- [x] Start/Stop recording audio
- [ ] Real-time transcription from audio
- [ ] Local summarization of full transcript
- [ ] Display summary with key points
- [ ] Save summaries locally (with timestamp)
- [ ] View summary history

**Advanced (Phase 2+):**
- [ ] Export summaries (PDF, text)
- [ ] Meeting metadata (duration, participants, date)
- [ ] Custom summarization prompts
- [ ] Multiple summary styles (bullet points, paragraph, executive brief)
- [ ] Search summaries by keyword

### 2.2 Developer Mode Features

**Current UI Access:**
- Toggle to show original FFI debug interface
- Settings for:
  - Model selection
  - Inference parameters (context, temperature, etc.)
  - FFI debugging info
  - Native bridge logging

---

## 3. New Dependencies

### Required Packages

```yaml
# State Management
provider: ^6.2.0  # Lightweight state management

# Audio Recording
record: ^5.1.0  # Platform-independent audio recording

# Speech-to-Text (On-Device)
speech_to_text: ^6.6.0  # With offline model support
audio_session: ^0.1.14  # Audio session management

# Utilities
intl: ^0.19.0  # Date/time formatting
uuid: ^4.0.0  # Unique ID generation

# Data & Storage
hive: ^2.2.0  # Local database for summaries
hive_flutter: ^1.1.0

dev_dependencies:
  build_runner: ^2.4.0  # For hive code generation
  hive_generator: ^2.1.0  # Hive model generation
```

### Installation Steps

```bash
flutter pub add provider record audio_session speech_to_text intl uuid hive hive_flutter
flutter pub add --dev build_runner hive_generator
```

---

## 4. Project Structure

```
lib/
├── main.dart                           # Entry point → App widget
├── app.dart                            # App widget with theme
│
├── services/
│   ├── recording_service.dart          # Audio recording logic
│   ├── transcription_service.dart      # STT logic
│   ├── summarization_service.dart      # LLM inference (uses FFI)
│   └── storage_service.dart            # Hive + File storage
│
├── providers/
│   ├── recording_provider.dart         # Recording state
│   ├── transcription_provider.dart     # STT state
│   ├── summarization_provider.dart     # LLM state
│   ├── summary_provider.dart           # Summary history state
│   └── settings_provider.dart          # Dev mode & settings
│
├── models/
│   ├── meeting_summary.dart            # Summary data model
│   └── recording_session.dart          # Recording session data
│
├── screens/
│   ├── meeting_summarizer_screen.dart  # Main recording → summarization
│   ├── summary_history_screen.dart     # View past summaries
│   ├── summary_detail_screen.dart      # View single summary
│   └── settings_screen.dart            # Settings + dev mode toggle
│
├── widgets/
│   ├── recording_controls.dart         # Record/Stop buttons
│   ├── transcript_display.dart         # Live transcript view
│   ├── summary_display.dart            # Summary output
│   ├── summary_card.dart               # Summary list item
│   ├── audio_waveform.dart             # Visual audio indicator
│   └── dev_mode_panel.dart             # Debug UI (conditional)
│
└── native/
    └── (existing FFI bridge files)
    ├── native_bridge.dart
    ├── native_bridge_worker.dart
    └── ...
```

---

## 5. Implementation Phases

### Phase 1: Developer Mode Infrastructure (2-3 days)
**Goal**: Move existing UI behind dev toggle

**Tasks**:
1. Create `SettingsProvider` (manage dev mode toggle + settings)
2. Create `settings_screen.dart` with dev mode toggle
3. Move `homepage.dart` → `dev_mode_panel.dart` widget
4. Update `main.dart` to conditionally show dev panel

**Files to Create**:
- `lib/providers/settings_provider.dart` - Dev mode state
- `lib/screens/settings_screen.dart` - Settings UI with toggle
- `lib/widgets/dev_mode_panel.dart` - Debug UI (from homepage)

**Files to Modify**:
- `lib/main.dart` - Add provider setup
- `lib/homepage.dart` → refactor into settings screen

---

### Phase 2: Audio Recording (3-4 days)
**Goal**: Capture audio from device microphone

**Tasks**:
1. Add `record` package, handle permissions (Android/iOS)
2. Create `RecordingService` (file-based storage, start/stop/pause)
3. Create `RecordingProvider` (exposes recording state)
4. Build `RecordingControls` + `AudioWaveform` widgets
5. Create `MeetingSummarizerScreen` main UI

**Files to Create**:
- `lib/services/recording_service.dart`
- `lib/providers/recording_provider.dart`
- `lib/screens/meeting_summarizer_screen.dart`
- `lib/widgets/recording_controls.dart`
- `lib/widgets/audio_waveform.dart`
- `lib/models/recording_session.dart`

---

### Phase 3: On-Device Speech-to-Text (4-5 days)
**Goal**: Convert audio to text locally

**Tasks**:
1. Add `speech_to_text` package
2. Create `TranscriptionService` (calls speech_to_text on recorded audio)
3. Create `TranscriptionProvider` (manages STT state, streams text updates)
4. Build `TranscriptDisplay` widget (shows live transcript)
5. Integrate into `MeetingSummarizerScreen`

**Files to Create**:
- `lib/services/transcription_service.dart`
- `lib/providers/transcription_provider.dart`
- `lib/widgets/transcript_display.dart`

---

### Phase 4: Local Summarization via llama.cpp (4-5 days)
**Goal**: Summarize transcript using on-device LLM

**Tasks**:
1. Create `SummarizationService` (wraps FFI bridge worker)
2. Create `SummarizationProvider` (manages LLM state, streams summary tokens)
3. Implement prompt templates for summarization
4. Build `SummaryDisplay` widget (shows streaming summary)
5. Add error handling for model not loaded
6. Integrate into `MeetingSummarizerScreen`

**Files to Create**:
- `lib/services/summarization_service.dart` - Calls NativeBridgeWorkerClient
- `lib/providers/summarization_provider.dart`
- `lib/widgets/summary_display.dart`
- `lib/models/meeting_summary.dart` - Data model

---

### Phase 5: Summary Storage & History (2-3 days)
**Goal**: Persist summaries locally

**Tasks**:
1. Setup Hive local database
2. Create `StorageService` (save/load summaries)
3. Create `SummaryProvider` (history + search)
4. Build `SummaryHistoryScreen` + `SummaryDetailScreen`
5. Build `SummaryCard` widget for list display

**Files to Create**:
- `lib/services/storage_service.dart`
- `lib/providers/summary_provider.dart`
- `lib/screens/summary_history_screen.dart`
- `lib/screens/summary_detail_screen.dart`
- `lib/widgets/summary_card.dart`

---

### Phase 6: Polish & Production Readiness (3-4 days)
**Goal**: Production-quality app

**Tasks**:
1. Error handling + user feedback
2. Battery optimization (audio processing)
3. Memory management during long recordings
4. UI polish and animations
5. Testing (unit + widget tests)

---

## 6. Provider Architecture Details

### RecordingProvider

```dart
class RecordingProvider extends ChangeNotifier {
  final RecordingService _service;
  
  // State
  RecordingState _state = RecordingState.idle;
  String? _currentFilePath;
  Duration _duration = Duration.zero;
  
  // Getters
  RecordingState get state => _state;
  String? get currentFilePath => _currentFilePath;
  Duration get duration => _duration;
  bool get isRecording => _state == RecordingState.recording;
  
  // Methods
  Future<void> startRecording() async {
    _state = RecordingState.recording;
    notifyListeners();
    try {
      final path = await _service.startRecording();
      _currentFilePath = path;
      // Timer for duration tracking
      _startDurationTimer();
    } catch (e) {
      _state = RecordingState.error;
      notifyListeners();
    }
  }
  
  Future<String?> stopRecording() async {
    _state = RecordingState.idle;
    notifyListeners();
    try {
      return await _service.stopRecording();
    } catch (e) {
      _state = RecordingState.error;
      notifyListeners();
      return null;
    }
  }
}

enum RecordingState { idle, recording, paused, error }
```

### TranscriptionProvider

```dart
class TranscriptionProvider extends ChangeNotifier {
  final TranscriptionService _service;
  
  // State
  TranscriptionState _state = TranscriptionState.idle;
  String _transcript = '';
  String _error = '';
  
  // Getters
  TranscriptionState get state => _state;
  String get transcript => _transcript;
  bool get isTranscribing => _state == TranscriptionState.transcribing;
  
  // Methods
  Future<void> transcribeAudio(String filePath) async {
    _state = TranscriptionState.transcribing;
    _transcript = '';
    notifyListeners();
    
    try {
      await for (final partialText in _service.transcribe(filePath)) {
        _transcript = partialText;
        notifyListeners();
      }
      _state = TranscriptionState.done;
      notifyListeners();
    } catch (e) {
      _state = TranscriptionState.error;
      _error = e.toString();
      notifyListeners();
    }
  }
}

enum TranscriptionState { idle, transcribing, done, error }
```

### SummarizationProvider

```dart
class SummarizationProvider extends ChangeNotifier {
  final SummarizationService _service;
  
  // State
  SummarizationState _state = SummarizationState.idle;
  String _summary = '';
  String _error = '';
  
  // Getters
  SummarizationState get state => _state;
  String get summary => _summary;
  bool get isSummarizing => _state == SummarizationState.summarizing;
  
  // Methods
  Future<void> summarizeTranscript(String transcript) async {
    _state = SummarizationState.summarizing;
    _summary = '';
    notifyListeners();
    
    try {
      await for (final token in _service.summarize(transcript)) {
        _summary += token;
        notifyListeners();
      }
      _state = SummarizationState.done;
      notifyListeners();
    } catch (e) {
      _state = SummarizationState.error;
      _error = e.toString();
      notifyListeners();
    }
  }
}

enum SummarizationState { idle, summarizing, done, error }
```

---

## 7. Data Flow Diagrams

### Meeting Recording → Summarization Flow

```
┌──────────────────┐
│  Start Recording │
└────────┬─────────┘
         ↓
┌──────────────────────────────┐
│ RecordingProvider emits      │
│ state change (recording)     │
│ saves audio file path        │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ User speaks into microphone  │
│ Audio PCM saved to file      │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Stop Recording               │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ RecordingProvider.          │
│ stopRecording() called       │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ TranscriptionProvider        │
│ transcribeAudio(filePath)    │
│ starts STT processing        │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ speech_to_text package       │
│ streams partial text updates │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ TranscriptionProvider        │
│ updates _transcript field    │
│ notifyListeners() called     │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ UI rebuilds with live        │
│ transcript as it arrives     │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Transcription complete       │
│ User taps "Summarize"        │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ SummarizationProvider        │
│ summarizeTranscript()        │
│ passes to NativeBridgeWorker │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ NativeBridgeWorkerClient     │
│ calls llama.cpp via FFI      │
│ streams generated tokens     │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ SummarizationProvider        │
│ accumulates tokens in        │
│ _summary field               │
│ notifyListeners() called     │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ UI rebuilds with streaming   │
│ summary in real-time         │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Summarization complete       │
│ User taps "Save"             │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ StorageService.saveSummary() │
│ persists to Hive database    │
└────────┬─────────────────────┘
         ↓
┌──────────────────────────────┐
│ Summary persisted with:      │
│ - timestamp                  │
│ - transcript                 │
│ - summary text               │
│ - metadata                   │
└──────────────────────────────┘
```

---

## 7. Error Handling Strategy

| Error | Cause | Recovery |
|-------|-------|----------|
| Microphone permission denied | User rejected | Show settings prompt |
| Audio file too large | Long meeting | Split into chunks, process sequentially |
| STT failed | Speech unclear | Retry or manual input option |
| Model not loaded | FFI bridge issue | Show error, retry model load |
| Summarization timeout | LLM inference slow | Show partial summary, retry |
| Storage full | Device capacity | Clean old summaries, warn user |
| Speech data corrupted | File I/O error | Show error, delete corrupted file |

---

## 8. Testing Strategy

### Unit Tests (Use Cases & Repositories)
- `test/features/meeting_summarizer/domain/usecases/`
- Mock all repositories and data sources
- Test success and failure paths

### BLoC Tests
- `test/features/meeting_summarizer/presentation/bloc/`
- Test state emissions using `bloc_test`
- Test event handling and error states

### Widget Tests
- `test/features/meeting_summarizer/presentation/widgets/`
- Test UI rendering with mock BLoCs
- Test user interactions (buttons, inputs)

### Integration Tests
- `integration_test/`
- End-to-end flow: Record → Transcribe → Summarize → Save
- Test on physical device/emulator

---

## 9. Error Handling Strategy

| Error | Cause | Recovery |
|-------|-------|----------|
| Microphone permission denied | User rejected | Show settings prompt |
| Audio file too large | Long meeting | Split into chunks, process sequentially |
| STT failed | Speech unclear | Retry or manual input option |
| Model not loaded | FFI bridge issue | Show error, retry model load |
| Summarization timeout | LLM inference slow | Show partial summary, retry |
| Storage full | Device capacity | Clean old summaries, warn user |
| Speech data corrupted | File I/O error | Show error, delete corrupted file |

---

## 10. Testing Strategy

### Unit Tests (Services)
- `test/services/recording_service_test.dart`
- `test/services/transcription_service_test.dart`
- `test/services/summarization_service_test.dart`
- `test/services/storage_service_test.dart`

### Provider Tests
- `test/providers/recording_provider_test.dart`
- `test/providers/transcription_provider_test.dart`
- `test/providers/summarization_provider_test.dart`

### Widget Tests
- `test/widgets/recording_controls_test.dart`
- `test/widgets/transcript_display_test.dart`
- `test/widgets/summary_display_test.dart`

### Integration Tests
- `integration_test/meeting_flow_test.dart`
- End-to-end: Record → Transcribe → Summarize → Save
- Test on physical device/emulator

---

## 11. Migration Checklist

- [ ] Add provider package to pubspec.yaml
- [ ] Create services layer (Recording, Transcription, Summarization, Storage)
- [ ] Create providers layer (expose state to UI)
- [ ] Move existing UI to dev_mode_panel (behind toggle)
- [ ] Create SettingsProvider and Settings Screen
- [ ] Implement audio recording feature
- [ ] Implement transcription feature
- [ ] Implement summarization feature (integrate FFI)
- [ ] Implement summary storage & history
- [ ] Add error handling throughout
- [ ] Polish UI/UX
- [ ] Write tests
- [ ] Document provider usage
- [ ] Build and test on Android emulator
- [ ] Build and test on iOS simulator
- [ ] Optimize memory/battery usage

---

## 12. Known Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| STT accuracy varies by language/accent | User frustration | Provide manual transcript editing |
| Long recordings → high memory usage | App crash | Implement chunked processing |
| LLM inference takes 30-60s | Poor UX | Show progress, stream tokens |
| Model not bundled (size) | Network dependency | Pre-download in background |
| Provider rebuild performance | UI jank if state changes often | Use `Selector` for granular rebuilds |
| iOS implementation pending | Feature parity delay | Keep Android-first, iOS follow-up |

---

## 13. Timeline

| Phase | Feature | Duration | Status |
|-------|---------|----------|--------|
| 1 | Developer Mode + Settings | 2-3 days | Ready to start |
| 2 | Audio Recording | 3-4 days | After Phase 1 |
| 3 | Speech-to-Text | 4-5 days | After Phase 2 |
| 4 | Local Summarization | 4-5 days | After Phase 3 |
| 5 | Storage & History | 2-3 days | After Phase 4 |
| 6 | Polish & Testing | 3-4 days | After Phase 5 |
| **Total** | **MVP Complete** | **3-4 weeks** | |

---

## 14. Success Criteria

✅ **Phase Complete When:**
1. Feature implemented and compiles
2. No lint errors (flutter analyze)
3. No debug console errors
4. Unit tests pass (if applicable)
5. Manual testing on Android emulator succeeds
6. Code follows Provider pattern for state management
7. Memory usage stays under 200MB during operation
8. No native crashes (segfaults)

---

## 15. Quick Provider Tips

### Using Providers in Widgets

```dart
// Read state (one-time)
context.read<RecordingProvider>().startRecording();

// Listen to state changes
context.watch<RecordingProvider>().isRecording;

// Selective rebuild (only when specific field changes)
Selector<RecordingProvider, bool>(
  selector: (_, provider) => provider.isRecording,
  builder: (_, isRecording, __) {
    return Text(isRecording ? 'Recording...' : 'Ready');
  },
);

// Access multiple providers
final recording = context.watch<RecordingProvider>();
final transcription = context.watch<TranscriptionProvider>();
```

### Setting up Providers in main.dart

```dart
void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => RecordingProvider(RecordingService())),
        ChangeNotifierProvider(create: (_) => TranscriptionProvider(TranscriptionService())),
        ChangeNotifierProvider(create: (_) => SummarizationProvider(SummarizationService())),
        ChangeNotifierProvider(create: (_) => SummaryProvider(StorageService())),
      ],
      child: const App(),
    ),
  );
}
```

---

## Appendix: Reference Materials

- [Provider Package Docs](https://pub.dev/packages/provider)
- [ChangeNotifier & ChangeNotifierProvider](https://pub.dev/documentation/provider/latest/provider/ChangeNotifierProvider-class.html)
- [record Package](https://pub.dev/packages/record)
- [speech_to_text Package](https://pub.dev/packages/speech_to_text)
- [Hive Database](https://docs.hivedb.dev/)

---

**Next Steps**: 
1. Review this plan
2. Begin Phase 1 implementation
3. Commit changes to git with clear messages

