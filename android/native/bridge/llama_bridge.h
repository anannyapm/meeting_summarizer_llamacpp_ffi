#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Phase 1 ABI: minimal string bridge with explicit ownership.
// - Caller owns `input` memory.
// - Native allocates returned string for bridge_echo_alloc().
// - Dart MUST release that memory via bridge_string_free().
//
// Phase 2 ABI: add native state via opaque pointer.
// - Dart treats BridgeSession as an opaque handle only.
// - bridge_session_create allocates native state.
// - Dart MUST call bridge_session_destroy exactly once per successful create.
//
// Threading: one bridge_session_stream / bridge_session_stream_chat at a time per
// session. unload/destroy aborts in-flight generation and waits for the decode loop
// to finish before freeing model/context memory.
//
// Phase 3 ABI: explicit status codes and output pointers.
// - Return code communicates why a call failed.
// - Output pointer is set only on success.
// - Native strings are always freed via bridge_string_free().

typedef enum BridgeStatus {
  BRIDGE_STATUS_OK = 0,
  BRIDGE_STATUS_NULL_ARG = 1,
  BRIDGE_STATUS_EMPTY_INPUT = 2,
  BRIDGE_STATUS_INPUT_TOO_LARGE = 3,
  BRIDGE_STATUS_ALLOCATION_FAILED = 4,
  BRIDGE_STATUS_CALLBACK_NULL = 5,
  BRIDGE_STATUS_LLAMA_BACKEND_NOT_READY = 6,
  BRIDGE_STATUS_MODEL_ALREADY_LOADED = 7,
  BRIDGE_STATUS_MODEL_NOT_LOADED = 8,
  BRIDGE_STATUS_MODEL_LOAD_FAILED = 9,
  BRIDGE_STATUS_CONTEXT_INIT_FAILED = 10,
  BRIDGE_STATUS_SAMPLER_INIT_FAILED = 11,
  BRIDGE_STATUS_GENERATION_IN_PROGRESS = 12,
  BRIDGE_STATUS_TOKENIZE_FAILED = 13,
  BRIDGE_STATUS_DECODE_FAILED = 14
} BridgeStatus;

const char *bridge_version();

const char *bridge_status_to_cstr(int status_code);

int bridge_echo_alloc(const char *input, char **out_string);

void bridge_string_free(char *ptr);

int bridge_llama_runtime_info_alloc(char **out_string);

typedef struct BridgeSession BridgeSession;
typedef void (*BridgeTokenCallback)(const char *token, void *user_data);

BridgeSession *bridge_session_create();

void bridge_session_destroy(BridgeSession *session);

int bridge_session_set_tag(BridgeSession *session, const char *tag);

int bridge_session_echo_alloc(BridgeSession *session, const char *input,
                              char **out_string);

int bridge_session_stream(BridgeSession *session, const char *input,
                          int max_tokens, BridgeTokenCallback on_token,
                          void *user_data);

int bridge_session_stream_chat(BridgeSession *session,
                               const char *system_prompt,
                               const char *user_prompt, int max_tokens,
                               BridgeTokenCallback on_token, void *user_data);

int bridge_session_load_model(BridgeSession *session, const char *model_path,
                              int n_ctx, int n_gpu_layers, int n_batch,
                              int n_threads);

int bridge_session_unload_model(BridgeSession *session);

int bridge_session_model_info_alloc(BridgeSession *session, char **out_string);

// Signals the ongoing bridge_session_stream call to stop at the next decode
// step. Safe to call from any thread. Returns BRIDGE_STATUS_OK on success.
int bridge_session_abort_stream(BridgeSession *session);

#ifdef __cplusplus
}
#endif