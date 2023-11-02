#!/bin/bash

set -ex

# remove outdated vendored headers
rm -rf $SRC_DIR/python/triton/third_party

# direct CMake towards LLVM library directory
export MLIR_DIR="$PREFIX/lib"
export LLVM_INCLUDE_DIRS="$SRC_DIR/include"
export LLVM_LIBRARY_DIR="$SRC_DIR/lib"
export LLVM_SYSPATH="$SRC_DIR"

export CFLAGS="$(echo $CFLAGS | sed 's/-O[0-9]//g')"
export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-O[0-9]//g')"

cd python
$PYTHON -m pip install . --no-deps --no-build-isolation --ignore-installed --no-cache-dir -vv
