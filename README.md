# Offline Meeting Summarizer (Dart FFI + llama.cpp)

A Flutter proof-of-concept that runs **local LLM inference on-device** using **Dart FFI** and a custom **C++ bridge** around [llama.cpp](https://github.com/ggml-org/llama.cpp). The app records or accepts meeting transcripts, transcribes speech on-device, and streams an AI-generated summary token-by-token—without sending data to a remote server.

---

## Table of contents

- [Why this project exists](#why-this-project-exists)
- [Features](#features)
- [Platform support](#platform-support)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
- [Running the app](#running-the-app)
- [Model management](#model-management)
- [Configuration](#configuration)
- [Native bridge (C ABI)](#native-bridge-c-abi)
- [Dart FFI layer](#dart-ffi-layer)
- [End-to-end flow](#end-to-end-flow)
- [Performance tuning](#performance-tuning)
- [Developer mode](#developer-mode)
- [Troubleshooting](#troubleshooting)
- [Key design decisions](#key-design-decisions)
- [Roadmap](#roadmap)
- [Resources](#resources)

---

## Why this project exists

**Server-based AI** needs connectivity, adds latency, costs money to host, and often sends user data off-device.

**Local AI via llama.cpp** runs GGUF models directly on the phone or desktop:

| Benefit | Description |
|--------|-------------|
| Offline | Inference works without network after the model is present |
| Privacy | Audio and transcripts stay on the device |
| Latency | No round-trip to an API |
| Cost | No inference server to operate |

Flutter is excellent for UI and app logic; it is not built for heavy tensor math. This project follows the standard production pattern:

- **Dart** — UI, state, orchestration
- **C++ (llama.cpp)** — model load, tokenization, inference
- **FFI** — low-overhead calls across the language boundary
- **Isolates** — keep inference off the UI thread

Most pub.dev “llama” packages hide these layers. This repo shows how to own the bridge, ABI, and lifecycle yourself.

---

## Features

- **Meeting summarizer UI** — record → transcribe → summarize with streaming output
- **On-device speech-to-text** via [`speech_to_text`](https://pub.dev/packages/speech_to_text)
- **Audio recording** via [`record`](https://pub.dev/packages/record)
- **Custom native bridge** (`libllama_bridge.so` on Android) compiled with llama.cpp from source
- **Worker isolate** — `NativeBridgeWorkerClient` runs FFI on a background isolate so the UI stays responsive
- **Token streaming** — C++ callbacks push tokens to Dart as they are generated
- **Model download & caching** — `ModelManager` downloads GGUF files to app documents (no 600MB+ asset bundle required)
- **Multiple model presets** — Llama 3.2 1B, TinyLlama, Qwen2.5, SmolLM2 (see `lib/models/model_presets.dart`)
- **Summary history** — persisted locally with `shared_preferences`
- **Developer mode** — FFI echo/stream tests and bridge diagnostics behind a settings toggle

---

## Platform support

| Platform | Native bridge | LLM inference | Notes |
|----------|---------------|---------------|--------|
| **Android** | ✅ `libllama_bridge.so` | ✅ Primary target | `arm64-v8a` only in `build.gradle.kts` |
| **iOS** | ⚠️ Partial / planned | ⚠️ | `DynamicLibrary.process()` stub in Dart; full iOS bridge not wired in this POC |
| **macOS / Linux / Windows** | ❌ | ❌ | Flutter scaffold present; no llama bridge build for desktop yet |

Treat **Android (physical device or arm64 emulator)** as the supported path for local LLM features.

---

## Architecture

### Layered design

```
┌─────────────────────────────────────────────────────┐
│  Presentation (Flutter widgets)                     │
│  MeetingSummarizerScreen, SettingsScreen, DevMode   │
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│  State (Provider)                                   │
│  Recording, Transcription, Summarization, Settings  │
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│  Services                                         │
│  RecordingService, TranscriptionService,          │
│  SummarizationService                             │
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│  FFI + isolates                                   │
│  NativeBridgeWorkerClient → NativeBridge            │
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│  C++ bridge (llama_bridge.cpp / .h)               │
│  Sessions, status codes, token callbacks            │
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│  llama.cpp + GGUF weights in RAM                  │
└─────────────────────────────────────────────────────┘
```

### Recording → summary pipeline

```
User taps Record
    → RecordingProvider / RecordingService (audio file)
User taps Stop
    → TranscriptionProvider / speech_to_text (transcript text)
User runs Summarize
    → SummarizationProvider
    → SummarizationService
    → NativeBridgeWorkerClient (isolate)
    → bridge_session_load_model + bridge_session_stream
    → Tokens stream to UI via Stream / notifyListeners
```

### Why FFI instead of platform channels?

| Approach | Best for |
|----------|----------|
| **Platform channels** | OS APIs (camera, permissions, billing) |
| **Dart FFI** | Tight loops, large buffers, streaming callbacks, minimal marshalling |

Inference is CPU-heavy and chatty (many small token callbacks). FFI avoids serializing through the platform embedder on every step.

### Why a worker isolate?

`bridge_session_stream` can run for tens of seconds. Running it on the main isolate would freeze frames. `NativeBridgeWorkerClient` owns a dedicated isolate that:

1. Loads `DynamicLibrary` and `NativeBridge` once
2. Handles commands (`loadModel`, `streamEcho`, `abortStream`, …)
3. Forwards tokens to the main isolate via `SendPort` / `StreamController`

---

## Repository layout

```
ffi_learn/
├── lib/
│   ├── main.dart                          # App bootstrap, Provider tree
│   ├── app.dart                           # MaterialApp → MeetingSummarizerScreen
│   ├── model_manager.dart                 # GGUF download, verify, path resolution
│   ├── models/
│   │   ├── model_presets.dart             # Hugging Face URLs + preset IDs
│   │   └── summary_record.dart
│   ├── native/
│   │   ├── native_bridge.dart             # FFI bindings, memory helpers, streaming
│   │   └── native_bridge_worker.dart      # Isolate command protocol
│   ├── providers/                         # ChangeNotifier state
│   ├── services/                          # Recording, STT, summarization
│   ├── screens/                           # Main UI + settings
│   └── widgets/dev_mode_panel.dart        # Low-level FFI debug UI
├── android/
│   ├── app/
│   │   ├── build.gradle.kts               # CMake externalNativeBuild, arm64-v8a
│   │   └── src/main/cpp/CMakeLists.txt    # Includes native bridge
│   └── native/
│       ├── bridge/
│       │   ├── llama_bridge.h             # Stable C ABI
│       │   ├── llama_bridge.cpp           # Session + llama.cpp calls
│       │   └── CMakeLists.txt
│       └── llama.cpp/                     # Git submodule (ggml-org/llama.cpp)
├── pubspec.yaml
├── .gitmodules
└── Building Local LLM's Using Dart FFI...md   # Full tutorial / design doc
```

---

## Prerequisites

1. **Flutter SDK** — stable channel, Dart `^3.11` (see `pubspec.yaml`)
2. **Android toolchain**
   - Android Studio or SDK command-line tools
   - **NDK** (version aligned with Flutter’s `ndkVersion`)
   - CMake (via Android SDK)
3. **Git** — for submodules
4. **Device or emulator** — **arm64** Android (project filters `abiFilters` to `arm64-v8a`)
5. **Disk space** — GGUF models are hundreds of MB to a few GB; plan for download storage under app documents

Optional but useful:

- `adb` for logcat
- Physical phone for realistic inference speed (emulators are slower)

---

## Getting started

### 1. Clone and initialize submodules

`llama.cpp` is vendored as a submodule under `android/native/llama.cpp`.

```bash
git clone <your-repo-url> ffi_learn
cd ffi_learn
git submodule update --init --recursive
```

If `android/native/llama.cpp` is empty, the native build will fail until the submodule is initialized.

### 2. Install Dart dependencies

```bash
flutter pub get
```

### 3. Verify Flutter / Android setup

```bash
flutter doctor -v
```

Resolve any Android licenses or NDK issues before building.

### 4. Download a GGUF model (in-app or manual)

**Recommended (in-app):** Open **Settings**, pick a preset (default: **Llama 3.2 1B Instruct Q4_K_M**), tap download. Files land in:

`<application_documents>/models/<fileName>.gguf`

**Manual (optional):**

```bash
# Example: TinyLlama ~600MB — good for slower devices
curl -L -o tinyllama.gguf \
  "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
```

Copy into the app’s models directory on device, or use Settings to download the matching preset by filename.

Bundling large GGUF files inside `android/app/src/main/assets` is possible but **not required**—this project prefers download-on-first-use.

---

## Running the app

### List devices

```bash
flutter devices
```

### Run on Android (default path)

```bash
flutter run
```

First build compiles `llama.cpp` and `llama_bridge` via CMake; expect several minutes.

### Release build (smoke test)

```bash
flutter run --release
```

### Choose model preset at compile time

```bash
flutter run --dart-define=MODEL_PRESET=tinyllama_1_1b_q4_k_m
```

Valid IDs are defined in `lib/models/model_presets.dart` (`llama3_2_1b_q4_k_m`, `tinyllama_1_1b_q4_k_m`, `qwen2_5_1_5b_q4_k_m`, `smollm2_1_7b_q4_k_m`).

### Watch logs

```bash
flutter logs
# or filter native/model tags:
flutter logs | grep -E 'MODEL|SUMMARIZE|STT|native|UI'
```

Tagged logging uses `lib/core/app_logger.dart`.

---

## Model management

| Preset ID | Model | Approx. size (Q4_K_M) |
|-----------|--------|------------------------|
| `llama3_2_1b_q4_k_m` (default) | Llama 3.2 1B Instruct | ~800MB |
| `tinyllama_1_1b_q4_k_m` | TinyLlama 1.1B Chat | ~600MB |
| `qwen2_5_1_5b_q4_k_m` | Qwen2.5 1.5B Instruct | ~1GB |
| `smollm2_1_7b_q4_k_m` | SmolLM2 1.7B Instruct | ~1GB |

`ModelManager`:

- Downloads to `getApplicationDocumentsDirectory()/models/`
- Reports progress for UI
- Supports optional SHA-256 verification when configured

After download, `SummarizationProvider.loadModel()` loads weights through the native bridge (`bridge_session_load_model`).

---

## Configuration

### Summarization defaults

In `lib/services/summarization_service.dart`:

| Parameter | Default | Effect |
|-----------|---------|--------|
| `nCtx` | `256` | Context window; smaller = faster, may truncate long transcripts |
| `nGpuLayers` | `999` | Offload layers to GPU when available (device-dependent) |

### Android ABI

`android/app/build.gradle.kts` restricts builds to **`arm64-v8a`**. Add other ABIs only if you build and ship matching `.so` libraries.

### Native library name

Dart opens the bridge with:

```dart
DynamicLibrary.open('libllama_bridge.so');  // Android
```

The CMake target `llama_bridge` produces that shared library.

---

## Native bridge (C ABI)

The contract lives in `android/native/bridge/llama_bridge.h`. Dart never sees C++ struct internals—only an opaque `BridgeSession` pointer.

### Ownership rules

- Caller owns input strings passed **into** the bridge.
- Strings allocated **by** the bridge (`*_alloc` functions) must be freed with `bridge_string_free()`.
- Each `bridge_session_create()` must be paired with exactly one `bridge_session_destroy()`.

### Status codes (excerpt)

| Code | Name | Typical cause |
|------|------|----------------|
| 0 | `BRIDGE_STATUS_OK` | Success |
| 1 | `BRIDGE_STATUS_NULL_ARG` | Missing pointer |
| 8 | `BRIDGE_STATUS_MODEL_NOT_LOADED` | Stream before load |
| 9 | `BRIDGE_STATUS_MODEL_LOAD_FAILED` | Bad path or corrupt GGUF |
| 12 | `BRIDGE_STATUS_GENERATION_IN_PROGRESS` | Overlapping stream |
| 13–14 | Tokenize / decode errors | Prompt or model mismatch |

Dart converts non-zero codes to `BridgeNativeException` using `bridge_status_to_cstr()`.

### Core exports

| Function | Purpose |
|----------|---------|
| `bridge_version` | Bridge build identity |
| `bridge_echo_alloc` | Phase-1 string echo (memory test) |
| `bridge_session_create` / `destroy` | Session lifecycle |
| `bridge_session_load_model` / `unload_model` | GGUF load into RAM |
| `bridge_session_stream` | Run inference; `BridgeTokenCallback` per token |
| `bridge_session_abort_stream` | Cooperative cancel from any thread |
| `bridge_session_model_info_alloc` | Debug / UI metadata |

### Building the native piece

CMake chain:

1. `android/app/src/main/cpp/CMakeLists.txt` → adds `android/native/bridge`
2. `android/native/bridge/CMakeLists.txt` → `add_subdirectory(../llama.cpp)` + `add_library(llama_bridge SHARED ...)`

llama.cpp build flags in CMake disable tests, examples, and server to keep compile time reasonable.

---

## Dart FFI layer

| File | Responsibility |
|------|----------------|
| `native_bridge.dart` | `DynamicLibrary` lookup, `calloc`/`malloc` helpers, session API, token callback registry |
| `native_bridge_worker.dart` | Isolate protocol: commands, pending completers, token `Stream`s |
| `summarization_service.dart` | App-facing API: ensure session, load model, `summarizeStream(transcript)` |
| `summarization_provider.dart` | UI state: loading, streaming text, errors, timeouts |

### Phases implemented

1. **Echo alloc** — prove load + malloc/free discipline  
2. **Opaque sessions** — `Pointer<BridgeSessionPointer>`  
3. **Status codes** — no exceptions across the C boundary  
4. **Streaming callbacks** — `@pragma('vm:entry-point')` for C→Dart token delivery  

### Memory pattern (always use `try` / `finally`)

```dart
final inputPtr = transcript.toNativeUtf8();
try {
  // call native
} finally {
  malloc.free(inputPtr);
}
```

---

## End-to-end flow

1. **Launch** — `main.dart` wires `MultiProvider` (settings, recording, transcription, summarization, history).
2. **Settings** — User downloads a GGUF preset; path is stored and passed to `SummarizationService.updateModelPath`.
3. **Meeting screen** — Optional record → STT, or paste transcript manually.
4. **Summarize** — Provider calls service → worker isolate → `bridge_session_stream`.
5. **UI** — Summary `String` grows as tokens arrive; history can persist completed summaries.

Prompt truncation and meeting-specific templates are implemented in the summarization service layer (see tutorial for tuning long transcripts).

---

## Performance tuning

| Knob | Mobile suggestion | Tradeoff |
|------|-------------------|----------|
| Model | TinyLlama or Llama 3.2 1B Q4_K_M | Quality vs speed vs RAM |
| `nCtx` | 128–256 | Lower = faster; may clip long meetings |
| `nGpuLayers` | `999` or tuned layer count | GPU when driver supports it |
| Transcript length | Truncate to last N chars in prompt | Large speedup with small quality loss |
| Lifecycle | `unloadModel()` / `dispose()` when idle | Frees hundreds of MB RAM |

---

## Developer mode

Enable **Developer mode** in **Settings** to open `DevModePanel`:

- Inspect bridge version and llama runtime info  
- Run echo / stream-echo FFI tests without the full meeting flow  
- Validate isolate + callback wiring in isolation  

Use this when changing `llama_bridge.cpp` or `native_bridge.dart` before testing the full summarizer UI.

---

## Troubleshooting

| Symptom | Likely cause | What to try |
|---------|--------------|-------------|
| CMake / NDK build failure | Submodule missing | `git submodule update --init --recursive` |
| `UnsupportedError: Native bridge...` | Running on unsupported OS | Use Android arm64 |
| Crash on model load | Wrong path or incomplete download | Check Settings download status; verify file size |
| No tokens / empty summary | Model not loaded or prompt issue | Logs under `MODEL`; try dev-mode stream echo |
| UI freezes | FFI on main isolate | Confirm `SummarizationService` uses `NativeBridgeWorkerClient` |
| OOM / slow device | Model too large | Switch to `tinyllama_1_1b_q4_k_m`; lower `nCtx` |
| Segfault | FFI memory bug | Audit `calloc`/`malloc`/`bridge_string_free` pairs |
| Emulator unusably slow | x86 vs ARM, no GPU | Prefer physical arm64 device |

---

## Key design decisions

1. **Own the ABI** — Stable C header (`llama_bridge.h`) instead of opaque wrapper packages.  
2. **Status codes, not C++ exceptions** — Mapped to Dart exceptions at the boundary only.  
3. **Opaque session handles** — C++ holds `llama_model`, `llama_context`, mutexes, abort flags.  
4. **Worker isolate** — Required for responsive UI during 30s+ generation.  
5. **Streaming UX** — Token callbacks beat waiting for a full completion string.  
6. **Download models** — Avoid bloating APK/AAB with multi-hundred-MB assets.  

---

## Roadmap

Items called out in the POC / article but not fully implemented here:

- First-class **iOS** bridge packaging (static link + Xcode copy phases)  
- Desktop targets (macOS / Windows) with platform-specific `.dylib` / `.dll`  
- Remote model registry with checksum pinning  
- Custom summarization prompt templates in UI  
- Export / share summaries  
- Built-in performance profiling (tokens/sec, RAM)  

---

## Resources

- [Full project write-up (markdown)](./Building%20Local%20LLM's%20Using%20Dart%20FFI%20And%20Llama%20CPP%20-%20Beyond%20Wrapper%20Packages.md)
- [Dart FFI (C interop)](https://dart.dev/interop/c-interop)
- [llama.cpp](https://github.com/ggml-org/llama.cpp)
- [GGUF format](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md)
- [Flutter platform integration](https://docs.flutter.dev/platform-integration)
- [Provider package](https://pub.dev/packages/provider)
- [Hugging Face GGUF models](https://huggingface.co/models?library=gguf)

---

**Happy building.** For step-by-step FFI phases, CMake snippets, and production lessons learned, start with my article
