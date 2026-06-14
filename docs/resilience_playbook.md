# Resilience Playbook

## Timeout recovery (soft vs hard)

| Scenario | Behavior |
|----------|----------|
| First-token grace | Wait 5s for late tokens before abort |
| Soft reset | `abortStream()` only — model stays loaded |
| Hard reset | Kill worker isolate — use only if abort fails |

## Cancel

User cancel calls `abortStream()` and cancels the Dart subscription. Model remains loaded.

## Model integrity

When `expectedSha256` is set on a preset, `ModelManager` verifies after download. Re-download if verification fails.

## Partial summaries

If total timeout fires with non-empty buffer, UI shows partial summary with warning message.

## Common incidents

### Stuck on prefill

- Check logcat for `prefill decode start` without `prefill decode done`
- Try smaller/faster preset (SmolLM2 360M, Llama 3.2 1B)
- Ensure release build (debug is 2-3x slower)

### Echo / instruction leak in output

- Quality gate retries once with stricter system prompt
- SmolLM2 uses `plainEcho` completion format; others use native chat template

### Worker dead after timeout

- Soft recovery should prevent this; if model shows "Not loaded" after timeout, reload from Settings

## Disk pressure

Use Settings → clear unused models (when enabled). Avoid deleting the currently loaded GGUF file.
