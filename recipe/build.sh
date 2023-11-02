#!/bin/bash

set -ex

# remove outdated vendored headers
rm -rf $SRC_DIR/python/triton/third_party

# direct CMake towards LLVM library directory
export LLVM_DIR="$SRC_DIR"

export CFLAGS="$(echo $CFLAGS | sed 's/-O[0-9]//g')"
export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-O[0-9]//g')"

cd python
$PYTHON -m pip install . --no-deps --no-build-isolation --ignore-installed --no-cache-dir -vv
