#!/bin/bash
set -e
echo "Installing avatari voices.."
echo "Approximate build time: less than 0.1 SBU"
echo "Required disk space: 180 MB"

# x. avatari voices
# the Piper voice models. Shipped apart from the renderer because
# they are large binary assets on a different cadence to the code - rebuilding
# the renderer should not re-ship them.
#
# Nothing consumes these yet - text to speech is brain side and no brain
# service exists. They are shipped now so the image is complete ahead of that
# work; drop this package from packages.list to get the space back.
#
# No BUILD_REQUIRES: this installs a tarball of assets and compiles nothing.
# No RUNTIME_REQUIRES either - they are data files, read by avatari, which
# declares what it needs itself.
#
# The tarball unpacks straight into the install layout, so the recipe makes no
# decision about where anything goes - avatari's own 'make dist-assets' owns
# that. See x-make-avatari.sh for why these are verified against
# sources/local.md5sums instead of a wget list.

pushd /sources && grep " avatari-voices-" local.md5sums | md5sum -c - && popd

install -v -d -m755 /usr/share/avatari
tar -xf /sources/avatari-voices-*.tar.xz -C /usr/share/avatari --strip-components=1     || exit 1

test -d /usr/share/avatari/voices
echo "avatari voices installed: $(ls /usr/share/avatari/voices | wc -l) files"
