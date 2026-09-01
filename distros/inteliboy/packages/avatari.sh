#!/bin/bash
set -e
echo "Building avatari.."
echo "Approximate build time: less than 0.1 SBU"
echo "Required disk space: 6 MB"

# x. avatari
# The renderer InteliBoy exists to run: a talking head drawn straight to
# DRM/KMS, with no display server under it. Driven over a unix socket by the
# brain services, which are separate programs and are not built here.
#
# BUILD_REQUIRES: 24-make-mesa 24-make-libdrm 42-make-alsa-lib 8.19-make-pkgconf
# RUNTIME_REQUIRES: 24-make-mesa 24-make-libdrm 42-make-alsa-lib 8.40-make-expat
#
# NOTE mesa is named in RUNTIME_REQUIRES as well as BUILD_REQUIRES, and that is
# not redundant. The renderer reaches libEGL through dlopen, so it never appears
# in the ELF graph and 'make check' - which resolves programs with ldd - cannot
# see the dependency at all. A distro built from link-time information alone
# would boot to a renderer that dies in platform_init. The declared line is the
# only place that fact is recorded, which is what these declarations are for.
#
# libexpat is here for the same reason one step removed: nothing in avatari
# references it, Mesa pulls it in to parse drirc.
#
# NOTE the source is not downloaded. It is built from this checkout by
# 'make avatari-sources', which runs avatari's own 'make dist' and copies the
# tarballs here. They carry no upstream url, so they are verified against
# sources/local.md5sums rather than the wget lists - the checksum still catches
# a truncated copy, it just is not a supply chain claim about our own code.
#
# NOTE PLATFORM and DEBUG are repeated on the install line. The install
# target depends on the binary, and the binary's path is derived from those
# two variables - a bare 'make install' re-resolves them to the defaults,
# starts building the desktop backend instead, and stops on a GLFW header
# that is deliberately not on this system.
#
# NOTE the glob is avatari-[0-9]* and not avatari-*. The heads and voices
# tarballs sit beside this one and share its prefix; a wider glob hands tar
# three files and it extracts a member from the first instead of the archive.

VER=$(ls /sources/avatari-[0-9]*.tar.xz | sed 's|.*/avatari-||; s|\.tar\.xz$||')
echo "avatari $VER"

pushd /sources && grep " avatari-[0-9]" local.md5sums | md5sum -c - && popd

rm -rf /tmp/avatari
tar -xf /sources/avatari-[0-9]*.tar.xz -C /tmp/ \
    && mv /tmp/avatari-[0-9]* /tmp/avatari \
    && pushd /tmp/avatari \
    && make PLATFORM=kms DEBUG=0 \
    && make PLATFORM=kms DEBUG=0 install \
    && popd \
    && rm -rf /tmp/avatari \
    || exit 1

# The binary has to exist and report itself, or the distro ships a renderer
# that cannot start and says nothing about why.
test -x /usr/bin/avatari
/usr/bin/avatari --version
test -f /etc/avatari.conf
echo "avatari installed"
