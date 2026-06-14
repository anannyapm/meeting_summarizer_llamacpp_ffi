class ContextParams {
  const ContextParams({
    this.nCtx = 512,
    this.nGpuLayers = 0,
    this.nBatch = 64,
    this.nThreads = 4,
  });

  final int nCtx;
  final int nGpuLayers;
  final int nBatch;
  final int nThreads;
}
