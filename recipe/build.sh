#!/bin/bash

set -ex

# remove outdated vendored headers
rm -rf $SRC_DIR/python/triton/third_party

# direct CMake towards LLVM library directory
export LLVM_DIR="$SRC_DIR"

#Turn off optimizations
export CFLAGS="$(echo $CFLAGS | sed 's/-O[0-9]//g')"
export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-O[0-9]//g')"

# the vendored-in llvm on centos is compiled with the pre-C++11 ABI, leading to linker errors if we don't include this
export CFLAGS="${CFLAGS} -D_GLIBCXX_USE_CXX11_ABI=0"
export CXXFLAGS="${CXXFLAGS} -D_GLIBCXX_USE_CXX11_ABI=0"

cd python
$PYTHON -m pip install . --no-deps --no-build-isolation --ignore-installed --no-cache-dir -vv
