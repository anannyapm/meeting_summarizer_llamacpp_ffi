import 'package:ffi_learn/native/native_bridge_worker.dart';
import 'package:llama_bridge_flutter/llama_bridge_flutter.dart';

/// App-level facade over the extracted plugin engine.
class LlamaEngineFacade {
  LlamaEngineFacade()
      : _engine = FlutterLlamaBridgeEngine(
          () => NativeBridgeWorkerClient.start(),
        );

  final FlutterLlamaBridgeEngine _engine;

  LlamaBridgeEngine get engine => _engine;

  Future<void> loadPresetModel({
    required String modelPath,
    required ContextParams context,
  }) {
    return _engine.loadModel(
      model: ModelParams(modelPath: modelPath),
      context: context,
    );
  }

  Stream<String> summarizeStream({
    required String userPrompt,
    required String systemPrompt,
    required int maxTokens,
    required bool useChatTemplate,
  }) {
    return _engine.generateStream(
      userPrompt: userPrompt,
      options: GenerationOptions(
        maxTokens: maxTokens,
        systemPrompt: systemPrompt,
        useChatTemplate: useChatTemplate,
      ),
    );
  }

  Future<void> dispose() => _engine.dispose();
}
