#!/bin/bash
set -e
echo "Building inteliboy-adapters.."
echo "Approximate build time: less than 0.1 SBU"
echo "Required disk space: 12 MB"

# x. inteliboy-adapters
# Which model thinks, and which voice speaks. cogiti names no implementation of
# any port and this is where the naming happens — the one package in the image
# that is allowed to know that Anthropic exists.
#
# BUILD_REQUIRES: 8.51-make-python
# RUNTIME_REQUIRES: 8.51-make-python
#
# NOTE its own directory and its own copy of `anthropic`, not audi's. Sharing
# a site-packages between two adapters would mean one of them upgrading a
# library the other did not ask to have upgraded.

VER=$(ls /sources/inteliboy-adapters-*.tar.xz \
      | sed 's|.*/inteliboy-adapters-||; s|\.tar\.xz$||')
echo "inteliboy-adapters $VER"

pushd /sources && grep " inteliboy-adapters-" local.md5sums | md5sum -c - && popd

rm -rf /tmp/ia /usr/lib/inteliboy-adapters
tar -xf /sources/inteliboy-adapters-*.tar.xz -C /tmp/ && mv /tmp/inteliboy-adapters-* /tmp/ia

install -d /usr/lib/inteliboy-adapters
cp -r /tmp/ia/adapters/* /usr/lib/inteliboy-adapters/
python3 -m pip install --no-deps --no-index --no-warn-script-location \
    --target /usr/lib/inteliboy-adapters /tmp/ia/wheels/*.whl

cat > /usr/bin/inteliboy-agent <<'LAUNCHER'
#!/usr/bin/env python3
import os, sys
sys.path.insert(0, "/usr/lib/inteliboy-adapters")
sys.argv[0] = "inteliboy-agent"
exec(open("/usr/lib/inteliboy-adapters/anthropic/adapter.py").read(),
     {"__name__": "__main__", "__file__":
      "/usr/lib/inteliboy-adapters/anthropic/adapter.py"})
LAUNCHER
chmod 755 /usr/bin/inteliboy-agent

rm -rf /tmp/ia

# The import is the check, for the same reason as audi: a wheel for the wrong
# Python installs without complaint and fails at first use.
python3 -c "import sys; sys.path.insert(0,'/usr/lib/inteliboy-adapters'); import anthropic; print('  anthropic', anthropic.__version__ if hasattr(anthropic,'__version__') else 'ok')"
/usr/bin/inteliboy-agent --capabilities
echo "inteliboy-adapters installed"
