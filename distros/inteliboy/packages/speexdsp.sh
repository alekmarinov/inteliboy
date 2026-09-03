#!/bin/bash
# PACKAGE:  speexdsp
# SOURCE:   speexdsp-*.tar.gz
# RELEASE:  1
# CLASS:    extra
set -e
echo "Building speexdsp.."
echo "Approximate build time: less than 0.1 SBU"
echo "Required disk space: 5 MB"

# speexdsp
# The acoustic echo canceller. audi loads libspeexdsp.so.1 through ctypes and
# declares `barge_in` only when it is there — so without this package the
# appliance cannot be interrupted while it speaks, and says so honestly rather
# than hearing its own voice and calling it a person.
#
# It is a dependency of a capability, not of a binary: nothing fails to link
# without it. audi's `--capabilities` reports barge_in false, cogiti believes
# it, stops listening while it talks, and the device becomes half duplex. That
# is a working appliance you cannot interrupt, which is why this was easy to
# postpone and worth stopping to do.
#
# https://www.speex.org/ — the codec is obsolete and this is not it: speexdsp
# is the signal processing half (echo cancellation, resampling, denoise) and is
# still what everything uses, PulseAudio included.
#
# Verified against sources/local.md5sums like everything else in this distro's
# sources directory. See tools/stage.sh, which downloads it once against a
# pinned sha256 and never again.

pushd /sources && grep " speexdsp-" local.md5sums | md5sum -c - && popd

VER=$(ls /sources/speexdsp-*.tar.gz | sed 's/^[^-]*-//' | sed 's/\.tar\.gz$//')
tar -xf /sources/speexdsp-*.tar.gz -C /tmp/ \
    && mv /tmp/speexdsp-* /tmp/speexdsp \
    && pushd /tmp/speexdsp \
    && ./configure \
        --prefix=/usr \
        --disable-static \
        --docdir=/usr/share/doc/speexdsp-$VER \
    && make \
    && if [ $LFS_TEST -eq 1 ]; then make check || true; fi \
    && make install \
    && popd \
    && rm -rf /tmp/speexdsp

# The name audi asks ctypes for. If this is not here the package installed
# something, and audi would still report barge_in false with nothing to
# explain why.
test -e /usr/lib/libspeexdsp.so.1
echo "speexdsp installed: $(ls -l /usr/lib/libspeexdsp.so.1* | wc -l) file(s)"
