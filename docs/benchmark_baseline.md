# Benchmark Baseline

Structured metrics are emitted under the `METRICS` log tag during each summarization run.

## Schema

| Field | Meaning |
|-------|---------|
| `presetId` | Active GGUF preset |
| `transcriptChars` | Input size after prepare |
| `chunkCount` | Map-reduce chunk count |
| `ttftMs` | Time to first token |
| `totalMs` | End-to-end latency |
| `tokenCount` | Tokens streamed |
| `qualityGatePassed` | Heuristic quality check |
| `retryCount` | Quality-gate retries |

## Corpus

See `test/fixtures/benchmark_transcripts.dart` for short/medium/long fixtures.

## CI regression

Run:

```bash
flutter test test/summary_quality_gate_test.dart
```

Quality rubric uses keyword coverage + minimum length heuristics (no GGUF required).

## On-device baseline (manual)

1. Release build on arm64 physical device
2. Run each benchmark transcript with Llama 3.2 1B
3. Capture logcat: `flutter logs | grep METRICS`
4. Record TTFT and totalMs per fixture

Target SLO: TTFT < 30s, total < 120s for short/medium on recommended models.
