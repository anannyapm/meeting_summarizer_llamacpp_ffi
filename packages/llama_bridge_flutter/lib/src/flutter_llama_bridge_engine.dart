import 'package:llama_bridge_core/llama_bridge_core.dart';

/// Flutter FFI engine — wraps app native bridge worker (libllama_bridge.so on Android).
class FlutterLlamaBridgeEngine implements LlamaBridgeEngine {
  FlutterLlamaBridgeEngine(this._workerFactory);

  final Future<dynamic> Function() _workerFactory;
  dynamic _worker;
  bool _sessionReady = false;
  bool _modelLoaded = false;

  @override
  Future<void> loadModel({
    required ModelParams model,
    required ContextParams context,
  }) async {
    _worker ??= await _workerFactory();
    if (!_sessionReady) {
      await _worker.createSession(tag: 'llama_bridge_flutter');
      _sessionReady = true;
    }
    await _worker.loadModel(
      modelPath: model.modelPath,
      nCtx: context.nCtx,
      nGpuLayers: context.nGpuLayers,
      nBatch: context.nBatch,
      nThreads: context.nThreads,
    );
    _modelLoaded = true;
  }

  @override
  Future<void> unloadModel() async {
    if (!_modelLoaded || _worker == null) {
      return;
    }
    await _worker.unloadModel();
    _modelLoaded = false;
  }

  @override
  Stream<String> generateStream({
    required String userPrompt,
    GenerationOptions options = const GenerationOptions(),
  }) {
    if (_worker == null || !_modelLoaded) {
      throw const LlamaBridgeException('Model not loaded');
    }
    if (options.useChatTemplate) {
      return _worker.streamChat(
        systemPrompt: options.systemPrompt,
        userPrompt: userPrompt,
        maxTokens: options.maxTokens,
      ) as Stream<String>;
    }
    return _worker.streamEcho(
      userPrompt,
      maxTokens: options.maxTokens,
    ) as Stream<String>;
  }

  @override
  Future<void> cancelGeneration() async {
    if (_worker == null) {
      return;
    }
    await _worker.abortStream();
  }

  @override
  Future<String> modelInfo() async {
    if (_worker == null) {
      throw const LlamaBridgeException('Session not ready');
    }
    return _worker.modelInfo() as String;
  }

  @override
  Future<void> dispose() async {
    final worker = _worker;
    _worker = null;
    _sessionReady = false;
    _modelLoaded = false;
    if (worker != null) {
      await worker.close();
    }
  }
}
