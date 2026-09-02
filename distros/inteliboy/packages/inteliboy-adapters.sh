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

# Two directories, and they must not be one.
#
# The adapters are named after what they talk to — adapters/anthropic/ — and
# the library they talk to it with is also called anthropic. Put both in one
# directory on sys.path and `import anthropic` finds our folder instead of the
# SDK: "module 'anthropic' has no attribute 'Anthropic'", at first escalation,
# on the device. The same shape as a file called http.py shadowing the standard
# library, which this project has already been bitten by once.
#
# So the libraries go somewhere importable and our scripts go somewhere that is
# not on the path at all. They are programs, not modules; nothing imports them.
install -d /usr/lib/inteliboy-adapters
python3 -m pip install --no-deps --no-index --no-warn-script-location \
    --target /usr/lib/inteliboy-adapters /tmp/ia/wheels/*.whl

install -d /usr/libexec/inteliboy
cp -r /tmp/ia/adapters/* /usr/libexec/inteliboy/

cat > /usr/bin/inteliboy-agent <<'LAUNCHER'
#!/usr/bin/env python3
import sys
# Only the libraries. The adapter itself lives off the path on purpose.
sys.path.insert(0, "/usr/lib/inteliboy-adapters")
_p = "/usr/libexec/inteliboy/anthropic/adapter.py"
sys.argv[0] = "inteliboy-agent"
exec(compile(open(_p).read(), _p, "exec"),
     {"__name__": "__main__", "__file__": _p})
LAUNCHER
chmod 755 /usr/bin/inteliboy-agent

# The voice. Azure reports its own viseme timings, so this needs no phonemiser
# and no espeak — which is the whole reason it is worth carrying a cloud voice
# on a device that would otherwise need a new lfs package to speak at all.
#
# It writes its wav to /run rather than /tmp: cogiti hands the path to the
# renderer, both are on the same machine, and /run is a tmpfs so a sentence
# never touches the disk.
cat > /usr/bin/inteliboy-say <<'LAUNCHER'
#!/usr/bin/env python3
import os, sys
sys.path.insert(0, "/usr/lib/inteliboy-adapters")
os.environ.setdefault("AZURE_WAV", "/run/inteliboy-say.wav")
for var, name in (("AZURE_SPEECH_KEY", "azure.speech_key"),
                  ("AZURE_SPEECH_REGION", "azure.speech_region")):
    # Read here rather than inherited: cogiti builds a fresh environment for
    # every adapter it spawns, and this one is spawned by audi, which is
    # spawned by cogiti. Threading a secret through two of those is more
    # moving parts than reading the file it is already allowed to read.
    if var not in os.environ:
        try:
            with open("/var/lib/cogiti/secrets/%s" % name) as f:
                os.environ[var] = f.read().strip()
        except OSError:
            pass
_p = "/usr/libexec/inteliboy/azure/say-azure.py"
sys.argv = ["inteliboy-say", "--print"] + sys.argv[1:]
exec(compile(open(_p).read(), _p, "exec"),
     {"__name__": "__main__", "__file__": _p})
LAUNCHER
chmod 755 /usr/bin/inteliboy-say

rm -rf /tmp/ia

# The import is the check, for the same reason as audi: a wheel for the wrong
# Python installs without complaint and fails at first use.
# `Anthropic` specifically, not just that the name imports. Our own directory
# imports perfectly well under that name and has no client in it, which is
# exactly how this went wrong.
python3 -c "
import sys; sys.path.insert(0,'/usr/lib/inteliboy-adapters')
import anthropic
assert hasattr(anthropic, 'Anthropic'), 'anthropic resolved to the wrong thing: %s' % anthropic.__file__
print('  anthropic ok:', anthropic.__file__)"
/usr/bin/inteliboy-agent --capabilities
python3 -c "
import sys; sys.path.insert(0,'/usr/lib/inteliboy-adapters')
import azure.cognitiveservices.speech as s
assert hasattr(s, 'SpeechConfig'), 'the azure speech sdk did not load'
print('  azure speech sdk ok')"
test -x /usr/bin/inteliboy-say
test -f /usr/share/avatari/data/azure-visemes.txt
echo "inteliboy-adapters installed"
