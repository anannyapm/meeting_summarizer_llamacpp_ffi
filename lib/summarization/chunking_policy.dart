/// Map-reduce chunking with overlap to preserve cross-boundary context.
class ChunkingPolicy {
  const ChunkingPolicy({
    this.maxChunkChars = 600,
    this.overlapChars = 80,
  });

  final int maxChunkChars;
  final int overlapChars;

  List<String> chunk(String transcript) {
    final text = transcript.trim();
    if (text.length <= maxChunkChars) {
      return <String>[text];
    }

    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + maxChunkChars).clamp(0, text.length);
      if (end < text.length) {
        final lastSpace = text.lastIndexOf(' ', end);
        if (lastSpace > start) {
          end = lastSpace;
        }
      }
      final slice = text.substring(start, end).trim();
      if (slice.isNotEmpty) {
        chunks.add(slice);
      }
      if (end >= text.length) {
        break;
      }
      start = (end - overlapChars).clamp(0, text.length);
      if (start >= end) {
        start = end;
      }
    }
    return chunks;
  }

  String formatCombineInput(List<String> partialSummaries) {
    return partialSummaries.join('\n\n');
  }
}
