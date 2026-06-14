class ModelParams {
  const ModelParams({
    required this.modelPath,
    this.useMmap = true,
  });

  final String modelPath;
  final bool useMmap;
}
