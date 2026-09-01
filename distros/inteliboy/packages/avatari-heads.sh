#!/bin/bash
set -e
echo "Installing avatari heads.."
echo "Approximate build time: less than 0.1 SBU"
echo "Required disk space: 12 MB"

# x. avatari heads
# the avatar models the renderer loads. Shipped apart from the renderer because
# they are large binary assets on a different cadence to the code - rebuilding
# the renderer should not re-ship them.
#
# model.head in /etc/avatari.conf selects which one is used.
#
# No BUILD_REQUIRES: this installs a tarball of assets and compiles nothing.
# No RUNTIME_REQUIRES either - they are data files, read by avatari, which
# declares what it needs itself.
#
# The tarball unpacks straight into the install layout, so the recipe makes no
# decision about where anything goes - avatari's own 'make dist-assets' owns
# that. See x-make-avatari.sh for why these are verified against
# sources/local.md5sums instead of a wget list.

pushd /sources && grep " avatari-heads-" local.md5sums | md5sum -c - && popd

install -v -d -m755 /usr/share/avatari
tar -xf /sources/avatari-heads-*.tar.xz -C /usr/share/avatari --strip-components=1     || exit 1

test -d /usr/share/avatari/heads
echo "avatari heads installed: $(ls /usr/share/avatari/heads | wc -l) files"
