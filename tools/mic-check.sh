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
import audioop, sys, wave
w = wave.open(sys.argv[1]); n = w.getnframes()
rate = w.getframerate()
if not n:
    print("\n  nothing captured at all — the source is not delivering frames.")
    raise SystemExit(1)

data = w.readframes(n)
peak, rms = audioop.max(data, 2), audioop.rms(data, 2)
print("\n  %.1fs at %d Hz   peak %5d   rms %4d" % (n / rate, rate, peak, rms))

# A level meter over the whole recording, so a mic that only works for part of
# it is visible rather than averaged away.
step = max(1, n // 40)
bar = ""
for i in range(0, n - step, step):
    chunk = data[i * 2:(i + step) * 2]
    lvl = audioop.rms(chunk, 2)
    bar += " .:-=+*#@"[min(8, int((lvl / 3000.0) * 8))]
print("  [%s]" % bar)

if peak < 500:
    print("\n  Captured, but silent. The stream is alive, so this is not a")
    print("  missing device — check that the mic is unmuted, that Windows lets")
    print("  this app use it, and that RDPSource is the right source.")
    raise SystemExit(1)
if rms < 300:
    print("\n  Very quiet. Speech recognition will struggle; raise the input")
    print("  gain rather than making the recogniser guess.")
    raise SystemExit(0)
print("\n  Good level. This is usable for speech recognition.")
PY
