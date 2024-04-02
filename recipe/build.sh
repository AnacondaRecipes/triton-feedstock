#!/bin/bash

set -ex

# remove outdated vendored headers
rm -rf $SRC_DIR/python/triton/third_party

export TRITON_LIBDEVICE_PATH=$PREFIX/lib/libdevice.10.bc
export TRITON_PTXAS_PATH=$PREFIX/bin/ptxas
export TRITON_CUOBJDUMP_PATH=$PREFIX/bin/cuobjdump
export TRITON_NVDISASM_PATH=$PREFIX/bin/nvdisasm
export LLVM_INCLUDE_DIRS=$PREFIX/include
export LLVM_LIBRARY_DIR=$PREFIX/lib
export LLVM_SYSPATH=$PREFIX

cd python
$PYTHON -m pip install . -vv --no-deps --no-build-isolation
