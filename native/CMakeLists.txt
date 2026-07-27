cmake_minimum_required(VERSION 3.26.4)
project(sogen_dart LANGUAGES C CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT SOGEN_SOURCE_DIR)
  set(SOGEN_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../build/deps/sogen")
endif()
get_filename_component(SOGEN_SOURCE_DIR "${SOGEN_SOURCE_DIR}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")

if(NOT EXISTS "${SOGEN_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "Sogen was not found at ${SOGEN_SOURCE_DIR}. Run tool/bootstrap_native.ps1 first.")
endif()

set(SOGEN_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(SOGEN_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_PYTHON_BINDINGS OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_LTO OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_RUST_CODE OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_REFLECTION OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_STEAM OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_FUZZING OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_SANITIZER OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_CLANG_TIDY OFF CACHE BOOL "" FORCE)
set(SOGEN_ENABLE_SDL3 ON CACHE BOOL "" FORCE)
set(SOGEN_USE_SYSTEM_SDL3 OFF CACHE BOOL "" FORCE)

block(SCOPE_FOR VARIABLES)
  set(BUILD_SHARED_LIBS OFF)
  add_subdirectory("${SOGEN_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/deps/sogen" EXCLUDE_FROM_ALL)
endblock()

# Pinned Sogen uses CMAKE_SOURCE_DIR for these includes, which points at this
# adapter when Sogen is embedded as a subproject.
target_include_directories(disassembler PUBLIC "${SOGEN_SOURCE_DIR}/src/emulator")
target_include_directories(emulator-platform INTERFACE "${SOGEN_SOURCE_DIR}/src")

add_library(sogen_dart SHARED
  src/api_hook_registry.cpp
  src/error.cpp
  src/linux_core.cpp
  src/linux_callbacks.cpp
  src/linux_factory.cpp
  src/linux_models.cpp
  src/linux_runtime.cpp
  src/lookup.cpp
  src/sogen_dart.cpp
  src/windows_callbacks.cpp
)

target_include_directories(sogen_dart
  PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(sogen_dart PRIVATE
  windows-emulator
  linux-emulator
  disassembler
  backend-selection
  ${CMAKE_DL_LIBS}
)
target_compile_features(sogen_dart PRIVATE cxx_std_20)

if(MSVC)
  target_compile_options(sogen_dart PRIVATE /W4 /permissive-)
else()
  target_compile_options(sogen_dart PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(BUILD_TESTING)
  add_executable(sogen_dart_abi_test test/abi_test.cpp)
  target_link_libraries(sogen_dart_abi_test PRIVATE sogen_dart)
  target_compile_features(sogen_dart_abi_test PRIVATE cxx_std_20)
  add_test(NAME sogen_dart_abi COMMAND sogen_dart_abi_test)
endif()
