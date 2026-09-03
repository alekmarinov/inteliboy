#!/bin/bash
set -e
echo "Building cogiti.."
echo "Approximate build time: less than 0.1 SBU"
echo "Required disk space: 4 MB"

# x. cogiti
# The brain: resolve, act, escalate, remember. Stdlib-only Python by decision,
# so this installs sources and a launcher and compiles nothing.
#
# BUILD_REQUIRES: 8.51-make-python
# RUNTIME_REQUIRES: 8.51-make-python 22-make-sqlite
#
# NOTE sqlite is a runtime dependency and nothing links it. cogiti reaches it
# through Python's own sqlite3 module, so it never appears in the ELF graph and
# 'make check' cannot see it — the same shape as avatari's dlopen of libEGL,
# and recorded here for the same reason.
#
# NOTE no venv and no pip. cogiti imports nothing that is not in the standard
# library, which is what lets it be installed by copying. Every dependency the
# appliance has belongs to an adapter, and those bring their own.

VER=$(ls /sources/cogiti-[0-9]*.tar.xz | sed 's|.*/cogiti-||; s|\.tar\.xz$||')
echo "cogiti $VER"

pushd /sources && grep " cogiti-[0-9]" local.md5sums | md5sum -c - && popd

rm -rf /tmp/cogiti /usr/lib/cogiti
tar -xf /sources/cogiti-[0-9]*.tar.xz -C /tmp/ \
    && mv /tmp/cogiti-[0-9]* /tmp/cogiti \
    && install -d /usr/lib/cogiti \
    && cp -r /tmp/cogiti/src/cogiti /usr/lib/cogiti/ \
    && install -d /usr/share/doc/cogiti \
    && cp -r /tmp/cogiti/docs/* /usr/share/doc/cogiti/ 2>/dev/null \
    && rm -rf /tmp/cogiti \
    || exit 1

# A launcher rather than the checkout's bin/cogiti, which resolves its path
# relative to a source tree that is not here.
cat > /usr/bin/cogiti <<'LAUNCHER'
#!/usr/bin/env python3
import sys
sys.path.insert(0, "/usr/lib/cogiti")
from cogiti.main import main
sys.exit(main(sys.argv[1:]))
LAUNCHER
chmod 755 /usr/bin/cogiti

test -f /usr/lib/cogiti/cogiti/main.py
python3 -c "import sys; sys.path.insert(0,'/usr/lib/cogiti'); import cogiti.main"
echo "cogiti installed"
