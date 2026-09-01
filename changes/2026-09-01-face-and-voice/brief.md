# 2026-09-01-face-and-voice — the answer reaches the face

Status: landed
Approved by: alek, 2026-09-01 ("go ahead with what you can do without microphone")

## The ask

Wire the loop as far as it goes without a microphone. The user's constraint:
cogiti does not go on the box until the path from audio in to a speaking head
is whole, because a half-wired appliance on hardware proves very little.

## The seam

    contracts: presentation port, speech port (out half)
    owner:     cogiti
    consumers: avatari (presentation), this repo's espeak adapter (speech)
    additive:  yes — no port changed. Both were written from avatari; they fit.

## The finding that shaped the work

**The workstation has no working audio, in or out.** WSLg enumerates
`RDPSource` and `RDPSink` but both are suspended: `parecord` returns 0 frames,
`paplay` fails. espeak-ng and piper are installed and produce wav files that
cannot be heard.

This turned out not to block anything, because **avatari lipsyncs with no
sound card**: timing comes from the viseme queue scheduled against
`audio_start_ns`, and playback is off unless `--audio` is passed. So the
speaking head is fully demonstrable here. Only *hearing* it and *talking to*
it need hardware.

## What was built

### cogiti [order 1]

- `adapters/presentation.py` — the port's client. Reconnect with backoff, the
  renderer allowed to be absent, re-declare of pinned objects on connect,
  capability negotiation via `hello`.
- `present.py` — result → scene ops. **The only module in cogiti that says
  `stage`.** Nothing above it uses presentation vocabulary, which is what keeps
  a terminal, a web page and a 3D head equally valid adapters.
- `speech.py` — the out half of the speech port. Asks an adapter for marks and
  hands them to whoever draws a mouth; synthesises nothing itself.
- `main.py` — `FaceOutput`, composing the two. Either port may be missing
  without the other stopping.
- `config.py` — `presentation_adapter` left out of `MUST_EXIST`. It names a
  socket, and the renderer is a separate process; refusing to start would mean
  cogiti could never start before the face.

proves it: `make test` — 54, was 31.

### inteliboy [order 2]

- `adapters/espeak/speak` — a speech adapter wrapping avatari's `avatari-say`.
  It lives here for the same reason the Anthropic adapter does: cogiti names no
  implementation, and which engine speaks is a deployment's choice.

## What was deliberately not reimplemented

avatari already runs text through espeak-ng's C API, takes **the phoneme
boundaries it reports**, and maps them through the same `data/visemes.txt` its
renderer uses to pick mouth shapes (`tools/say.c`). Deriving timings anywhere
else would mean a second mapping to keep in step with that file, and it would
be wrong first.

`avatari-say --print` emits the message instead of sending it, which is the
seam that matters: **cogiti sends its own `speak`, over its own connection**,
so the presentation port stays the only thing talking to the renderer. Letting
avatari-say send it directly works today and puts a second writer on the socket
the moment anything needs sequencing.

## Two bugs found

**1. `subprocess.run` hangs under the event loop.** asyncio's child watcher
reaps the process, so a blocking `Popen.wait()` never sees the exit status and
stalls until its timeout — 60 ms of synthesis became a 20 second stall, and
only under the loop, which is why it read as a slow adapter. `say()` is now a
coroutine and speech uses `asyncio.create_subprocess_exec`. That is also simply
the right shape: `architecture.md` §1 says the loop does not block, and
barge-in needs it answering while the device speaks.

**2. A pinned object was sent twice on the connection that carried it** — once
by the connect-time replay and once by its own write, because it was recorded
into the pinned set *before* connecting. Recorded after delivery now, and still
recorded when delivery fails, since pinning something while the renderer is
away should still put it on screen when the renderer arrives.

## Proven live

avatari built `PLATFORM=desktop` under WSLg, cogiti driving it with the real
Anthropic adapter behind:

    {"event":"scene","objects":[{"id":"brain/answer","kind":"text",
      "region":"stage","lifetime":"turn","owner":"brain",...}],"listed":1}

Queried from a second connection while the turn was live. The answer was on
the stage, owned by `brain`, with a real model behind it.

## Not in this change

- **The resolver.** reflexi is still not linked in; everything escalates.
  It needs a `libreflexi.so` — reflexi ships `.a` only, and Python cannot load
  that. Next change.
- **Barge-in.** `stop()` exists on the presenter and nothing calls it, because
  nothing can interrupt yet without a microphone.
- **The `acting`, `confirming` and `choosing` turn states.** They arrive with
  the resolver and the command table.
- **audi.** No microphone, and it is the user's to prepare.
- **cogiti on the box**, by the user's decision recorded above.

## Rollback

`git revert` in each repo. No lock entry changed, no contract version moved.
