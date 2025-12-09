#!/bin/bash

set -ex

# remove outdated vendored headers
rm -rf $SRC_DIR/python/triton/third_party

export JSON_SYSPATH=$PREFIX
export PYBIND11_SYSPATH=$SP_DIR/pybind11

# these don't seem to be actually used, but they prevent downloads
export TRITON_PTXAS_PATH=$PREFIX/bin/ptxas
export TRITON_CUOBJDUMP_PATH=$PREFIX/bin/cuobjdump
export TRITON_NVDISASM_PATH=$PREFIX/bin/nvdisasm
export TRITON_CUDACRT_PATH=$PREFIX
export TRITON_CUDART_PATH=$PREFIX/targets/x86_64-linux/include
export TRITON_CUPTI_PATH=$PREFIX
export TRITON_CACHE_DIR=/tmp/.triton
export MAX_JOBS=$CPU_COUNT

rm -rf /tmp/.triton/
rm -rf ~/.triton/
rm -rf /tmp/triton*
rm -rf build/
rm -rf dist/
rm -rf *.egg-info/

export TRITON_BUILD_WITH_CLANG_LLD=false
export TRITON_BUILD_WITH_CCACHE=false
export CC="$BUILD_PREFIX/bin/x86_64-conda-linux-gnu-gcc"
export CXX="$BUILD_PREFIX/bin/x86_64-conda-linux-gnu-g++"

# GCC version missing __glibcxx_assert_fail function. We'll create a stub for it.
cat > /tmp/glibcxx_assert_stub.cpp << 'EOF'
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
$CXX -c /tmp/glibcxx_assert_stub.cpp -o /tmp/glibcxx_assert_stub.o -fPIC

export CXXFLAGS="-D_GLIBCXX_ASSERTIONS $CXXFLAGS"
export CPPFLAGS="-I$BUILD_PREFIX/include $CPPFLAGS"
export LDFLAGS="/tmp/glibcxx_assert_stub.o -L$BUILD_PREFIX/lib -Wl,-rpath,$BUILD_PREFIX/lib $LDFLAGS"

# the build does not run C++ unittests, and they implicitly fetch gtest
# no easy way of passing this, not really worth a whole patch
sed -i -e '/TRITON_BUILD_UT/s:\bON:OFF:' CMakeLists.txt

cd python
$PYTHON -m pip install . -vv --no-deps --no-build-isolation
