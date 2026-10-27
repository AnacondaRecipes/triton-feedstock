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

# Keep triton's build cache (TRITON_HOME/.triton) inside the work dir instead of
# the worker's ~/.triton, so no shared paths need cleaning up.
export TRITON_HOME=$SRC_DIR

# Cleanup build leftovers, helpful during development.
rm -rf build/
rm -rf dist/
rm -rf *.egg-info/

# --- Build LLVM from source (hermetic; replaces triton's prebuilt download) ---
# Built BEFORE we set triton's assertion CXXFLAGS / stub LDFLAGS below, so LLVM
# compiles with clean conda toolchain flags. Projects/targets are the minimal set
# triton needs (mlir + lld; host + NVPTX for CUDA, plus AMDGPU because libtriton
# links LLVMAMDGPUCodeGen unconditionally even though we only install the nvidia
# backend, see patch 0005). Flags modeled on conda-forge's triton recipe.
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

# Third-party notices for code compiled into libtriton.so from the nanobind host
# package (its static library and bundled robin_map), listed in about/license_file.
mkdir -p host-licenses
cp $SP_DIR/nanobind-*.dist-info/licenses/LICENSE host-licenses/nanobind-LICENSE
# robin_map's MIT notice is only shipped as the header comment of robin_map.h
sed -n '2,/^ \*\/$/p' $SP_DIR/nanobind/ext/robin_map/include/tsl/robin_map.h \
    | sed -e '$d' -e 's/^ \* \{0,1\}//' > host-licenses/robin_map-LICENSE
# nlohmann_json (header-only, compiled into libproton): its MIT text comes from a source
# entry; collect the copyright holders named in its headers
(
  set -o pipefail
  grep -rh '^// SPDX-FileCopyrightText:' "$PREFIX/include/nlohmann" \
    | sed 's|^// ||' | LC_ALL=C sort -u \
    > host-licenses/nlohmann_json-COPYRIGHTS
)
test -s host-licenses/nlohmann_json/LICENSE.MIT
test -s host-licenses/nlohmann_json-COPYRIGHTS
# Separately licensed LLVM Support sources compiled into the shipped binaries; LLVM's
# LICENSE.TXT says such code carries its own notice in the file header
"$PYTHON" - <<'PY'
from pathlib import Path

support = Path('llvm-project/llvm/lib/Support')
names = ('xxhash.cpp', 'ConvertUTF.cpp', 'regcomp.c', 'regerror.c',
         'regexec.c', 'regfree.c', 'regstrlcpy.c')
parts = ['These sources include modifications made by the LLVM Project.\n']
for name in names:
    path = support / name
    text = path.read_text().split('#include', 1)[0]
    assert text.strip() and 'copyright' in text.lower(), path
    parts.append('\n' + str(path) + '\n' + text)
Path('host-licenses/llvm-support-LICENSES').write_text(''.join(parts))
PY

$PYTHON -m pip install . -vv --no-deps --no-build-isolation
