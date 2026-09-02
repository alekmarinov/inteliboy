#!/bin/sh
# Is the microphone actually delivering speech?
#
#     tools/mic-check.sh [seconds]        speak while it runs
#
# Two different failures look identical from a distance: no capture at all,
# and capture that is working but silent. This tells them apart, because the
# second one is what a muted mic, a wrong source, or a Windows privacy setting
# all look like — and none of those are audi's fault.
set -eu
SECS=${1:-5}
OUT=${MIC_WAV:-/tmp/mic-check.wav}

command -v parecord >/dev/null || { echo "no parecord (pulseaudio-utils)"; exit 1; }

echo "sources:"
pactl list short sources 2>/dev/null | sed 's/^/  /' || echo "  (pulseaudio not answering)"
echo
echo "recording ${SECS}s — say something."
timeout $((SECS + 5)) parecord --file-format=wav --rate=16000 --channels=1 "$OUT" &
P=$!
sleep "$SECS"
kill -INT $P 2>/dev/null || true
wait $P 2>/dev/null || true

python3 - "$OUT" <<'PY'
import sys, wave

# audioop, not array/math, was the obvious way to write this — and it was
# removed in Python 3.13, which is what the appliance runs. These scripts
# worked on a 3.12 workstation and died on the device with ModuleNotFoundError,
# which is a poor way for a diagnostic tool to fail.
def _levels(data):
    import array, math
    a = array.array("h"); a.frombytes(data)
    if not a:
        return 0, 0, a
    peak = max(abs(x) for x in a)
    rms = int(math.sqrt(sum(x * x for x in a) / len(a)))
    return peak, rms, a


def _rms(chunk):
    import math
    return int(math.sqrt(sum(x * x for x in chunk) / len(chunk))) if chunk else 0

w = wave.open(sys.argv[1]); n = w.getnframes()
rate = w.getframerate()
if not n:
    print("\n  nothing captured at all — the source is not delivering frames.")
    raise SystemExit(1)

peak, rms, a = _levels(w.readframes(n))
print("\n  %.1fs at %d Hz   peak %5d   rms %4d" % (n / rate, rate, peak, rms))

# A level meter over the whole recording, so a mic that only works for part of
# it is visible rather than averaged away.
step = max(1, len(a) // 40)
bar = "".join(" .:-=+*#@"[min(8, int((_rms(a[i:i+step]) / 3000.0) * 8))]
              for i in range(0, len(a) - step, step))
print("  [%s]" % bar)

if peak < 500:
    print("\n  Captured, but silent. The stream is alive, so this is not a")
    print("  missing device — check that the mic is unmuted, that its boost is")
    print("  not at zero (the ALC233 ships that way), and that whatever is")
    print("  recording is allowed to.")
    raise SystemExit(1)
if rms < 300:
    print("\n  Very quiet. Speech recognition will struggle; raise the input")
    print("  gain rather than making the recogniser guess.")
    raise SystemExit(0)
print("\n  Good level. This is usable for speech recognition.")
PY
