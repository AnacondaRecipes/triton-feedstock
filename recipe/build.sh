#!/bin/bash

set -ex

# Currently we leave CUDA vendored-in, see
# patches section for reasoning.
# Uncomment this if we want to change this.
# remove outdated vendored headers
#rm -rf $SRC_DIR/python/triton/third_party

# To find e.g. the right libstdc++
export LD_LIBRARY_PATH=${PREFIX}/lib:$LD_LIBRARY_PATH

export JSON_SYSPATH=$PREFIX
export LLVM_SYSPATH=$PREFIX
export PYBIND11_SYSPATH=$SP_DIR/pybind11

# these don't seem to be actually used, but they prevent downloads
export TRITON_PTXAS_PATH=$PREFIX/bin/ptxas
export TRITON_CUOBJDUMP_PATH=$PREFIX/bin/cuobjdump
export TRITON_NVDISASM_PATH=$PREFIX/bin/nvdisasm
export TRITON_CUDACRT_PATH=$PREFIX
export TRITON_CUDART_PATH=$PREFIX
export TRITON_CUPTI_PATH=$PREFIX

export MAX_JOBS=$CPU_COUNT

# the build does not run C++ unittests, and they implicitly fetch gtest
# no easy way of passing this, not really worth a whole patch
sed -i -e '/TRITON_BUILD_UT/s:\bON:OFF:' CMakeLists.txt

cd python
$PYTHON -m pip install . -vv --no-deps --no-build-isolation
