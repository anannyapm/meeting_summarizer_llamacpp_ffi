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