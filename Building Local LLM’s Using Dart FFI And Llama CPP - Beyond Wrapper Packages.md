**Building Local LLM’s Using Dart FFI And Llama CPP \- Beyond Wrapper Packages**

# **Introduction**

When I first explored running local LLMs inside Flutter, I had a lot of questions:

* Why are people using C++ libraries for AI?  
* Why not just write everything in Dart?  
* What exactly is llama.cpp?  
* What are .so, .dll, and .dylib files?  
* Why does Flutter suddenly need native code?  
* Why do most tutorials feel incomplete?

If you’re coming from a Flutter-only background, all of this initially feels very unfamiliar.  
Most Flutter developers rarely touch:

* native memory,  
* C/C++,  
* shared libraries,  
* compilers,  
* ABI architectures,  
* or systems-level programming.

But once you understand the architecture, things become surprisingly logical.  
This article is the guide I wish I had when I started exploring local AI in Flutter.

Before diving in, 

* *why go through all the complexity of Flutter FFI and llama.cpp when we could simply host a GGUF model on a Python FastAPI server and consume it like any normal API?*  
  Local AI solves a completely different problem. Server-based AI depends on internet connectivity, introduces latency, incurs infrastructure costs, and sends user data to external servers. With llama.cpp, the model runs directly on the device itself, enabling offline inference, better privacy, lower latency, and eliminating backend AI costs entirely. In many ways, llama.cpp acts like the **engine** that knows how to run a GGUF model, while Flutter communicates with that engine through Dart FFI.

# **Why Are AI Libraries Usually Written in C++?**

This was my first major question.  
Why is almost every serious AI runtime written in:

* C,  
* C++,  
* Rust,  
* CUDA,  
* Metal,  
* or some low-level language?

Why not Dart? The answer is performance and hardware access.  
LLMs perform enormous amounts of: matrix multiplication, memory operations, tensor computation, CPU/GPU optimizations.  
Languages like Dart are fantastic for: UI, app logic, developer productivity. But they are not designed for ultra-low-level hardware optimization.

C++ gives developers:

* direct memory control,  
* CPU optimization,  
* SIMD instructions,  
* GPU integrations,  
* fine-grained threading,  
* extremely fast execution.

That’s why libraries like: TensorFlow, PyTorch, ONNX Runtime, llama.cpp, all rely heavily on native code internally. Even Python AI frameworks are mostly wrappers around C/C++ backends.

# **So what exactly is llama.cpp?**

[llama.cpp](https://github.com/ggml-org/llama.cpp?utm_source=chatgpt.com) is a lightweight C/C++ implementation for running LLMs efficiently on local devices.  
Think of it as an AI inference engine optimized for local hardware.  
It takes **model weights, tokens,prompts**, and performs the actual mathematical computation required to generate text.  
It supports all CPUs, GPUs and importantly it does not require Python.

# **Why Use llama.cpp Instead of Building an AI Engine in Dart?**

Because building an LLM runtime is extremely difficult.  
You would need to implement:

* tensor math,  
* tokenization,  
* attention mechanisms,  
* memory management,  
* quantization,  
* threading,  
* hardware acceleration,  
* model loading,  
* inference pipelines.

Instead, Flutter apps usually:

* use Dart for UI and app logic,  
* use native libraries for heavy computation.

# **What Are .so, .dll, and .dylib Files?**

When we used to install games on Windows, many of us probably saw files like: game.dll, audio.dll etc  
At that time, most developers never questioned what those files actually were.  
Those .dll files are compiled native libraries.  
They contain optimized code for:

* rendering,  
* audio,  
* physics,  
* networking,  
* gameplay systems.

The main game executable loads them and uses their functionality.  
Flutter using llama.cpp is conceptually very similar.  
Instead of physics.dll we load [libllama.so](http://libllama.so) or llama.dll file depending on platform.  
The native library does heavy work and Flutter simply communicates with it.

So basically, these are simply platform specific shared libraries eg: windows has dll, android/linux has .so and macOs/iOS has .dylib  
They all serve a similar purpose: compiled reusable native code.

# **What Does "Compiled Native Code" Mean?**

When we write Dart:   
**print("Hello");**  
Flutter/Dart handles most things for us.  
But C/C++ code gets converted directly into machine instructions specific to the device architecture like ARM64, x86\_64. This compiled code runs extremely fast because it interacts much more directly with the hardware.  
That’s why AI runtimes prefer native code.

# **So How Does Flutter Talk to C++?**

This is where Dart FFI comes in.  
[Dart FFI Documentation](https://dart.dev/interop/c-interop?utm_source=chatgpt.com)  
FFI stands for: **Foreign Function Interface**  
Which basically means:  
"Allow Dart to call functions written in another language."  
Using FFI, Flutter can directly call native C APIs.

# **The Architecture**

At a high level:  
Flutter UI \-\> Dart Code \-\> Dart FFI \-\> Native C API \-\> llama.cpp \-\> AI model

# **Why Not Platform Channels?**

This was another doubt I had.  
Flutter already supports: MethodChannels, platform communication and native integration. So why use FFI?  
Because inference workloads are different.  
Platform channels involve: serialization,message passing, and async communication overhead.  
Local AI requires massive memory access, continuous token generation, and high-frequency native calls. FFI is much faster for these workloads.

# **Understanding the Basic FFI Code**

Now let’s dive into the code 

# **Step 1 \- Loading the Native Library**

**final dylib \= DynamicLibrary.open("[libllama.so](http://libllama.so)");**

What is happening here?  
We are telling Flutter "Load this compiled native library into memory."  
Think of it like importing a package \- but at the operating system level.  
The app now gains access to functions inside: libllama.so

# **Step 2 \- Defining Native Function Signatures**

**typedef InitNative \= Pointer\<Void\> Function(Pointer\<Utf8\>);**

This simply describes what the C++ function looks like.  
Equivalent idea in C: void\* init\_model(char\* path);

Meaning:

* it accepts a string path,  
* returns a pointer to native memory.

Dart needs this definition to understand how to communicate correctly with native code.

# **Step 3 \- Converting Native Function into Dart Function**

**final initModel \= dylib**  
    **.lookup\<NativeFunction\<InitNative\>\>('init\_model')**  
    **.asFunction\<InitDart\>();**

This line means:

1. Find the function called init\_model inside the native library.  
2. Convert it into a callable Dart function.

Now Flutter can invoke it like normal Dart code.

# **Step 4 \- Passing Model Path**

**final modelPath \= "/storage/emulated/0/model.gguf".toNativeUtf8();**  
Why convert the string? Because native C code does not understand Dart strings directly.  
C uses char\* instead of Dart’s String object. So we convert the Dart string into native UTF8 memory.

# **Step 5 \- Initializing the Model**

**final context \= initModel(modelPath);**  
This line tells llama.cpp \-\> "Load this AI model into memory."  
This step may:

* allocate RAM,  
* initialize tensors,  
* create inference context,  
* prepare tokenization,  
* load quantized weights.

This is usually expensive. Some models can take several seconds to initialize.

# **Why use Pointer?**

Pointers are another concept that confuses many Flutter developers initially.  
A pointer is simply **a memory address.**  
Instead of storing huge objects everywhere, native systems often store references, addresses, locations in memory. Example:0x00007FF8A1B2C3D4  
That might point to a model, tensor data, tokenizer or inference context.  
Pointers help native systems avoid copying huge amounts of memory repeatedly.

# **Why Memory Management Becomes Important**

Dart normally has garbage collection. Native code often does not. This means you can accidentally leak memory if you don’t release resources properly.  
Example:

* forgetting to free model context,  
* forgetting token buffers,  
* leaking native allocations.

This becomes especially important with LLMs because models are huge.

# **The Real Challenge: Streaming Tokens**

In real AI apps stream tokens progressively rather than single output at once.  
Instead of waiting for:   
*This is the final response.*  
users see:  
*This*  
*This is*  
*This is generated*  
*This is generated progressively*

\<need to add code solution here\>

# **Why Isolates Matter**

Because token generation is computationally heavy, it can freeze UI. Without isolates animations stutter, scrolling lags,and input becomes unresponsive.  
That’s why inference is usually moved into:

* native threads,  
* background isolates,  
* async stream pipelines.


\<need to add code solution here\>

\<need to add small step/explanation and code for sample project here\>  
