#include "llama_bridge.h"

#include "../llama.cpp/include/llama.h"
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "llama_bridge", __VA_ARGS__)

#include <atomic>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <climits>
#include <cstdio>
#include <mutex>
#include <new>
#include <string>
#include <vector>

struct BridgeSession {
  std::string tag = "default";
  int request_count = 0;
  std::string loaded_model_path;
  llama_model *model = nullptr;
  llama_context *context = nullptr;
  llama_sampler *sampler = nullptr;
  bool is_generating = false;
  std::mutex mutex;
  // Atomic abort flag — set from any thread, checked by the llama.cpp abort
  // callback after each decode step so generation stops promptly.
  std::atomic<bool> abort_requested{false};
};

namespace {
constexpr const char *kBridgeVersion = "ffi-bridge-phase8";
constexpr size_t kMaxInputBytes = 8192;
constexpr int kMaxGeneratedTokens = 16;
std::mutex g_llama_backend_mutex;
int g_llama_backend_users = 0;

void retain_llama_backend() {
  std::lock_guard<std::mutex> lock(g_llama_backend_mutex);
  if (g_llama_backend_users == 0) {
    llama_backend_init();
  }
  g_llama_backend_users += 1;
}

void release_llama_backend() {
  std::lock_guard<std::mutex> lock(g_llama_backend_mutex);
  if (g_llama_backend_users <= 0) {
    return;
  }
  g_llama_backend_users -= 1;
  if (g_llama_backend_users == 0) {
    llama_backend_free();
  }
}

int copy_to_native_string(const std::string &value, char **out_string) {
  if (out_string == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }

  const size_t size_with_null = value.size() + 1;
  auto *out = static_cast<char *>(std::malloc(size_with_null));
  if (out == nullptr) {
    *out_string = nullptr;
    return BRIDGE_STATUS_ALLOCATION_FAILED;
  }

  std::memcpy(out, value.c_str(), size_with_null);
  *out_string = out;
  return BRIDGE_STATUS_OK;
}

int validate_input(const char *input) {
  if (input == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }

  const size_t input_len = std::strlen(input);
  if (input_len == 0) {
    return BRIDGE_STATUS_EMPTY_INPUT;
  }
  if (input_len > kMaxInputBytes) {
    return BRIDGE_STATUS_INPUT_TOO_LARGE;
  }

  return BRIDGE_STATUS_OK;
}

void unload_model_locked(BridgeSession *session) {
  if (session->sampler != nullptr) {
    llama_sampler_free(session->sampler);
    session->sampler = nullptr;
  }
  if (session->context != nullptr) {
    llama_free(session->context);
    session->context = nullptr;
  }
  if (session->model != nullptr) {
    llama_model_free(session->model);
    session->model = nullptr;
  }
  session->loaded_model_path.clear();
  session->is_generating = false;
}
} // namespace

const char *bridge_version() { return kBridgeVersion; }

const char *bridge_status_to_cstr(int status_code) {
  switch (status_code) {
  case BRIDGE_STATUS_OK:
    return "ok";
  case BRIDGE_STATUS_NULL_ARG:
    return "null_arg";
  case BRIDGE_STATUS_EMPTY_INPUT:
    return "empty_input";
  case BRIDGE_STATUS_INPUT_TOO_LARGE:
    return "input_too_large";
  case BRIDGE_STATUS_ALLOCATION_FAILED:
    return "allocation_failed";
  case BRIDGE_STATUS_CALLBACK_NULL:
    return "callback_null";
  case BRIDGE_STATUS_LLAMA_BACKEND_NOT_READY:
    return "llama_backend_not_ready";
  case BRIDGE_STATUS_MODEL_ALREADY_LOADED:
    return "model_already_loaded";
  case BRIDGE_STATUS_MODEL_NOT_LOADED:
    return "model_not_loaded";
  case BRIDGE_STATUS_MODEL_LOAD_FAILED:
    return "model_load_failed";
  case BRIDGE_STATUS_CONTEXT_INIT_FAILED:
    return "context_init_failed";
  case BRIDGE_STATUS_SAMPLER_INIT_FAILED:
    return "sampler_init_failed";
  case BRIDGE_STATUS_GENERATION_IN_PROGRESS:
    return "generation_in_progress";
  case BRIDGE_STATUS_TOKENIZE_FAILED:
    return "tokenize_failed";
  case BRIDGE_STATUS_DECODE_FAILED:
    return "decode_failed";
  default:
    return "unknown_status";
  }
}

int bridge_echo_alloc(const char *input, char **out_string) {
  if (out_string != nullptr) {
    *out_string = nullptr;
  }
  const int input_status = validate_input(input);
  if (input_status != BRIDGE_STATUS_OK) {
    return input_status;
  }

  const std::string message = std::string("native_echo: ") + input;
  return copy_to_native_string(message, out_string);
}

void bridge_string_free(char *ptr) {
  if (ptr == nullptr) {
    return;
  }
  std::free(ptr);
}

int bridge_llama_runtime_info_alloc(char **out_string) {
  if (out_string != nullptr) {
    *out_string = nullptr;
  }

  std::lock_guard<std::mutex> lock(g_llama_backend_mutex);
  if (g_llama_backend_users <= 0) {
    return BRIDGE_STATUS_LLAMA_BACKEND_NOT_READY;
  }

  const char *runtime_info_cstr = llama_print_system_info();
  if (runtime_info_cstr == nullptr) {
    return BRIDGE_STATUS_ALLOCATION_FAILED;
  }

  const std::string runtime_info(runtime_info_cstr);
  return copy_to_native_string(runtime_info, out_string);
}

BridgeSession *bridge_session_create() {
  BridgeSession *session = new (std::nothrow) BridgeSession();
  if (session == nullptr) {
    return nullptr;
  }
  retain_llama_backend();
  return session;
}

void bridge_session_destroy(BridgeSession *session) {
  if (session == nullptr) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(session->mutex);
    unload_model_locked(session);
  }
  delete session;
  release_llama_backend();
}

int bridge_session_set_tag(BridgeSession *session, const char *tag) {
  if (session == nullptr || tag == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  if (std::strlen(tag) == 0) {
    return BRIDGE_STATUS_EMPTY_INPUT;
  }
  if (std::strlen(tag) > kMaxInputBytes) {
    return BRIDGE_STATUS_INPUT_TOO_LARGE;
  }

  std::lock_guard<std::mutex> lock(session->mutex);
  session->tag = tag;
  return BRIDGE_STATUS_OK;
}

int bridge_session_echo_alloc(BridgeSession *session, const char *input,
                              char **out_string) {
  if (out_string != nullptr) {
    *out_string = nullptr;
  }
  if (session == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }

  const int input_status = validate_input(input);
  if (input_status != BRIDGE_STATUS_OK) {
    return input_status;
  }

  std::string message;
  {
    std::lock_guard<std::mutex> lock(session->mutex);
    session->request_count += 1;
    message = "session[" + session->tag + "] #" +
              std::to_string(session->request_count) + ": " + input;
  }
  return copy_to_native_string(message, out_string);
}

int bridge_session_stream(BridgeSession *session, const char *input,
                          BridgeTokenCallback on_token, void *user_data) {
                          LOGI(
        "[llama_bridge] ENTER bridge_session_stream\n");
  LOGI("ENTER bridge_session_stream");
  if (session == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  if (on_token == nullptr) {
    return BRIDGE_STATUS_CALLBACK_NULL;
  }

  const int input_status = validate_input(input);
  if (input_status != BRIDGE_STATUS_OK) {
    return input_status;
  }

  llama_model *model = nullptr;
  llama_context *context = nullptr;
  llama_sampler *sampler = nullptr;
  {
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->model == nullptr || session->context == nullptr) {
      return BRIDGE_STATUS_MODEL_NOT_LOADED;
    }
    if (session->sampler == nullptr) {
      return BRIDGE_STATUS_SAMPLER_INIT_FAILED;
    }
    if (session->is_generating) {
      return BRIDGE_STATUS_GENERATION_IN_PROGRESS;
    }
    session->is_generating = true;
    session->abort_requested.store(false);
    session->request_count += 1;
    model = session->model;
    context = session->context;
    sampler = session->sampler;
    LOGI(
    "[llama_bridge] session validated model=%p context=%p sampler=%p\n",
    model,
    context,
    sampler);
  }

  auto finish_generation = [session]() {
    std::lock_guard<std::mutex> lock(session->mutex);
    session->is_generating = false;
  };

  const llama_vocab *vocab = llama_model_get_vocab(model);
  if (vocab == nullptr) {
    finish_generation();
    return BRIDGE_STATUS_MODEL_NOT_LOADED;
  }

  llama_memory_t memory = llama_get_memory(context);
  if (memory != nullptr) {
    llama_memory_clear(memory, false);
  }
  llama_sampler_reset(sampler);

  const int32_t prompt_len = static_cast<int32_t>(std::strlen(input));
  LOGI(
    "[llama_bridge] before tokenize prompt_len=%d input=%s\n",
    prompt_len,
    input);
  int32_t prompt_tokens_required =
      llama_tokenize(vocab, input, prompt_len, nullptr, 0, true, true);
  if (prompt_tokens_required == INT32_MIN) {
    finish_generation();
    return BRIDGE_STATUS_TOKENIZE_FAILED;
  }
  if (prompt_tokens_required < 0) {
    prompt_tokens_required = -prompt_tokens_required;
  }
  if (prompt_tokens_required <= 0) {
    finish_generation();
    return BRIDGE_STATUS_TOKENIZE_FAILED;
  }
  LOGI(
    "[llama_bridge] prompt_tokens_required=%d\n",
    prompt_tokens_required);

  std::vector<llama_token> prompt_tokens(
      static_cast<size_t>(prompt_tokens_required));
  const int32_t tokenized = llama_tokenize(
      vocab, input, prompt_len, prompt_tokens.data(), prompt_tokens_required,
      true, true);
  if (tokenized < 0) {
    finish_generation();
    return BRIDGE_STATUS_TOKENIZE_FAILED;
  }
  prompt_tokens.resize(static_cast<size_t>(tokenized));
  LOGI(
    "[llama_bridge] tokenized successfully token_count=%d\n",
    tokenized);
  if (prompt_tokens.empty()) {
    finish_generation();
    return BRIDGE_STATUS_TOKENIZE_FAILED;
  }

LOGI(
    "[llama_bridge] stream start prompt_tokens=%zu max_gen_tokens=%d",
    prompt_tokens.size(),
    kMaxGeneratedTokens);

// =========================
// INITIAL PROMPT BATCH
// =========================

llama_batch prompt_batch = llama_batch_init(
    static_cast<int32_t>(prompt_tokens.size()),
    0,
    1);

for (int i = 0; i < prompt_tokens.size(); ++i) {
    prompt_batch.token[i] = prompt_tokens[i];

    prompt_batch.pos[i] = i;

    prompt_batch.n_seq_id[i] = 1;

    prompt_batch.seq_id[i][0] = 0;

    prompt_batch.logits[i] =
        (i == prompt_tokens.size() - 1);
}

prompt_batch.n_tokens =
    static_cast<int32_t>(prompt_tokens.size());

if (llama_model_has_encoder(model)) {

    if (llama_encode(context, prompt_batch) != 0) {

        llama_batch_free(prompt_batch);

        finish_generation();

        return BRIDGE_STATUS_DECODE_FAILED;
    }

    llama_token decoder_start =
        llama_model_decoder_start_token(model);

    if (decoder_start == LLAMA_TOKEN_NULL) {
        decoder_start = llama_vocab_bos(vocab);
    }

    prompt_batch =
        llama_batch_get_one(&decoder_start, 1);
}

LOGI("BEFORE FIRST DECODE");

const int firstDecodeResult =
    llama_decode(context, prompt_batch);

LOGI(
    "AFTER FIRST DECODE result=%d",
    firstDecodeResult);

// ONLY free if batch came from llama_batch_init
llama_batch_free(prompt_batch);

if (firstDecodeResult < 0) {

    finish_generation();

    return BRIDGE_STATUS_DECODE_FAILED;
}

std::vector<char> piece_buffer(512);

int emitted_tokens = 0;

for (int i = 0; i < kMaxGeneratedTokens; ++i) {

    if (session->abort_requested.load()) {

        LOGI(
            "[llama_bridge] stream aborted at step=%d",
            i);

        break;
    }

    LOGI("sampling step=%d", i);

    llama_token token =
        llama_sampler_sample(sampler, context, -1);

    if (llama_vocab_is_eog(vocab, token)) {

        LOGI(
            "[llama_bridge] stream reached EOG at step=%d",
            i);

        break;
    }

    int32_t piece_len =
        llama_token_to_piece(
            vocab,
            token,
            piece_buffer.data(),
            static_cast<int32_t>(piece_buffer.size()),
            0,
            true);

    if (piece_len >
        static_cast<int32_t>(piece_buffer.size())) {

        piece_buffer.resize(
            static_cast<size_t>(piece_len));

        piece_len =
            llama_token_to_piece(
                vocab,
                token,
                piece_buffer.data(),
                static_cast<int32_t>(piece_buffer.size()),
                0,
                true);
    }

    if (piece_len <= 0) {

        finish_generation();

        return BRIDGE_STATUS_DECODE_FAILED;
    }

    const std::string piece(
        piece_buffer.data(),
        static_cast<size_t>(piece_len));
if (piece.find("<|im_end|>") != std::string::npos) {

    LOGI("Qwen stop token reached");

    break;
}
    LOGI(
        "[llama_bridge] sending token piece=%s",
        piece.c_str());

    on_token(piece.c_str(), user_data);

    emitted_tokens += 1;

    if (emitted_tokens == 1 ||
        emitted_tokens % 8 == 0) {

        LOGI(
            "[llama_bridge] emitted_tokens=%d",
            emitted_tokens);
    }

    llama_sampler_accept(sampler, token);

    // IMPORTANT:
    // llama_batch_get_one() batch must NOT be freed
    llama_batch token_batch =
        llama_batch_get_one(&token, 1);

    LOGI(
        "[llama_bridge] BEFORE LOOP DECODE step=%d",
        i);

    const int loopDecodeResult =
        llama_decode(context, token_batch);

    LOGI(
        "[llama_bridge] AFTER LOOP DECODE result=%d step=%d",
        loopDecodeResult,
        i);

    if (loopDecodeResult < 0) {

        finish_generation();

        return BRIDGE_STATUS_DECODE_FAILED;
    }
}

finish_generation();

LOGI(
    "[llama_bridge] stream done emitted_tokens=%d",
    emitted_tokens);

return BRIDGE_STATUS_OK;}

int bridge_session_load_model(BridgeSession *session, const char *model_path,
                              int n_ctx, int n_gpu_layers) {
  if (session == nullptr || model_path == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  if (std::strlen(model_path) == 0) {
    return BRIDGE_STATUS_EMPTY_INPUT;
  }
  if (std::strlen(model_path) > kMaxInputBytes) {
    return BRIDGE_STATUS_INPUT_TOO_LARGE;
  }

  std::lock_guard<std::mutex> lock(session->mutex);
  if (session->model != nullptr || session->context != nullptr) {
    return BRIDGE_STATUS_MODEL_ALREADY_LOADED;
  }

  llama_model_params model_params = llama_model_default_params();
  model_params.use_mmap = llama_supports_mmap();
  model_params.use_mlock = false;
  model_params.n_gpu_layers =
      llama_supports_gpu_offload() ? n_gpu_layers : 0;

  LOGI(
               "[llama_bridge] load_model path=%s use_mmap=%d n_gpu_layers=%d\n",
               model_path, model_params.use_mmap ? 1 : 0,
               model_params.n_gpu_layers);
  llama_model *model = llama_model_load_from_file(model_path, model_params);
  if (model == nullptr && model_params.use_mmap) {
    // Some devices fail mmap for large GGUF files in app storage.
    LOGI(
                 "[llama_bridge] load_model mmap failed, retrying with "
                 "use_mmap=0\n");
    model_params.use_mmap = false;
    model = llama_model_load_from_file(model_path, model_params);
  }
  if (model == nullptr) {
    LOGI(
                 "[llama_bridge] load_model failed after retries path=%s\n",
                 model_path);
    return BRIDGE_STATUS_MODEL_LOAD_FAILED;
  }

  llama_context_params ctx_params = llama_context_default_params();
  if (n_ctx > 0) {
    ctx_params.n_ctx = static_cast<uint32_t>(n_ctx);
    LOGI(
    "[llama_bridge] context configured n_ctx=%u\n",
    ctx_params.n_ctx);
  }
  ctx_params.n_threads = 8;
  ctx_params.n_threads_batch = 8;
  // Register an abort callback so bridge_session_abort_stream() can stop an
  // ongoing llama_decode call from another thread.
  ctx_params.abort_callback = [](void *data) -> bool {
    return reinterpret_cast<std::atomic<bool> *>(data)->load();
  };
  ctx_params.abort_callback_data = &session->abort_requested;

  llama_context *context = llama_init_from_model(model, ctx_params);
  if (context == nullptr) {
    llama_model_free(model);
    return BRIDGE_STATUS_CONTEXT_INIT_FAILED;
  }

  auto chain_params = llama_sampler_chain_default_params();
  chain_params.no_perf = true;
  llama_sampler *sampler = llama_sampler_chain_init(chain_params);
  if (sampler == nullptr) {
    llama_free(context);
    llama_model_free(model);
    return BRIDGE_STATUS_SAMPLER_INIT_FAILED;
  }
  llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
  llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95f, 1));
  llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.8f));
  llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

  session->model = model;
  session->context = context;
  session->sampler = sampler;
  session->loaded_model_path = model_path;
  return BRIDGE_STATUS_OK;
}

int bridge_session_unload_model(BridgeSession *session) {
  if (session == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  std::lock_guard<std::mutex> lock(session->mutex);
  if (session->model == nullptr && session->context == nullptr) {
    return BRIDGE_STATUS_MODEL_NOT_LOADED;
  }
  unload_model_locked(session);
  return BRIDGE_STATUS_OK;
}

int bridge_session_model_info_alloc(BridgeSession *session, char **out_string) {
  if (out_string != nullptr) {
    *out_string = nullptr;
  }
  if (session == nullptr || out_string == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }

  std::lock_guard<std::mutex> lock(session->mutex);
  if (session->model == nullptr || session->context == nullptr) {
    return BRIDGE_STATUS_MODEL_NOT_LOADED;
  }

  const int32_t n_ctx_train = llama_model_n_ctx_train(session->model);
  const uint32_t n_ctx_runtime = llama_n_ctx(session->context);
  const bool gpu_offload = llama_supports_gpu_offload();
  std::string info = "model_path=" + session->loaded_model_path +
                     "; n_ctx_train=" + std::to_string(n_ctx_train) +
                     "; n_ctx_runtime=" + std::to_string(n_ctx_runtime) +
                     "; gpu_offload_supported=" + (gpu_offload ? "true" : "false");
  return copy_to_native_string(info, out_string);
}

int bridge_session_abort_stream(BridgeSession *session) {
  if (session == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  session->abort_requested.store(true);
  LOGI( "[llama_bridge] abort_stream requested\n");
  return BRIDGE_STATUS_OK;
}