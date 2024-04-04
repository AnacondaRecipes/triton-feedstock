#!/bin/bash

set -ex

# remove outdated vendored headers
rm -rf $SRC_DIR/python/triton/third_party

export TRITON_BUILD_WITH_CCACHE=true

cd python
$PYTHON -m pip install . -vv --no-deps --no-build-isolation
