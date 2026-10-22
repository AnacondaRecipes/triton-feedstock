#!/bin/bash

set -ex

# remove outdated vendored headers
rm -rf $SRC_DIR/python/triton/third_party

# Hermetic build: do not let triton download its prebuilt LLVM image or the
# Blackwell CUDA tools at build time. We build LLVM from source (the llvm-project
# source entry) and provide the CUDA tools from the host environment below.
export TRITON_OFFLINE_BUILD=1

export JSON_SYSPATH=$PREFIX

# only some of them are actually used currently, but set all just in case
export TRITON_PTXAS_PATH=$PREFIX/bin/ptxas
export TRITON_CUOBJDUMP_PATH=$PREFIX/bin/cuobjdump
export TRITON_NVDISASM_PATH=$PREFIX/bin/nvdisasm
export TRITON_CUDACRT_PATH=$PREFIX
export TRITON_CUDART_PATH=$PREFIX
export TRITON_CUPTI_INCLUDE_PATH=$PREFIX/include
export TRITON_CUPTI_LIB_PATH=$PREFIX/lib

export MAX_JOBS=$CPU_COUNT

# Cleanup caches, helpful to avoid previous build leftovers during development.
rm -rf /tmp/.triton/ || true
rm -rf ~/.triton/ || true
rm -rf /tmp/triton* || true
rm -rf build/
rm -rf dist/
rm -rf *.egg-info/

# --- Build LLVM from source (hermetic; replaces triton's prebuilt download) ---
# Built BEFORE we set triton's assertion CXXFLAGS / stub LDFLAGS below, so LLVM
# compiles with clean conda toolchain flags. Projects/targets are the minimal set
# triton needs (mlir + lld; host + NVPTX for CUDA + AMDGPU). Flags modeled on
# conda-forge's triton recipe.
CMAKE_LLVM_ARGS=(
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DLLVM_BUILD_UTILS=ON
    -DLLVM_BUILD_TOOLS=OFF
    -DLLD_BUILD_TOOLS=OFF
    -DLLVM_BUILD_TELEMETRY=OFF
    # clang is required: triton's nvidia backend find_program()s clang++ in
    # ${LLVM_SYSPATH}/bin to compile its gsan device runtime (third_party/nvidia/
    # CMakeLists.txt). Matches triton's own scripts/build-llvm-project.sh.
    -DLLVM_ENABLE_PROJECTS="mlir;lld;clang"
    -DLLVM_TARGETS_TO_BUILD="host;NVPTX;AMDGPU"
    -DLLVM_ENABLE_TERMINFO=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DMLIR_INCLUDE_TESTS=OFF
)
cmake "${CMAKE_LLVM_ARGS[@]}" -B llvm-project/build -S llvm-project/llvm
cmake --build llvm-project/build -j "${MAX_JOBS}"

export LLVM_SYSPATH=$PWD/llvm-project/build
export LLVM_INCLUDE_DIRS=$LLVM_SYSPATH/include
export LLVM_LIBRARY_DIR=$LLVM_SYSPATH/lib

# --- AMD codegen library (new in 3.9) ---
# Upstream downloads a prebuilt libtriton_amd_codegen.so built against a separate
# AMD LLVM pin (cmake/amd-llvm-info.json), which fails offline. Build it from the
# in-tree source against our LLVM above (AMDGPU target enabled) instead.
AMD_CODEGEN_LIB=$SRC_DIR/third_party/amd/backend/lib/libtriton_amd_codegen.so
# -Wl,-s for the same reason as libtriton.so below (statically-linked LLVM symbols).
LDFLAGS="$LDFLAGS -Wl,-s" cmake -G Ninja -B amd-codegen-build -S third_party/amd/backend/codegen \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_DIR=$LLVM_SYSPATH/lib/cmake/llvm \
    -DCMAKE_INSTALL_PREFIX=$SRC_DIR/amd-codegen-build/install \
    -DTRITON_AMD_LLVM_REVISION=$($PYTHON -c "import json; print(json.load(open('cmake/llvm-info.json'))['llvm_hash'])")
cmake --build amd-codegen-build --target install -j "${MAX_JOBS}"
cp amd-codegen-build/install/lib/libtriton_amd_codegen.so $AMD_CODEGEN_LIB
# Non-empty path makes build_helpers.py skip its download; the copy above is what ships.
export TRITON_AMD_CODEGEN_PATH=$AMD_CODEGEN_LIB

# --- Build triton against the freshly-built LLVM ---
# GCC version missing __glibcxx_assert_fail function. We'll create a stub for it.
cat > $SRC_DIR/glibcxx_assert_stub.cpp << 'EOF'
#include <cstdio>
#include <cstdlib>

namespace std {
  [[noreturn]] void __glibcxx_assert_fail(const char* file, int line,
                                          const char* function, const char* condition) {
    fprintf(stderr, "Assertion failed: %s at %s:%d in %s\n", condition, file, line, function);
    abort();
  }
}
EOF

# Compile the stub into an object file
$CXX -c $SRC_DIR/glibcxx_assert_stub.cpp -o $SRC_DIR/glibcxx_assert_stub.o -fPIC

export CXXFLAGS="-D_GLIBCXX_ASSERTIONS $CXXFLAGS"
export CPPFLAGS="-I$BUILD_PREFIX/include $CPPFLAGS"
# -Wl,-s strips symbols at link time: statically-linked LLVM adds a large symbol
# table to libtriton.so and conda-build does not strip it in post-processing.
export LDFLAGS="$SRC_DIR/glibcxx_assert_stub.o -L$BUILD_PREFIX/lib -Wl,-rpath,$BUILD_PREFIX/lib -Wl,-s $LDFLAGS"

# the build does not run C++ unittests, and they implicitly fetch gtest
# no easy way of passing this, not really worth a whole patch
sed -i -e '/TRITON_BUILD_UT/s:\bON:OFF:' CMakeLists.txt

$PYTHON -m pip install . -vv --no-deps --no-build-isolation
