#!/bin/bash
set -e
echo "Building reflexi.."
echo "Approximate build time: less than 0.1 SBU"
echo "Required disk space: 8 MB"

# x. reflexi
# The reflex: pre-LLM intent resolution, C11, no network, no allocation in the
# hot path. cogiti links it and calls it on every partial transcript, which is
# why it is a library here and not a service.
#
# BUILD_REQUIRES: 8.51-make-python 8.29-make-gcc
# RUNTIME_REQUIRES: 8.5-make-glibc
#
# NOTE the shared library, not just the archive. cogiti is Python and loads it
# with ctypes, which cannot open a static archive. Both are installed; the .a
# costs nothing and is what a C consumer would want.
#
# NOTE python is a *build* dependency and not a runtime one. The blob is
# compiled from intents/ by tools/reflexi/blob.py, here, rather than shipped
# prebuilt — the loader refuses a blob built by a different normalizer than the
# one linked into it, and building both in the same place is the only thing
# that makes that check mean anything.

VER=$(ls /sources/reflexi-[0-9]*.tar.xz | sed 's|.*/reflexi-||; s|\.tar\.xz$||')
echo "reflexi $VER"

pushd /sources && grep " reflexi-[0-9]" local.md5sums | md5sum -c - && popd

rm -rf /tmp/reflexi
tar -xf /sources/reflexi-[0-9]*.tar.xz -C /tmp/ \
    && mv /tmp/reflexi-[0-9]* /tmp/reflexi \
    && pushd /tmp/reflexi \
    && make DEBUG=0 \
    && make DEBUG=0 install \
    && popd \
    && rm -rf /tmp/reflexi \
    || exit 1

# The library cogiti actually opens, the blob it reads, and the thresholds a
# distro may override. Missing any one of them is a device that escalates every
# utterance to a language model and never says why.
test -f /usr/lib/libreflexi.so
test -f /usr/lib/libreflexi.a
test -f /usr/share/reflexi/reflexi.blob
test -f /etc/reflexi-thresholds.toml
/usr/bin/reflexi-cli --version || true
echo "reflexi installed"
