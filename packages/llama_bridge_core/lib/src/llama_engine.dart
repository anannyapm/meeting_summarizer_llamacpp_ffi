import 'generation_options.dart';
import 'context_params.dart';
import 'model_params.dart';

/// Plugin-style engine facade (session lifecycle + streaming generation).
abstract class LlamaBridgeEngine {
  Future<void> loadModel({
    required ModelParams model,
    required ContextParams context,
  });

  Future<void> unloadModel();

  Stream<String> generateStream({
    required String userPrompt,
    GenerationOptions options = const GenerationOptions(),
  });

  Future<void> cancelGeneration();

  Future<String> modelInfo();

  Future<void> dispose();
}
