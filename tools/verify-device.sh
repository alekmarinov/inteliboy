#!/bin/bash
# Is the appliance actually working? Ask it, over ssh.
#
#     tools/verify-device.sh 192.168.1.174
#     tools/verify-device.sh localhost -p 2222        (a qemu boot)
#
# Written after a boot test found three failures that all looked identical from
# the outside — a face that never answers — and none of which appeared in any
# log as a cause. Each check below is one of them, or something that would fail
# the same silent way.
set -u
HOST=${1:?usage: verify-device.sh <host> [ssh args...]}
shift || true
SSH=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=8 "$@" "root@$HOST")

pass=0; fail=0
check() {                      # check <name> <command...>
    local name=$1; shift
    printf "  %-46s " "$name"
    if out=$("${SSH[@]}" "$@" 2>&1); then
        echo "ok"; pass=$((pass+1))
    else
        echo "FAILED"
        echo "$out" | tail -3 | sed 's/^/        /'
        fail=$((fail+1))
    fi
}

echo "InteliBoy at $HOST"
echo
echo "the parts:"
check "the image identifies itself"      'grep -q inteliboy /etc/os-release'
check "python is present"                'python3 -V >/dev/null'
check "the renderer is running"          'pgrep -x avatari >/dev/null'
check "the brain is running"             'pgrep -f "python3 /usr/bin/cogiti" >/dev/null'

echo
echo "what the brain needs:"
check "the resolver library loads"       'python3 -c "import ctypes; ctypes.CDLL(\"/usr/lib/libreflexi.so\")"'
check "the resolver blob is there"       'test -f /usr/share/reflexi/reflexi.blob'
check "an utterance resolves"            'python3 -c "
import sys; sys.path.insert(0,\"/usr/lib/cogiti\")
from cogiti.adapters.resolver import Resolver
r = Resolver(\"/usr/lib/libreflexi.so\", \"/usr/share/reflexi/reflexi.blob\",
             config=\"/etc/reflexi-thresholds.toml\")
d = r.resolve(\"turn the volume up\")
assert d.intent_id == \"volume_up\" and d.verdict == \"handle\", d
"'
check "the command table loads"          'python3 -c "
import sys; sys.path.insert(0,\"/usr/lib/cogiti\")
from cogiti import providers, table
providers.load_all()
assert len(table.load(\"/etc/cogiti/commands.toml\")) > 0
"'

echo
echo "what the ears need:"
check "the speech stack imports"         'python3 -c "
import sys; sys.path.insert(0,\"/usr/lib/audi\")
import numpy, onnxruntime, sherpa_onnx"'
check "audi finds its models"            'python3 -c "
import sys; sys.path.insert(0,\"/usr/lib/audi\")
from audi import paths
paths.find(\"silero_vad.onnx\", \"VAD model\")"'
check "audi declares its capabilities"   'timeout 60 /usr/bin/audi --capabilities | grep -q partials'
check "there is a capture device"        'arecord -l 2>/dev/null | grep -q "^card"'

echo
echo "credentials:"
check "the model key is installed"       'test -s /var/lib/cogiti/secrets/anthropic.api_key'
check "and is not world readable"        'test "$(stat -c %a /var/lib/cogiti/secrets/anthropic.api_key)" = 600'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
