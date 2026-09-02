#!/bin/bash
set -e
echo "Building audi.."
echo "Approximate build time: less than 0.2 SBU"
echo "Required disk space: 600 MB"

# x. audi
# Ears and voice. Unlike cogiti it has dependencies — numpy, scipy,
# onnxruntime and sherpa-onnx — and they arrive as wheels rather than as
# source, because building onnxruntime from source is a day and a compiler
# farm.
#
# BUILD_REQUIRES: 8.51-make-python
# RUNTIME_REQUIRES: 8.51-make-python 42-make-alsa-utils 8.5-make-glibc 8.29-make-gcc
#
# NOTE gcc is a runtime dependency here for libstdc++: onnxruntime and
# sherpa-onnx are C++ and link it, and nothing else in this image would have
# pulled it in for that reason.
#
# NOTE alsa-utils is how audio actually moves. audi shells out to arecord and
# aplay rather than binding a library, which keeps a C extension out of a
# component that has enough of them, and works identically on a workstation
# with PulseAudio and here with ALSA.
#
# NOTE the wheels are installed with --no-deps and --no-index. Every dependency
# is already in the tarball, and letting pip reach the network during an image
# build would make the image depend on what PyPI served that afternoon.

VER=$(ls /sources/audi-[0-9]*.tar.xz | sed 's|.*/audi-||; s|\.tar\.xz$||')
echo "audi $VER"

pushd /sources && grep -E " audi(-models|-wheels)?-[0-9]" local.md5sums | md5sum -c - && popd

rm -rf /tmp/audi /tmp/audi-wheels /tmp/audi-models /usr/lib/audi
tar -xf /sources/audi-[0-9]*.tar.xz -C /tmp/ && mv /tmp/audi-[0-9]* /tmp/audi
tar -xf /sources/audi-wheels-*.tar.xz -C /tmp/ && mv /tmp/audi-wheels-* /tmp/audi-wheels
tar -xf /sources/audi-models-*.tar.xz -C /tmp/ && mv /tmp/audi-models-* /tmp/audi-models

install -d /usr/lib/audi
cp -r /tmp/audi/src/audi /usr/lib/audi/
install -d /usr/share/audi
cp -r /tmp/audi-models/models/* /usr/share/audi/

python3 -m pip install --no-deps --no-index --no-warn-script-location \
    --target /usr/lib/audi /tmp/audi-wheels/wheels/*.whl

cat > /usr/bin/audi <<'LAUNCHER'
#!/usr/bin/env python3
import sys
sys.path.insert(0, "/usr/lib/audi")
from audi.adapter import main
sys.exit(main(sys.argv[1:]))
LAUNCHER
chmod 755 /usr/bin/audi

rm -rf /tmp/audi /tmp/audi-wheels /tmp/audi-models

# The imports are the point of the check. A wheel built for a different Python
# minor version installs without complaint and fails here, which is the whole
# reason this test exists rather than a file listing.
test -f /usr/share/audi/silero_vad.onnx
python3 - <<'CHECK'
import sys
sys.path.insert(0, "/usr/lib/audi")
import numpy, onnxruntime, sherpa_onnx
from audi import adapter, aec, asr, vad
print("  numpy", numpy.__version__, "onnxruntime", onnxruntime.__version__)
CHECK
echo "audi installed"
