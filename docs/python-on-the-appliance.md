# Python on the appliance

cogiti and audi are both Python, so the image needs an interpreter and four
binary wheels. Neither was obvious to size, and both have a trap.

## The interpreter

`make closure PACKAGES=8.51-make-python` in lfs, diffed against what the
distro already lists: **21 of Python's 25 dependencies were already there** for
other reasons, and only four had to be added — `gdbm`, `libffi`, `sqlite` and
Python itself.

## The wheels, and the version that matters

    numpy  scipy  onnxruntime  sherpa-onnx        87 MB, cp313, manylinux

Two compatibility questions, and the answers are not the ones you would guess
from the sizes.

**glibc and libstdc++ are a non-issue.** The wheels need at most `GLIBC_2.28`
and `GLIBCXX_3.4.22`; LFS 12.4 builds glibc 2.42 and gcc 15.2. Comfortable.

**The Python minor version is the real constraint.** C-extension wheels are
ABI-locked to it: a `cp312` wheel will not load on Python 3.13, and fails at
import on the device rather than at build time. LFS 12.4 ships **Python
3.13.7**, and the development venv here is 3.12 — so *the wheels that work on
this workstation are not the wheels the image needs*.

    pip download --only-binary=:all: \
        --python-version 3.13 --implementation cp --abi cp313 \
        --platform manylinux2014_x86_64 --platform manylinux_2_17_x86_64 \
        numpy scipy onnxruntime sherpa-onnx

**The platform tag is worth getting right rather than guessing.** Asked for
`manylinux_2_28_x86_64`, pip reports `No matching distribution found for
sherpa-onnx` — which reads exactly like "there is no cp313 build" and is not:
it publishes `manylinux2014` / `manylinux_2_17`, and asking for the wrong tag
says the same thing as asking for a package that does not exist.

## Size

    python + gdbm + libffi + sqlite     ~100 MB
    four wheels                           87 MB
    speech models                        568 MB   (321 streaming, 245 whisper, 2 vad)

The models dominate, and the offline one is optional: `audi --no-offline` uses
the streaming model's own final and saves 245 MB, at the cost of punctuation
and some accuracy on the transcript the language model sees. The streaming
model alone produced `TURN THE VOLUME UP`, which reflexi resolves perfectly
well — so the first image can ship without Whisper and gain it later.

The 20M streaming model is not a saving worth making: it transcribes the same
audio as `UE UP`, which resolves to nothing at all.
