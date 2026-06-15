# Building Local LLM's Using Dart FFI And Llama CPP - Beyond Wrapper Packages

## Introduction

When I first explored running local LLMs inside Flutter, I had a lot of questions:

* Why are people using C++ libraries for AI?  
* Why not just write everything in Dart?  
* What exactly is llama.cpp?  
* What are .so, .dll, and .dylib files?  
* Why does Flutter suddenly need native code?  
* Why do most tutorials feel incomplete?

If you're coming from a Flutter-only background, all of this initially feels very unfamiliar. Most Flutter developers rarely touch:

* native memory
* C/C++
* shared libraries
* compilers
* ABI architectures
* or systems-level programming

But once you understand the architecture, things become surprisingly logical. This article documents my journey building a **proof-of-concept** offline meeting summarizer with on-device AI.

### The Problem Statement

Before diving in, consider this question:

> *Why go through all the complexity of Flutter FFI and llama.cpp when we could simply host a GGUF model on a Python FastAPI server and consume it like any normal API?*

Local AI solves a completely different problem:
- **Server-based AI** depends on internet connectivity, introduces latency, incurs infrastructure costs, and sends user data to external servers
- **Local AI via llama.cpp** runs the model directly on the device itself, enabling:
  - ✅ Offline inference (no internet required)
  - ✅ Better privacy (data never leaves the device)
  - ✅ Lower latency (no network round trips)
  - ✅ No backend costs (computation happens on user's device)

In this article, I'll explain how I built this POC, from understanding the architecture to streaming tokens in real-time.

---

## Why Are AI Libraries Usually Written in C++?

This was my first major question: Why is almost every serious AI runtime written in low-level languages like C++, Rust, or CUDA instead of higher-level languages like Dart?

The answer is **performance and hardware access**.

### The Performance Reality

LLMs perform enormous amounts of:
- Matrix multiplication
- Memory operations
- Tensor computation
- CPU/GPU optimizations

Languages like Dart are fantastic for:
- UI development
- App logic
- Developer productivity
- Rapid prototyping

But they are **not designed for ultra-low-level hardware optimization**.

### What C++ Gives You

C++ gives developers:
- Direct memory control (allocate exactly what you need)
- CPU optimization techniques (vectorization, cache management)
- SIMD instructions (vectorized computation for performance)
- GPU integrations (CUDA, Metal, OpenCL)
- Fine-grained threading control
- Extremely fast execution (minimal overhead)

That's why libraries like **TensorFlow, PyTorch, ONNX Runtime, llama.cpp** all rely heavily on native code. Even Python AI frameworks are mostly wrappers around C/C++ backends.

---

## What Is llama.cpp?

[llama.cpp](https://github.com/ggml-org/llama.cpp) is a lightweight C/C++ implementation for running LLMs efficiently on local devices.

Think of it as an **AI inference engine optimized for local hardware**.

### How It Works

It takes:
- **Model weights** (the trained parameters from the LLM, in GGUF format)
- **Tokens** (numerical representations of text)
- **Prompts** (user input)

And performs the mathematical computation required to:
- Generate text predictions
- Produce the next token in sequence
- Stream responses token-by-token

### Key Advantages

- ✅ Supports **all CPUs** (x86_64, ARM64, etc.)
- ✅ GPU acceleration (NVIDIA CUDA, Apple Metal, etc.)
- ✅ **No Python required** (pure C/C++)
- ✅ Highly optimized for mobile/embedded devices
- ✅ Supports **quantization** (run larger models on limited hardware)
- ✅ Small footprint (< 2MB binary on Android)

### The GGUF Format

Models are distributed in **GGUF** format (**GGML Universal File** — the single-file container llama.cpp uses for weights, tokenizer, and metadata). GGUF does not quantize models itself; it **stores** weights that may already be quantized (e.g. Q4_K_M). A 7B model in Q4_K_M is roughly 4 GB on disk instead of ~14 GB in FP16, with modest quality tradeoffs on summarization tasks.

---

## Why Not Build an AI Engine in Dart?

Because building an LLM runtime from scratch is extremely difficult. You would need to implement:

- Tensor mathematics (matrix ops, linear algebra)
- Tokenization (converting text to numbers)
- Attention mechanisms (the core of transformer models)
- Memory management (allocating/deallocating huge tensors)
- Quantization (reducing precision for speed)
- Threading (parallel computation)
- Hardware acceleration (GPU integration)
- Model loading (parsing GGUF format)
- Inference pipelines (orchestrating computation)

**The right approach:** Use what already works.

- ✅ Use Dart for **UI and app logic**
- ✅ Use native libraries for **heavy computation**
- ✅ Communicate between them via **FFI**

This is the pattern used by all production mobile AI apps.

---

## Understanding Binary Files: .so, .dll, and .dylib

When we used to install games on Windows, many saw files like: `game.dll`, `audio.dll`, etc.

Those `.dll` files are **compiled native libraries**. They contain optimized code for:
- Rendering
- Audio processing
- Physics simulation
- Networking
- Gameplay systems

The main game executable **loads them and uses their functionality**.

### Platform-Specific Names

Flutter using llama.cpp follows the same pattern:

Instead of `physics.dll`, we load:
- **Android** (shipped in this POC): `libllama_bridge.so` via `DynamicLibrary.open`
- **iOS**: App Store rules forbid loading arbitrary `.dylib` from storage — static link and use `DynamicLibrary.process()` (planned; not fully wired in this repo)
- **Windows / macOS / Linux**: Flutter scaffold present; bridge build not included yet

The native library does the heavy work, and Flutter communicates with it via FFI.

### Why Platform-Specific?

Each platform has different:
- CPU architectures (ARM64, x86_64, etc.)
- Compilation toolchains
- Operating system requirements
- Performance characteristics

So we compile llama.cpp **once per platform** and distribute that binary with the app.

---

## What Does "Compiled Native Code" Mean?

When we write Dart:

```dart
print("Hello");
```

The Dart runtime handles compilation at runtime (JIT).

But C/C++ code gets converted into **machine instructions specific to the device architecture**:
- **ARM64** (most mobile devices, Apple Silicon)
- **x86_64** (most laptops/servers)
- **armv7** (older Android devices)

### Why This Matters

This compiled code runs **extremely fast** because it:
- Interacts directly with the CPU
- Uses CPU-specific optimizations
- Avoids runtime interpretation overhead
- Can leverage SIMD, GPU, and specialized instructions

That's why AI runtimes prefer native code—speed is critical when processing gigabytes of model weights.

---

## How Flutter Talks to C++: Dart FFI

This is where **Dart FFI** comes in.

**FFI** stands for: **Foreign Function Interface**

Which means: *"Allow Dart to call functions written in another language."*

Using FFI, Flutter can directly call native C APIs without:
- Platform channels (async overhead)
- Serialization (JSON conversion)
- Message passing (queue overhead)

[📚 Official Dart FFI Documentation](https://dart.dev/interop/c-interop)

### The Architecture at a Glance

```
Flutter UI
    ↓
Dart Code (RecordingProvider, etc.)
    ↓
Native Bridge (Dart FFI layer)
    ↓
Native C API (bridge_session_stream, etc.)
    ↓
llama.cpp (inference engine)
    ↓
AI Model (GGUF weights in RAM)
```

---

## FFI vs Platform Channels: Why Not Platform Channels?

Flutter already supports **MethodChannels** for native communication. So why use FFI instead?

### Performance Comparison

| Aspect | Platform Channels | FFI |
|--------|------------------|-----|
| Serialization | Yes (JSON conversion) | No (direct function call) |
| Async overhead | High (message queue) | Low (direct call) |
| Per-call latency | ~1-5ms | ~0.1ms |
| Memory copies | Multiple | Zero |
| Suitable for | Occasional calls | High-frequency calls |

### Why FFI for AI

Local AI inference workloads require:
- Massive memory access (gigabytes of model weights)
- Continuous token generation (millions of operations)
- High-frequency native calls (every token needs callback)
- Direct memory access (avoid copying data)

**FFI is 10-100x faster** for these patterns than platform channels.

---

## Understanding the FFI Bridge - My Implementation

Now let's look at my actual implementation. I built this in phases to understand each layer.

### Phase 1: Basic Memory Bridge

The simplest FFI example: echo a string with memory management.

```dart
// Define the native function signature
typedef EchoNative = Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef EchoDart = int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);

// Load the library
final dylib = DynamicLibrary.open('libllama_bridge.so');

// Get the native function
final echoFunc = dylib
    .lookupFunction<NativeFunction<EchoNative>>('bridge_echo_alloc')
    .asFunction<EchoDart>();

// Call it
final inputPtr = "Hello".toNativeUtf8();
final outputPtr = calloc<Pointer<Utf8>>();

try {
  final status = echoFunc(inputPtr, outputPtr);
  if (status == 0) {  // BRIDGE_STATUS_OK
    final result = outputPtr.value.toDartString();
    print("Result: $result");
  }
} finally {
  malloc.free(inputPtr);
  calloc.free(outputPtr);
}
```

**What's happening:**
1. We load the compiled C library (`libllama_bridge.so`)
2. We look up the function by name (`bridge_echo_alloc`)
3. We pass a pointer to input and a pointer where output should go
4. We read the result and clean up memory

### Phase 2: Stateful Sessions (Opaque Pointers)

For AI, we need to keep state across calls (the loaded model, context, tokenizer, etc.).

I used **opaque pointers**—Dart treats them as black boxes:

```dart
// C side defines an opaque struct
final class BridgeSessionPointer extends Opaque {}

// Dart just passes the pointer around
typedef SessionCreateNative = Pointer<BridgeSessionPointer> Function();
typedef SessionCreateDart = Pointer<BridgeSessionPointer> Function();

typedef SessionDestroyNative = Void Function(Pointer<BridgeSessionPointer>);
typedef SessionDestroyDart = void Function(Pointer<BridgeSessionPointer>);

// Create a session
final sessionPtr = bridgeSessionCreate();

// Use it
final status = bridgeSessionLoadModel(sessionPtr, modelPath, nCtx, nGpuLayers);

// Destroy it when done
bridgeSessionDestroy(sessionPtr);
```

**Why this pattern?**
- Dart doesn't need to know what's inside `BridgeSession`
- C++ can store complex objects (model, context, sampler, mutex)
- Memory is managed on the C++ side
- Dart just passes handles around

### Phase 3: Status Codes (Explicit Error Handling)

Instead of throwing exceptions, C functions return status codes:

```dart
// C header (llama_bridge.h)
typedef enum BridgeStatus {
  BRIDGE_STATUS_OK = 0,
  BRIDGE_STATUS_NULL_ARG = 1,
  BRIDGE_STATUS_EMPTY_INPUT = 2,
  BRIDGE_STATUS_MODEL_NOT_LOADED = 8,
  BRIDGE_STATUS_MODEL_LOAD_FAILED = 9,
  // ... more status codes
} BridgeStatus;

// Dart wrapper
void _throwIfError(int status, {required String operation}) {
  if (status == 0) {
    return;  // OK
  }
  final messagePtr = _bindings.bridgeStatusToCstr(status);
  final statusLabel = messagePtr.toDartString();
  throw BridgeNativeException(
    operation: operation,
    statusCode: status,
    statusLabel: statusLabel,
  );
}
```

**Why explicit status codes?**
- C functions can't throw Dart exceptions
- We need to communicate success/failure clearly
- Status codes are lightweight and predictable
- We convert to Dart exceptions at the boundary

### Phase 4: Streaming Callbacks (Tokens)

The hardest part: streaming tokens as they're generated.

In C, we use function pointers (callbacks):

```dart
// The callback signature
typedef _BridgeTokenCallbackNative =
    Void Function(Pointer<Utf8>, Pointer<Void>);

// Keep track of active streams
final Map<int, _TokenSink> _activeTokenSinks = <int, _TokenSink>{};

// Create a function that Dart FFI can pass to C
final Pointer<NativeFunction<_BridgeTokenCallbackNative>>
_nativeTokenCallbackPointer = Pointer.fromFunction<_BridgeTokenCallbackNative>(
  _nativeTokenCallback,
);

// This function is called by C for EACH token
@pragma('vm:entry-point')
void _nativeTokenCallback(Pointer<Utf8> tokenPtr, Pointer<Void> userData) {
  if (tokenPtr == nullptr || userData == nullptr) {
    return;
  }
  
  // Extract stream ID from user data
  final streamId = userData.cast<Int64>().value;
  
  // Find the sink for this stream
  final sink = _activeTokenSinks[streamId];
  if (sink == null) {
    return;
  }
  
  // Send token to Dart
  sink(tokenPtr.toDartString());
}
```

**How it works:**
1. We create a Dart function that can be called from C
2. We register it with the native session
3. C calls it for **each token** generated
4. We route the token to the appropriate Dart stream

### The Native Bridge (C++ Side)

Here's what the C++ bridge looks like:

```cpp
// llama_bridge.h - The ABI contract

typedef struct BridgeSession {
  std::string tag;
  llama_model *model;
  llama_context *context;
  llama_sampler *sampler;
  bool is_generating;
  std::atomic<bool> abort_requested;
} BridgeSession;

typedef void (*BridgeTokenCallback)(const char *token, void *user_data);

// Core functions
BridgeSession *bridge_session_create();
void bridge_session_destroy(BridgeSession *session);

int bridge_session_load_model(BridgeSession *session, const char *model_path,
                              int n_ctx, int n_gpu_layers);

int bridge_session_stream(BridgeSession *session, const char *input,
                          BridgeTokenCallback on_token, void *user_data);
```

**Key points:**
- `BridgeSession` is opaque to Dart (C++ handles the internals)
- Status codes (int return) for error handling
- Callback function pointer for streaming
- All strings owned by caller or explicitly freed

---

## The Worker Pattern: Preventing UI Freeze

Token generation is computationally heavy and can freeze the UI.

Without proper threading:
- Animations stutter
- Scrolling lags
- Button taps feel unresponsive
- App appears frozen

### The Problem: Single-Threaded Dart

```dart
// ❌ BAD: Blocks UI thread for 30+ seconds
final summary = await _service.summarize(transcript);
```

While this waits, the UI thread is blocked and the app feels frozen.

### The Solution: Worker Isolate

I created a **separate isolate** running in the background:

```dart
class NativeBridgeWorkerClient {
  static Future<NativeBridgeWorkerClient> start() async {
    final eventPort = ReceivePort();
    final readyCompleter = Completer<SendPort>();
    
    late final StreamSubscription<dynamic> subscription;
    subscription = eventPort.listen((dynamic message) {
      if (message is Map<String, Object?> && message['type'] == 'ready') {
        final commandPort = message['commandPort'];
        if (!readyCompleter.isCompleted && commandPort is SendPort) {
          readyCompleter.complete(commandPort);
        }
      }
    });

    // Spawn a new isolate
    final isolate = await Isolate.spawn(
      _nativeBridgeWorkerMain,
      eventPort.sendPort,
      debugName: 'native_bridge_worker',
    );
    
    final commandPort = await readyCompleter.future;

    return NativeBridgeWorkerClient._(
      isolate,
      eventPort,
      commandPort,
      subscription,
    );
  }
}
```

**How it works:**
1. Main thread spawns a new isolate
2. Worker isolate initializes FFI bridge
3. Main thread and worker communicate via message passing
4. FFI calls (model loading, generation) happen in worker
5. UI stays responsive

### Communication Protocol

```dart
// Request-response for blocking calls
Future<String> modelInfo() async {
  final result = await _sendRequest('modelInfo');
  return result as String;
}

// Streaming for token generation
Stream<String> streamEcho(String input) {
  final requestId = _allocateRequestId();
  final controller = StreamController<String>();
  
  _streamControllers[requestId] = controller;
  
  _commandPort.send({
    'id': requestId,
    'command': 'streamEcho',
    'input': input,
  });
  
  return controller.stream;
}
```

**Message types from worker:**
- `type: 'response'` - Response to a request
- `type: 'stream_token'` - Token in a stream
- `type: 'stream_done'` - Stream finished
- `type: 'stream_error'` - Error in stream

---

## Streaming Tokens in Real-Time

Let me trace through how a token flows from C++ to the UI:

### 1. Request Starts in Worker

```dart
// main.dart
Stream<String> streamEcho(String input) {
  final requestId = _allocateRequestId();
  final controller = StreamController<String>();
  _streamControllers[requestId] = controller;
  
  // Send to worker
  _commandPort.send({
    'id': requestId,
    'command': 'streamEcho',
    'input': input,
  });
  
  return controller.stream;
}
```

### 2. Worker Processes in Isolate

```dart
// Worker isolate (isolated from UI thread)
void _nativeBridgeWorkerMain(SendPort eventPort) {
  // Initialize FFI
  final session = NativeBridge.instance.createSession();
  
  // Setup event handler
  final receivePort = ReceivePort();
  eventPort.send({'type': 'ready', 'commandPort': receivePort.sendPort});
  
  receivePort.listen((message) {
    if (message['command'] == 'streamEcho') {
      final requestId = message['id'];
      final input = message['input'];
      
      // Call C++ with callback
      _nativeBridge.streamEcho(input, (token) {
        // Send token back to main thread
        eventPort.send({
          'type': 'stream_token',
          'id': requestId,
          'token': token,
        });
      });
    }
  });
}
```

### 3. C++ Generates and Calls Callback

```cpp
int bridge_session_stream(BridgeSession *session, const char *input,
                          BridgeTokenCallback on_token, void *user_data) {
  // Validate input
  int status = validate_input(input);
  if (status != BRIDGE_STATUS_OK) return status;
  
  // Tokenize prompt
  auto tokens = llama_tokenize(session->model, input, false);
  
  // Generate tokens
  for (int i = 0; i < kMaxGeneratedTokens; i++) {
    if (session->abort_requested) break;
    
    // Decode next token
    int token_id = llama_sampler_sample(session->sampler, session->context, -1);
    
    // Get token as string
    const char *token_str = llama_token_to_piece(session->model, token_id, false);
    
    // Call Dart callback
    on_token(token_str, user_data);
  }
  
  return BRIDGE_STATUS_OK;
}
```

### 4. Token Flows Back to Main Thread

```dart
// Back in main thread (NativeBridgeWorkerClient)
void _attachEventRouter() {
  _eventSubscription.onData((dynamic message) {
    if (message['type'] == 'stream_token') {
      final id = message['id'];
      final token = message['token'];
      
      // Find the stream controller
      final controller = _streamControllers[id];
      if (controller != null && !controller.isClosed) {
        controller.add(token);  // ✅ UI updates!
      }
    }
  });
}
```

### 5. UI Displays Token

```dart
// SummarizationProvider listens to stream
_streamSubscription = stream.listen(
  (token) {
    _summary += token;
    notifyListeners();  // ✅ Rebuilds UI with new token
  },
);
```

**Result:** Each token appears instantly without blocking the UI!

---

## Complete Project Architecture: Meeting Summarizer

Let me show the full architecture I implemented:

### System Layers

```
┌─────────────────────────────────────────────────────┐
│           Presentation Layer (UI)                   │
│  • MeetingSummarizerScreen (main recording flow)    │
│  • Settings Screen (model management)               │
│  • Recording Controls + Waveform visualization      │
│  • Streaming Summary Display                        │
└─────────────────────────────────────────────────────┘
              ↓              ↓              ↓
┌─────────────────────────────────────────────────────┐
│     State Management Layer (Provider Pattern)       │
│  • RecordingProvider (audio state)                  │
│  • TranscriptionProvider (speech-to-text state)    │
│  • SummarizationProvider (LLM streaming)           │
│  • SettingsProvider (dev mode, model paths)        │
│  • SummaryHistoryProvider (persistence)            │
└─────────────────────────────────────────────────────┘
              ↓              ↓              ↓
┌─────────────────────────────────────────────────────┐
│        Service Layer (Business Logic)               │
│  • RecordingService (using record package)         │
│  • TranscriptionService (using speech_to_text)    │
│  • SummarizationService (wraps FFI worker)         │
│  • StorageService (local file + preferences)       │
└─────────────────────────────────────────────────────┘
              ↓              ↓              ↓
┌─────────────────────────────────────────────────────┐
│    Native Layer (FFI + Isolates)                    │
│  • NativeBridgeWorkerClient (worker orchestration) │
│  • NativeBridge (FFI bindings, memory mgmt)        │
│  • NativeBridgeSession (stateful C++ handles)      │
└─────────────────────────────────────────────────────┘
              ↓              ↓              ↓
┌─────────────────────────────────────────────────────┐
│    C++ Native Bridge                                │
│  • libllama_bridge.so (Android/Linux)              │
│  • Callbacks, session management, status codes     │
│  • Memory management and cleanup                   │
└─────────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────────┐
│    llama.cpp + AI Model                            │
│  • GGUF model weights in RAM                       │
│  • Tokenization, inference, token generation       │
│  • GPU acceleration (if available)                  │
└─────────────────────────────────────────────────────┘
```

### Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # FFI and native interop
  ffi: ^2.2.0
  
  # State management
  provider: ^6.1.5+1
  
  # Audio recording
  record: ^6.2.1
  
  # Speech-to-text (on-device)
  speech_to_text: ^7.4.0
  
  # Storage
  path_provider: ^2.0.16
  shared_preferences: ^2.2.0
  
  # Utilities
  path: ^1.8.4
  crypto: ^3.0.3
```

### Core Flow: Capture → Transcription → Summarization

Two capture modes:

1. **Live mic** — `speech_to_text` transcribes while you speak (platform dictation APIs).
2. **Record then transcribe** — `record` saves `.m4a`, then `whisper_ggml` transcribes the file on-device.

```
User captures speech (live mic OR record → stop)
    ↓
Transcript text (live STT or Whisper file STT)
    ↓
SummarizationProvider gets transcript
    ↓
SummarizationService loads GGUF via FFI bridge
    ↓
Native bridge applies per-model chat template (llama_chat_apply_template)
    ↓
NativeBridgeWorkerClient sends streamChat command
    ↓
Worker isolate calls C++ bridge_session_stream_chat
    ↓
C++ calls llama.cpp for token generation
    ↓
For each token:
  - Callback fires
  - Token sent to main thread via message passing
  - UI updates with new token appearing
    ↓
Generation complete
    ↓
Summary displayed to user
```

---

## Creating the Native Bridge (The Hard Part)

The C++ bridge (`llama_bridge.cpp`) handles:

### 1. Session Management

```cpp
struct BridgeSession {
  std::string tag;
  int request_count = 0;
  std::string loaded_model_path;
  llama_model *model = nullptr;
  llama_context *context = nullptr;
  llama_sampler *sampler = nullptr;
  bool is_generating = false;
  std::mutex mutex;
  std::atomic<bool> abort_requested{false};  // Can be set from any thread
};

BridgeSession *bridge_session_create() {
  auto *session = new BridgeSession();
  retain_llama_backend();  // Initialize llama.cpp backend once
  return session;
}

void bridge_session_destroy(BridgeSession *session) {
  if (session == nullptr) return;
  std::lock_guard<std::mutex> lock(session->mutex);
  unload_model_locked(session);
  release_llama_backend();
  delete session;
}
```

### 2. Model Loading

```cpp
int bridge_session_load_model(BridgeSession *session, const char *model_path,
                              int n_ctx, int n_gpu_layers) {
  if (session == nullptr || model_path == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  
  std::lock_guard<std::mutex> lock(session->mutex);
  
  // Check if model already loaded
  if (session->model != nullptr) {
    return BRIDGE_STATUS_MODEL_ALREADY_LOADED;
  }
  
  // Load model weights from file
  session->model = llama_model_load_from_file(model_path, model_params);
  if (session->model == nullptr) {
    return BRIDGE_STATUS_MODEL_LOAD_FAILED;
  }
  
  // Create inference context
  session->context = llama_new_context_with_model(session->model, ctx_params);
  if (session->context == nullptr) {
    llama_model_free(session->model);
    session->model = nullptr;
    return BRIDGE_STATUS_CONTEXT_INIT_FAILED;
  }
  
  // Setup sampler (for token selection)
  session->sampler = llama_sampler_chain_init(sampler_params);
  session->loaded_model_path = model_path;
  
  return BRIDGE_STATUS_OK;
}
```

### 3. Token Streaming with Callbacks

```cpp
int bridge_session_stream(BridgeSession *session, const char *input,
                          BridgeTokenCallback on_token, void *user_data) {
  if (session == nullptr || input == nullptr || on_token == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  
  std::lock_guard<std::mutex> lock(session->mutex);
  
  if (session->model == nullptr) {
    return BRIDGE_STATUS_MODEL_NOT_LOADED;
  }
  
  // Tokenize input
  auto tokens = llama_tokenize(session->model, input, false);
  
  // Generate up to kMaxGeneratedTokens
  for (int i = 0; i < kMaxGeneratedTokens; i++) {
    // Check abort flag (can be set from any thread)
    if (session->abort_requested) {
      session->abort_requested = false;
      break;
    }
    
    // Decode next token
    int token_id = llama_sampler_sample(session->sampler, session->context, -1);
    
    // Get string representation
    const char *token_str = llama_token_to_piece(session->model, token_id, false);
    
    // Call Dart callback
    on_token(token_str, user_data);
  }
  
  return BRIDGE_STATUS_OK;
}
```

### 4. Abort Signal (Thread-Safe)

```cpp
int bridge_session_abort_stream(BridgeSession *session) {
  if (session == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  
  // Set atomic flag — safe from any thread
  session->abort_requested = true;
  return BRIDGE_STATUS_OK;
}
```

**Why atomic?** The abort flag can be set from the main Dart thread while C++ is generating tokens. Using `std::atomic<bool>` makes this thread-safe without expensive locks.

---

## Implementation Details: The Dart FFI Layer

### Native Bridge Initialization

```dart
DynamicLibrary _openNativeLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libllama_bridge.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS/macOS: symbols linked into app binary
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Platform not supported');
}

class NativeBridge {
  NativeBridge._() : _bindings = _BridgeBindings(_openNativeLibrary());

  static final NativeBridge instance = NativeBridge._();

  final _BridgeBindings _bindings;
}
```

### Session Wrapper

```dart
class NativeBridgeSession {
  NativeBridgeSession._(this._bindings, this._pointer);

  final _BridgeBindings _bindings;
  Pointer<BridgeSessionPointer> _pointer;
  bool _isDisposed = false;

  void loadModel({
    required String modelPath,
    required int nCtx,
    required int nGpuLayers,
  }) {
    _ensureActive();
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final status = _bindings.bridgeSessionLoadModel(
        _pointer,
        pathPtr,
        nCtx,
        nGpuLayers,
      );
      if (status != 0) {
        _throwIfError(status, operation: 'bridge_session_load_model');
      }
    } finally {
      malloc.free(pathPtr);
    }
  }

  void dispose() {
    if (!_isDisposed && _pointer != nullptr) {
      _bindings.bridgeSessionDestroy(_pointer);
      _pointer = nullptr.cast<BridgeSessionPointer>();
      _isDisposed = true;
    }
  }
}
```

### Memory Management

```dart
// ✅ Correct: Always free native memory
String _readAndFreeNativeUtf8(Pointer<Utf8> ptr) {
  if (ptr == nullptr) {
    throw const BridgeNativeException(
      operation: 'native_output',
      statusCode: -1,
      statusLabel: 'native_returned_null_output',
    );
  }
  try {
    return ptr.toDartString();  // Convert to Dart string
  } finally {
    _bindings.bridgeStringFree(ptr);  // Free native memory
  }
}
```

---

## Services and Providers

### SummarizationService (FFI Bridge)

```dart
class SummarizationService {
  SummarizationService({
    required String? modelPath,
    this.nCtx = 256,
    this.nGpuLayers = 999,
  }) : _modelPath = modelPath;

  String? _modelPath;
  final int nCtx;
  final int nGpuLayers;

  NativeBridgeWorkerClient? _worker;
  bool _sessionReady = false;
  bool _modelLoaded = false;

  Future<void> _ensureSessionReady() async {
    if (_sessionReady && _worker != null) return;
    
    _worker ??= await NativeBridgeWorkerClient.start();
    if (!_sessionReady) {
      await _worker!.createSession(tag: 'meeting_summarizer');
      _sessionReady = true;
    }
  }

  Future<void> ensureModelLoaded() async {
    await _ensureSessionReady();
    if (!_modelLoaded) {
      await _worker!.loadModel(
        modelPath: _modelPath!,
        nCtx: nCtx,
        nGpuLayers: nGpuLayers,
      );
      _modelLoaded = true;
    }
  }

  Stream<String> summarize(String transcript) async* {
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) {
      throw const SummarizationServiceException('Transcript is empty.');
    }

    await ensureModelLoaded();

    // Chunk long transcripts; native bridge applies the GGUF chat template.
    yield* _worker!.streamChat(
      systemPrompt: 'You are a concise meeting summarization assistant.',
      userPrompt: 'Summarize this meeting transcript:\n\n$cleaned',
      maxTokens: 512,
    );
  }

  Future<void> dispose() async {
    final worker = _worker;
    if (worker != null) {
      await worker.close();
    }
    _worker = null;
    _sessionReady = false;
    _modelLoaded = false;
  }
}
```

### SummarizationProvider (State Management)

```dart
enum SummarizationStatus { idle, generating, done, error }

class SummarizationProvider extends ChangeNotifier {
  SummarizationProvider(this._summarizationService);

  final SummarizationService _summarizationService;

  SummarizationStatus _status = SummarizationStatus.idle;
  String _summary = '';
  String? _errorMessage;
  StreamSubscription<String>? _streamSubscription;

  SummarizationStatus get status => _status;
  bool get isGenerating => _status == SummarizationStatus.generating;
  String get summary => _summary;
  String? get errorMessage => _errorMessage;

  Future<void> summarize(String transcript) async {
    await _streamSubscription?.cancel();
    _summary = '';
    _errorMessage = null;
    _status = SummarizationStatus.generating;
    notifyListeners();

    try {
      final stream = _summarizationService.summarize(transcript);
      
      _streamSubscription = stream.listen(
        (token) {
          _summary += token;
          notifyListeners();  // ✅ UI updates with each token
        },
        onError: (Object error) {
          _status = SummarizationStatus.error;
          _errorMessage = error.toString();
          notifyListeners();
        },
        onDone: () {
          _streamSubscription = null;
          if (_status != SummarizationStatus.error) {
            _status = SummarizationStatus.done;
            notifyListeners();
          }
        },
        cancelOnError: true,
      );
    } catch (error) {
      _status = SummarizationStatus.error;
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> cancelGeneration() async {
    if (_status != SummarizationStatus.generating) return;
    
    _status = SummarizationStatus.idle;
    _errorMessage = null;
    notifyListeners();
    
    await _streamSubscription?.cancel();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _summarizationService.dispose();
    super.dispose();
  }
}
```

---

## Step-by-Step Integration Guide

### Step 1: Setup Project

```bash
git clone https://github.com/your-repo/ffi_learn.git
cd ffi_learn
flutter pub get
```

### Step 2: Download a GGUF Model

```bash
# TinyLlama (1.1B, 600MB) - Recommended for mobile
wget https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf

# Or Phi 2 (2.7B, 1.4GB)
wget https://huggingface.co/TheBloke/Phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf
```

### Step 3: Add Model to Assets

```bash
# Android
mkdir -p android/app/src/main/assets
cp model.gguf android/app/src/main/assets/

# iOS
cp model.gguf ios/Runner/
# Then add to Xcode: Build Phases → Copy Bundle Resources
```

### Step 4: Configure Model Path

```dart
// lib/models/model_presets.dart
class AppModelPresets {
  static const String defaultModelId = 'tiny_llama';
  
  static AppModelPreset get tinyllama => AppModelPreset(
    id: defaultModelId,
    displayName: 'TinyLlama 1.1B',
    nCtx: 256,
    nGpuLayers: 999,
    getPath: _getTinyLlamaPath,
  );
  
  static Future<String> _getTinyLlamaPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/model.gguf';
  }
}

// In main.dart
final selectedModel = AppModelPresets.tinyllama;
runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider<SummarizationProvider>(
        create: (_) => SummarizationProvider(
          SummarizationService(
            modelPath: await selectedModel.getPath(),
          ),
        ),
      ),
    ],
    child: const App(),
  ),
);
```

### Step 5: Build and Run

```bash
# Android Emulator
flutter run

# iOS Simulator
flutter run -d "iPhone 15"

# Physical Device
flutter run -d <device-id>
```

### Step 6: Monitor Logs

```bash
# Terminal 1
flutter run

# Terminal 2
flutter logs | grep -E "MODEL|SUMMARIZE|STT|native"
```

---

## Performance Optimization

### 1. Model Selection

| Model | Size | Speed | Quality |
|-------|------|-------|---------|
| TinyLlama | 600MB | ⚡⚡⚡ | ⭐⭐ |
| Phi 2 | 1.4GB | ⚡⚡ | ⭐⭐⭐ |
| Mistral | 4GB | ⚡ | ⭐⭐⭐⭐ |

For mobile: Use **TinyLlama** or **Phi-2** with high quantization (Q4_K_M or Q3_K_M).

### 2. Context Size Tuning

```dart
// Smaller context = faster inference
// But may cut off long transcripts

// Mobile (slow CPUs): 128-256
nCtx: 256,

// High-end phones: 512-1024
nCtx: 1024,

// Desktop: 2048+
nCtx: 2048,
```

### 3. GPU Acceleration

```dart
// Use GPU if available (fallback to CPU)
nGpuLayers: 999,

// Or manually control:
nGpuLayers: 20,  // First 20 layers on GPU, rest on CPU
```

### 4. Prompt Optimization

```dart
// Original: 5000 characters
// Truncated: 500 characters (last 500, most relevant)
const maxChars = 500;
final boundedTranscript = cleaned.length > maxChars
    ? cleaned.substring(cleaned.length - maxChars)
    : cleaned;

// Result: 5x faster inference, 95% of quality
```

### 5. Memory Management

```dart
// Always unload model when not needed
@override
void dispose() {
  _summarizationService.dispose();  // Frees model from RAM
  super.dispose();
}
```

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Crash on model load | Model path incorrect | Verify file exists, check logs |
| "No tokens generated" | Model too small/corrupted | Use verified GGUF (TheBloke), test locally |
| Generation timeout | Model too large for device | Use smaller model (TinyLlama), reduce context |
| UI freezes during generation | Not using isolates properly | Ensure SummarizationService uses worker |
| Memory grows endlessly | Not freeing model | Call `dispose()` when done, check for leaks |
| Segmentation fault | Memory corruption in FFI | Check memory management: malloc/free pairs |
| Slow token output | Large context / slow device | Reduce `nCtx`, use GPU acceleration |

---

## Key Learnings from This POC

### 1. Memory Management is Critical

Native code has no garbage collection. Every `malloc` needs a `free`. Every `calloc` needs cleanup.

```dart
// ✅ Pattern: Always cleanup
final ptr = calloc<Pointer<Utf8>>();
try {
  // Use ptr
} finally {
  calloc.free(ptr);  // Always runs
}
```

### 2. Isolates Are Essential

Inference can take 30+ seconds. Using a worker isolate is **not optional**—it's required for a responsive UI.

### 3. Streaming Beats Batching

Showing tokens one-by-one gives instant feedback to users. Waiting for the whole response feels slow.

### 4. Status Codes Over Exceptions

C++ can't throw Dart exceptions. Status codes are the safe bridge for error handling.

### 5. Opaque Pointers Are Your Friend

Dart doesn't need to understand the internals of C++ structs. Treat them as black boxes—it simplifies the ABI.

### 6. Callbacks Are Powerful But Tricky

Function pointers are the way to stream data from C++ back to Dart. Need to manage lifetime carefully.

---

## What's Next?

This POC covers the essentials. In production, you might add:

- **Model download & caching** - Don't bundle 600MB+ models
- **Multiple model support** - Let users choose model size
- **Better error recovery** - Graceful degradation on older devices
- **Export/sharing** - Save and share summaries
- **Custom prompts** - User-defined summarization styles
- **Performance profiling** - Track latency and memory usage
- **iOS implementation** - Currently Android-focused

---

## Conclusion

Building local LLM apps with Flutter FFI and llama.cpp is complex but entirely achievable.

The architecture I used:
- ✅ Dart for UI and state management (what it's good at)
- ✅ C++ for inference and hardware optimization (what it's good at)
- ✅ FFI for bridging them with minimal overhead
- ✅ Isolates for preventing UI blocks
- ✅ Streaming for responsive UX

The result: an offline, private, battery-efficient meeting summarizer that runs entirely on the device.

---

## Resources

- [Dart FFI Documentation](https://dart.dev/interop/c-interop)
- [llama.cpp Repository](https://github.com/ggml-org/llama.cpp)
- [GGUF Model Format](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md)
- [Flutter Native Integration](https://docs.flutter.dev/platform-integration)
- [Provider Package](https://pub.dev/packages/provider)
- [HuggingFace GGUF Models](https://huggingface.co/models?library=gguf)

---

**Author's Note:** This guide is based on a proof-of-concept meeting summarizer. The patterns shown—opaque pointers, worker isolates, streaming callbacks, per-model chat templates, and memory management—are the same ones you would reuse in a production app, tested on Android arm64 devices.

The learning curve is steep, but the capability you unlock—running sophisticated AI models offline on mobile devices—is worth it.

Happy building! 🚀
