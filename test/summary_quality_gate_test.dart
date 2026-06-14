import 'package:flutter_test/flutter_test.dart';

import 'package:ffi_learn/summarization/chunking_policy.dart';
import 'package:ffi_learn/summarization/summary_quality_gate.dart';
import 'package:ffi_learn/summarization/timeout_policy.dart';

import 'fixtures/benchmark_transcripts.dart';

void main() {
  group('SummaryQualityGate', () {
    test('rejects instruction echo', () {
      expect(
        SummaryQualityGate.isBadSummary(
          'Summarize this meeting transcript. Write 2 to 4 sentences.',
          '',
        ),
        isTrue,
      );
    });

    test('accepts plausible summary', () {
      expect(
        SummaryQualityGate.isBadSummary(
          'The team agreed to ship Android first, fix login bugs, and review PRs by EOD.',
          BenchmarkCorpus.shortStandup.text,
        ),
        isFalse,
      );
    });

    test('rubric scores keyword coverage', () {
      final score = SummaryQualityGate.rubricScore(
        summary:
            'Alice fixed login and will deploy. Bob is blocked on API keys. Carol will review.',
        expectedKeywords: BenchmarkCorpus.shortStandup.expectedKeywords,
      );
      expect(score, greaterThan(0.4));
    });
  });

  group('ChunkingPolicy overlap', () {
    test('long text produces multiple overlapping chunks', () {
      const policy = ChunkingPolicy(maxChunkChars: 400, overlapChars: 60);
      final chunks = policy.chunk(BenchmarkCorpus.longAllHands.text);
      expect(chunks.length, greaterThan(1));
      expect(chunks.first.length, lessThanOrEqualTo(400));
    });
  });

  group('TimeoutPolicy', () {
    test('total timeout scales with chunk count', () {
      const policy = TimeoutPolicy();
      final one = policy.totalTimeout(chunkCount: 1, slowModel: false);
      final three = policy.totalTimeout(chunkCount: 3, slowModel: false);
      expect(three.inSeconds, greaterThan(one.inSeconds));
    });
  });
}
