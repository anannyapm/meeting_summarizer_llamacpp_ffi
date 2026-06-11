#include "llama_bridge.h"

#include "../llama.cpp/include/llama.h"
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "llama_bridge", __VA_ARGS__)

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <climits>
#include <cstdio>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <new>
#include <string>
#include <thread>
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
  std::condition_variable generation_done;
  // Atomic abort flag — set from any thread, checked by the llama.cpp abort
  // callback after each decode step so generation stops promptly.
  std::atomic<bool> abort_requested{false};
};

namespace {
#ifndef NDEBUG
#define BRIDGE_VERBOSE_LOG(...) LOGI(__VA_ARGS__)
#else
#define BRIDGE_VERBOSE_LOG(...) ((void)0)
#endif

constexpr const char *kBridgeVersion = "ffi-bridge-phase8";
constexpr size_t kMaxInputBytes = 8192;
constexpr int kDefaultMaxGeneratedTokens = 512;
constexpr size_t kMaxChatPromptBytes = 65536;
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

int normalize_max_tokens(int max_tokens) {
  if (max_tokens <= 0) {
    return kDefaultMaxGeneratedTokens;
  }
  return max_tokens;
}

int validate_chat_prompt(const char *system_prompt, const char *user_prompt) {
  if (system_prompt == nullptr || user_prompt == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  const size_t total_len = std::strlen(system_prompt) + std::strlen(user_prompt);
  if (total_len == 0) {
    return BRIDGE_STATUS_EMPTY_INPUT;
  }
  if (total_len > kMaxChatPromptBytes) {
    return BRIDGE_STATUS_INPUT_TOO_LARGE;
  }
  return BRIDGE_STATUS_OK;
}

std::string build_chat_prompt(llama_model *model, const char *system_prompt,
                              const char *user_prompt) {
  const char *tmpl = llama_model_chat_template(model, nullptr);
  llama_chat_message messages[2] = {
      {"system", system_prompt},
      {"user", user_prompt},
  };

  if (tmpl != nullptr && std::strlen(tmpl) > 0) {
    const int32_t required = llama_chat_apply_template(
        tmpl, messages, 2, true, nullptr, 0);
    if (required > 0) {
      std::vector<char> buffer(static_cast<size_t>(required) + 1);
      const int32_t written = llama_chat_apply_template(
          tmpl, messages, 2, true, buffer.data(),
          static_cast<int32_t>(buffer.size()));
      if (written > 0) {
        return std::string(buffer.data(), static_cast<size_t>(written));
      }
    }
  }

  LOGI("[llama_bridge] chat template missing; using plain prompt fallback");
  return std::string("System: ") + system_prompt + "\nUser: " + user_prompt +
         "\nAssistant:";
}

int run_stream_with_prompt(BridgeSession *session, llama_model *model,
                           llama_context *context, llama_sampler *sampler,
                           const std::string &prompt, int max_tokens,
                           BridgeTokenCallback on_token, void *user_data,
                           const std::function<void()> &finish_generation) {
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

  const int32_t prompt_len = static_cast<int32_t>(prompt.size());
  int32_t prompt_tokens_required =
      llama_tokenize(vocab, prompt.c_str(), prompt_len, nullptr, 0, true, true);
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

  std::vector<llama_token> prompt_tokens(
      static_cast<size_t>(prompt_tokens_required));
  const int32_t tokenized = llama_tokenize(
      vocab, prompt.c_str(), prompt_len, prompt_tokens.data(),
      prompt_tokens_required, true, true);
  if (tokenized < 0) {
    finish_generation();
    return BRIDGE_STATUS_TOKENIZE_FAILED;
  }
  prompt_tokens.resize(static_cast<size_t>(tokenized));
  if (prompt_tokens.empty()) {
    finish_generation();
    return BRIDGE_STATUS_TOKENIZE_FAILED;
  }

  const int gen_limit = normalize_max_tokens(max_tokens);
  const uint32_t runtime_ctx = llama_n_ctx(context);
  LOGI(
      "[llama_bridge] stream start prompt_tokens=%zu max_gen=%d n_ctx=%u",
      prompt_tokens.size(), gen_limit, runtime_ctx);

  const int n_prompt = static_cast<int>(prompt_tokens.size());
  const int n_batch = static_cast<int>(llama_n_batch(context));
  const int kPrefillBatch = std::max(1, std::min(32, n_batch));
  const bool single_batch_prefill = (n_prompt <= 64);
  const int prefill_step =
      single_batch_prefill ? n_prompt : kPrefillBatch;
  LOGI(
      "[llama_bridge] prefill decode start n_tokens=%d batch=%d n_batch=%d "
      "single_batch=%d",
      n_prompt, prefill_step, n_batch, single_batch_prefill ? 1 : 0);

  const auto prefill_start = std::chrono::steady_clock::now();
  for (int i = 0; i < n_prompt; i += prefill_step) {
    if (session->abort_requested.load()) {
      LOGI("[llama_bridge] prefill aborted at token %d", i);
      finish_generation();
      return BRIDGE_STATUS_OK;
    }

    const int chunk = std::min(prefill_step, n_prompt - i);
    const auto chunk_start = std::chrono::steady_clock::now();
    llama_batch prompt_batch = llama_batch_init(chunk, 0, 1);
    for (int j = 0; j < chunk; ++j) {
      prompt_batch.token[j] = prompt_tokens[static_cast<size_t>(i + j)];
      prompt_batch.pos[j] = i + j;
      prompt_batch.n_seq_id[j] = 1;
      prompt_batch.seq_id[j][0] = 0;
      prompt_batch.logits[j] = (j == chunk - 1);
    }
    prompt_batch.n_tokens = chunk;

    const int decode_result = llama_decode(context, prompt_batch);
    llama_batch_free(prompt_batch);
    const auto chunk_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                              std::chrono::steady_clock::now() - chunk_start)
                              .count();
    LOGI(
        "[llama_bridge] prefill chunk offset=%d size=%d decode_ms=%lld result=%d",
        i, chunk, static_cast<long long>(chunk_ms), decode_result);
    if (decode_result != 0) {
      if (decode_result < 0) {
        LOGI("[llama_bridge] prefill decode failed at=%d result=%d", i,
             decode_result);
        finish_generation();
        return BRIDGE_STATUS_DECODE_FAILED;
      }
      // decode_result == 1: cooperative abort from abort_callback.
      LOGI("[llama_bridge] prefill aborted by callback at=%d", i);
      finish_generation();
      return BRIDGE_STATUS_OK;
    }
  }
  const auto prefill_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                              std::chrono::steady_clock::now() - prefill_start)
                              .count();
  const double prefill_tok_per_s =
      prefill_ms > 0
          ? (static_cast<double>(n_prompt) * 1000.0 /
             static_cast<double>(prefill_ms))
          : 0.0;
  LOGI(
      "[llama_bridge] prefill decode done total_ms=%lld tok_per_s=%.1f "
      "n_tokens=%d",
      static_cast<long long>(prefill_ms), prefill_tok_per_s, n_prompt);

  std::vector<char> piece_buffer(512);
  int emitted_tokens = 0;

  for (int i = 0; i < gen_limit; ++i) {
    if (session->abort_requested.load()) {
      break;
    }

    llama_token token = llama_sampler_sample(sampler, context, -1);
    if (llama_vocab_is_eog(vocab, token)) {
      break;
    }

    int32_t piece_len = llama_token_to_piece(
        vocab, token, piece_buffer.data(),
        static_cast<int32_t>(piece_buffer.size()), 0, true);
    if (piece_len > static_cast<int32_t>(piece_buffer.size())) {
      piece_buffer.resize(static_cast<size_t>(piece_len));
      piece_len = llama_token_to_piece(
          vocab, token, piece_buffer.data(),
          static_cast<int32_t>(piece_buffer.size()), 0, true);
    }
    if (piece_len <= 0) {
      finish_generation();
      return BRIDGE_STATUS_DECODE_FAILED;
    }

    const std::string piece(piece_buffer.data(),
                            static_cast<size_t>(piece_len));
    if (emitted_tokens == 0) {
      LOGI("[llama_bridge] first token emitted len=%d", piece_len);
    }
    on_token(piece.c_str(), user_data);
    emitted_tokens += 1;

    llama_sampler_accept(sampler, token);
    llama_batch token_batch = llama_batch_get_one(&token, 1);
    const int loopDecodeResult = llama_decode(context, token_batch);
    if (loopDecodeResult < 0) {
      finish_generation();
      return BRIDGE_STATUS_DECODE_FAILED;
    }
  }

  finish_generation();
  BRIDGE_VERBOSE_LOG("[llama_bridge] stream done emitted_tokens=%d",
                     emitted_tokens);
  return BRIDGE_STATUS_OK;
}

void wait_for_generation_locked(std::unique_lock<std::mutex> &lock,
                              BridgeSession *session) {
  session->abort_requested.store(true);
  while (session->is_generating) {
    session->generation_done.wait(lock);
  }
}

int default_thread_count() {
  const unsigned hw = std::thread::hardware_concurrency();
  if (hw <= 2) {
    return 1;
  }
  const int threads = static_cast<int>(hw) - 2;
#if defined(__ANDROID__)
  // Use more big cores on modern phones; 2 threads was too conservative.
  return std::min(4, std::max(2, threads));
#else
  return std::min(4, std::max(1, threads));
#endif
}

void warmup_context(llama_model *model, llama_context *context) {
  const llama_vocab *vocab = llama_model_get_vocab(model);
  if (vocab == nullptr) {
    return;
  }

  llama_memory_t memory = llama_get_memory(context);
  if (memory != nullptr) {
    llama_memory_clear(memory, false);
  }

  const char *warmup_text = "Hi";
  llama_token tokens[8];
  const int32_t tokenized = llama_tokenize(
      vocab, warmup_text, 2, tokens, 8, true, true);
  if (tokenized <= 0) {
    LOGI("[llama_bridge] warmup skipped (tokenize failed)");
    return;
  }

  llama_batch batch = llama_batch_init(tokenized, 0, 1);
  for (int i = 0; i < tokenized; ++i) {
    batch.token[i] = tokens[i];
    batch.pos[i] = i;
    batch.n_seq_id[i] = 1;
    batch.seq_id[i][0] = 0;
    batch.logits[i] = (i == tokenized - 1);
  }
  batch.n_tokens = tokenized;

  const auto start = std::chrono::steady_clock::now();
  const int decode_result = llama_decode(context, batch);
  llama_batch_free(batch);
  const auto warmup_ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - start)
          .count();
  LOGI(
      "[llama_bridge] warmup decode tokens=%d ms=%lld result=%d",
      tokenized, static_cast<long long>(warmup_ms), decode_result);

  if (memory != nullptr) {
    llama_memory_clear(memory, false);
  }
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
    std::unique_lock<std::mutex> lock(session->mutex);
    wait_for_generation_locked(lock, session);
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

int begin_generation(BridgeSession *session, llama_model **out_model,
                   llama_context **out_context, llama_sampler **out_sampler) {
  if (session == nullptr || out_model == nullptr || out_context == nullptr ||
      out_sampler == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
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
  *out_model = session->model;
  *out_context = session->context;
  *out_sampler = session->sampler;
  return BRIDGE_STATUS_OK;
}

int bridge_session_stream(BridgeSession *session, const char *input,
                          int max_tokens, BridgeTokenCallback on_token,
                          void *user_data) {
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
  const int begin_status =
      begin_generation(session, &model, &context, &sampler);
  if (begin_status != BRIDGE_STATUS_OK) {
    return begin_status;
  }

  auto finish_generation = [session]() {
    std::lock_guard<std::mutex> lock(session->mutex);
    session->is_generating = false;
    session->generation_done.notify_all();
  };

  return run_stream_with_prompt(session, model, context, sampler,
                                std::string(input), max_tokens, on_token,
                                user_data, finish_generation);
}

int bridge_session_stream_chat(BridgeSession *session,
                               const char *system_prompt,
                               const char *user_prompt, int max_tokens,
                               BridgeTokenCallback on_token, void *user_data) {
  if (session == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  if (on_token == nullptr) {
    return BRIDGE_STATUS_CALLBACK_NULL;
  }

  const int prompt_status = validate_chat_prompt(system_prompt, user_prompt);
  if (prompt_status != BRIDGE_STATUS_OK) {
    return prompt_status;
  }

  llama_model *model = nullptr;
  llama_context *context = nullptr;
  llama_sampler *sampler = nullptr;
  const int begin_status =
      begin_generation(session, &model, &context, &sampler);
  if (begin_status != BRIDGE_STATUS_OK) {
    return begin_status;
  }

  auto finish_generation = [session]() {
    std::lock_guard<std::mutex> lock(session->mutex);
    session->is_generating = false;
    session->generation_done.notify_all();
  };

  const std::string prompt =
      build_chat_prompt(model, system_prompt, user_prompt);
  return run_stream_with_prompt(session, model, context, sampler, prompt,
                                max_tokens, on_token, user_data,
                                finish_generation);
}

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
  const int thread_count = default_thread_count();
  LOGI("[llama_bridge] using n_threads=%d", thread_count);
  ctx_params.n_threads = thread_count;
  ctx_params.n_threads_batch = thread_count;
  ctx_params.n_batch = 64;
  ctx_params.n_ubatch = 64;
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
  // Repeat penalty reduces transcript echo on small instruct models; greedy
  // keeps decode fast on CPU.
  llama_sampler_chain_add(
      sampler, llama_sampler_init_penalties(
                   /*penalty_last_n*/ 64, /*penalty_repeat*/ 1.18f,
                   /*penalty_freq*/ 0.0f, /*penalty_present*/ 0.0f));
  llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

  session->model = model;
  session->context = context;
  session->sampler = sampler;
  session->loaded_model_path = model_path;

  // Touch mmap'd weights during load so first real prefill is not 60s+ I/O.
  warmup_context(model, context);

  return BRIDGE_STATUS_OK;
}

int bridge_session_unload_model(BridgeSession *session) {
  if (session == nullptr) {
    return BRIDGE_STATUS_NULL_ARG;
  }
  std::unique_lock<std::mutex> lock(session->mutex);
  if (session->model == nullptr && session->context == nullptr) {
    return BRIDGE_STATUS_MODEL_NOT_LOADED;
  }
  wait_for_generation_locked(lock, session);
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