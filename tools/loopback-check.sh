#!/bin/sh
# Play something and listen for it: does the speaker reach the microphone?
#
#     tools/loopback-check.sh
#
# Two questions at once, and the second is the interesting one.
#
# **Does the mic work at all**, without anyone having to be in the room. If the
# speaker is audible to the mic, a silent recording means a broken capture path
# rather than a quiet room.
#
# **How much of its own voice will the device hear?** That number decides
# whether barge-in is possible. audi's speech_start fires on sound; if the
# device's own speaker lands in the mic at a level comparable to a person, then
# every sentence it speaks interrupts itself, and the answer is acoustic echo
# cancellation — which needs playback and capture in one clock domain, which is
# the concrete reason the speaker belongs to audi rather than to the renderer.
set -eu
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
SAY=${1:-"Testing one two three. Testing one two three."}

command -v parecord >/dev/null || { echo "no parecord"; exit 1; }
espeak-ng -v en -s 150 -a 200 -w "$D/tone.wav" "$SAY" 2>/dev/null \
  || { echo "no espeak-ng"; exit 1; }

echo "1. baseline: recording 2s of silence (nothing playing)"
timeout 12 parecord --file-format=wav --rate=16000 --channels=1 "$D/quiet.wav" &
Q=$!; sleep 2; kill -INT $Q 2>/dev/null || true; wait $Q 2>/dev/null || true

echo "2. loopback: recording while the speaker plays"
timeout 20 parecord --file-format=wav --rate=16000 --channels=1 "$D/loop.wav" &
R=$!
sleep 0.4
paplay "$D/tone.wav" 2>/dev/null || echo "   (playback failed)"
sleep 0.6
kill -INT $R 2>/dev/null || true; wait $R 2>/dev/null || true

python3 - "$D/quiet.wav" "$D/loop.wav" <<'PY'
import audioop, sys, wave

def level(path):
    w = wave.open(path); n = w.getnframes()
    if not n:
        return 0, 0, 0.0, ""
    d = w.readframes(n)
    step = max(1, n // 32)
    bar = "".join(" .:-=+*#@"[min(8, int(audioop.rms(d[i*2:(i+step)*2], 2)
                                         / 3000.0 * 8))]
                  for i in range(0, n - step, step))
    return audioop.max(d, 2), audioop.rms(d, 2), n / w.getframerate(), bar

qp, qr, qs, qb = level(sys.argv[1])
lp, lr, ls, lb = level(sys.argv[2])
print()
print("  silence   %.1fs  peak %5d  rms %4d  [%s]" % (qs, qp, qr, qb))
print("  loopback  %.1fs  peak %5d  rms %4d  [%s]" % (ls, lp, lr, lb))
print()

if lp < 200 and qp < 200:
    print("  Both silent. The capture path delivers frames but no sound —")
    print("  the mic is muted, denied, or not the source being recorded.")
    raise SystemExit(1)
if lp < qp * 3 and lp < 800:
    print("  The speaker does not reach the mic. Good news for barge-in: the")
    print("  device will not hear itself, so no echo cancellation is needed")
    print("  for this setup. It also means the mic cannot be tested this way —")
    print("  someone has to speak.")
    raise SystemExit(0)

ratio = (lr / qr) if qr else float("inf")
print("  The mic hears the speaker: %.0fx the silent level." % ratio)
print()
print("  So the capture path works, and the device WILL hear its own voice.")
print("  That is the echo problem: speech_start would fire on cogiti's own")
print("  speech and every sentence would interrupt itself. audi needs either")
print("  echo cancellation, or a half-duplex gate that closes the mic while")
print("  speaking — and the gate costs barge-in entirely.")
PY
