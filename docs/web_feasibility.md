# Web Local Inference Feasibility

**Decision gate:** Research phase only — does not block Android ship.

## Constraints

| Factor | Browser reality |
|--------|-----------------|
| Model size | 300MB–1GB download per session; storage quota limits |
| Memory | WASM heap + WebGPU buffers; mobile browsers tighter than desktop |
| Threads | Limited vs native; SharedArrayBuffer requires COOP/COEP headers |
| Backend | WebGPU preferred; fallback WASM CPU is slow |
| FFI bridge | Current `libllama_bridge.so` does not run in browser |

## Options

1. **Web shell only (recommended short-term)**  
   Flutter web UI without on-device LLM; Android remains primary inference target.

2. **WASM llama.cpp + WebGPU (future)**  
   Separate build pipeline; model served from CDN or user upload; different Dart bindings than Android FFI.

3. **Hybrid**  
   Web for history/settings; summarize on Android via export/import.

## Spike checklist (if pursuing option 2)

- [ ] Build llama.cpp to WASM with emscripten or official web target
- [ ] Load 360M GGUF in Chrome desktop; measure TTFT and tok/s
- [ ] Test Safari iOS WebGPU availability
- [ ] Measure memory peak on mid-range phone browser

## Recommendation (go/no-go)

**No-go for production web local inference in current sprint.**

Proceed with Android production path. Revisit web when:

- WebGPU coverage on target devices exceeds 80%
- WASM build achieves within 2x of native TTFT on 360M–1B models
- Dedicated web model delivery UX is designed

**Go** for web **shell** (settings, history, docs) without local LLM.
