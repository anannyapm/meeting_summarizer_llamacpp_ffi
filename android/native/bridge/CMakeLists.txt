cmake_minimum_required(VERSION 3.22.1)

project(llama_bridge)

set(CMAKE_CXX_STANDARD 17)

# Phase 6: compile llama.cpp as part of the bridge.
set(LLAMA_BUILD_TESTS OFF)
set(LLAMA_BUILD_EXAMPLES OFF)
set(LLAMA_BUILD_SERVER OFF)
set(LLAMA_BUILD_TOOLS OFF)
set(LLAMA_BUILD_COMMON OFF)
set(GGML_LLAMAFILE OFF)

# Android NDK cross-compiles with CMAKE_CROSSCOMPILING=ON, which disables
# GGML_NATIVE and leaves GGML_CPU_ARM_ARCH empty — ggml then builds ARM quants
# without -march flags (very slow scalar fallback). Apply -march only on
# arm64-v8a; armeabi-v7a hits vcvtnq_s32_f32 redefinition with NDK 28+.
if(ANDROID AND ANDROID_ABI STREQUAL "arm64-v8a")
    set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
endif()

add_subdirectory(
    ../llama.cpp
    llama_build
)

add_library(
    llama_bridge
    SHARED
    llama_bridge.cpp
)

target_link_libraries(
    llama_bridge
    llama
    android
    log
)