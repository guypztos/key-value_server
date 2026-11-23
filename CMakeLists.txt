cmake_minimum_required(VERSION 4.0)
project(kv_server LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Plain ISO C++20 (-std=c++20), not the GNU dialect (-std=gnu++20).
set(CMAKE_CXX_EXTENSIONS OFF)
# Writes build/<preset>/compile_commands.json, which clang-tidy reads.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
# For C++20, CMake scans every file for module imports before compiling it. This project
# uses headers, not modules, so the scan would be two wasted build steps per file.
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)

option(KV_SANITIZE "Build with AddressSanitizer and UndefinedBehaviorSanitizer" OFF)
option(KV_COVERAGE "Build with clang source-based coverage instrumentation" OFF)
option(KV_CLANG_TIDY "Run clang-tidy on each source file as it is compiled" OFF)

# kv_build_flags carries the flags for our own targets. Targets opt in by linking it,
# so third-party code (GoogleTest) is never compiled with our warnings or -Werror.
add_library(kv_build_flags INTERFACE)
target_compile_options(kv_build_flags INTERFACE -Wall -Wextra -Wpedantic -Werror)

if(KV_SANITIZE)
  # -fno-sanitize-recover=all: UBSan aborts on the first finding. By default it prints a
  #   message and carries on, so the test would still pass.
  # -fno-omit-frame-pointer: keeps sanitizer stack traces complete.
  set(kv_sanitizer_flags -fsanitize=address,undefined -fno-sanitize-recover=all
                         -fno-omit-frame-pointer)
  target_compile_options(kv_build_flags INTERFACE ${kv_sanitizer_flags})
  target_link_options(kv_build_flags INTERFACE ${kv_sanitizer_flags})
endif()

if(KV_COVERAGE)
  set(kv_coverage_flags -fprofile-instr-generate -fcoverage-mapping)
  target_compile_options(kv_build_flags INTERFACE ${kv_coverage_flags})
  target_link_options(kv_build_flags INTERFACE ${kv_coverage_flags})
endif()

if(KV_CLANG_TIDY)
  # CMake runs clang-tidy next to the compiler for every file. Because it is part of the
  # compile step, Ninja skips it for files that have not changed.
  find_program(KV_CLANG_TIDY_EXECUTABLE clang-tidy REQUIRED)
  # --quiet drops the "N warnings generated / suppressed" summary; findings still print.
  set(CMAKE_CXX_CLANG_TIDY "${KV_CLANG_TIDY_EXECUTABLE};--quiet")
endif()

# Makes the given sources rebuild (and so be linted again) when a clang-tidy config file
# changes. Without this, editing .clang-tidy would not re-check files that are up to date.
function(kv_relint_on_config_change)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "SOURCES;CONFIGS")
  if(KV_CLANG_TIDY)
    set_source_files_properties(${arg_SOURCES} PROPERTIES OBJECT_DEPENDS "${arg_CONFIGS}")
  endif()
endfunction()

set(kv_core_sources src/version.cpp)
add_library(kv_core STATIC ${kv_core_sources})
target_include_directories(kv_core PUBLIC include)
target_link_libraries(kv_core PRIVATE kv_build_flags)
kv_relint_on_config_change(SOURCES ${kv_core_sources} CONFIGS "${CMAKE_SOURCE_DIR}/.clang-tidy")

enable_testing()
add_subdirectory(tests)
