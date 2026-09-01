# The pipeline

Four components make one turn: **audi** hears, **reflexi** decides, **cogiti**
orchestrates, **avatari** speaks and shows. Each documents its own half; this
file is the only place the whole path is written down, which is what this
repository is for.

Read the halves for detail — `../reflexi/docs/decision-contract.md`,
`../avatari/docs/{protocol,scene-protocol}.md`, `../cogiti/docs/ports.md` and
`../cogiti/docs/architecture.md` §3. Nothing here overrides them. Where this
file and a component's own contract disagree, the component is right and this
file is stale.

## 1. It is a hub, not a chain

The obvious mental model — audio into reflexi, reflexi into cogiti, cogiti into
avatari — is wrong in a way that matters for the latency budget.

**reflexi is not a process.** It is a C library linked into cogiti;
`reflexi_resolve()` is a function call. No socket, no connect, no network, no
serialisation, ~16 µs. audi and avatari *are* separate processes on Unix
sockets.

```
  mic ─▶┌──────┐ speech_start│partial│final│speech_end  ┌────────┐
        │ audi │───────────────────────────────────────▶│        │
  spk ◀─└──────┘◀────────────── say(text) ──────────────│        │
                                                        │ cogiti │
                       resolve(utterance) → decision    │        │
                    ┌───── reflexi ── linked in ────────┤        │
                    └───────────────────────────────────▶        │
                                                        │        │
        ┌─────────┐◀─── create/update/destroy ──────────│        │
        │ avatari │◀─── speak(visemes, wav, t₀) ────────│        │
        └─────────┘                                     └────────┘
             │
          DRM/KMS
```

That reflexi costs microseconds and not milliseconds is what makes §3
affordable. If it were a process, resolving every partial transcript would be
a fork per word and the fast path would be slower than the thing it exists to
avoid.

## 2. Two directions through one adapter

audi is a single adapter for speech in *and* out, and that is deliberate: they
share a device and, more importantly, a clock. Barge-in is a comparison
between when the person started talking and when the device did, and two
adapters would be two clocks.

## 3. One turn, in order

**`speech_start` carries no words.** Its only job is barge-in. If cogiti is
mid-sentence the response order is fixed and is not a preference:

1. tell avatari to stop,
2. stop the audio,
3. *then* start listening.

Any other order leaves a face talking over the person for a second.

**Every partial goes through reflexi.** This is where latency is hidden. What
may be *done* with the answer is gated by the decision's `tier`:

| tier | on a partial | why |
|---|---|---|
| `pattern` | may pre-warm — open a socket, start a fetch. No effect. | a listed phrase cannot become something else with the next word |
| `similar` | nothing | the next word moves the cosine |
| any, destructive intent | nothing, ever | see `../reflexi/docs/decision-contract.md` |

Only a `final` commits.

**The decision branches four ways.** Three are verdicts; the fourth is a field.

| | what cogiti does | budget |
|---|---|---|
| `handle` | command table → a provider → present | < 250 ms, no network |
| `confirm` | speak the question, show the thing, wait | the user's time |
| `escalate` | the agent port | seconds |
| `missing_slot` | ask for the slot — *"a timer for how long?"* | one round trip |

`missing_slot` is the one worth knowing about. reflexi recognised the intent
but a required slot was empty, so it returns **both** `intent_id` and
`missing_slot`: the only case where an escalation still carries an intent. It
is what stops "set a timer" costing an API call.

A `confirm` that goes unanswered **expires into cancelled, never into yes**.
So does a `choosing`. Both are worth restating here because the opposite is a
one-line change that smooths over an awkward pause.

## 4. The face is driven throughout, not at the end

avatari is a status display for the turn machine, not a printer that runs once
at the end.

| turn state | what avatari is told |
|---|---|
| listening | `expression: listening` |
| thinking | `expression: thinking`, and a `stream` object with **`attention: "never"`** |
| acting | nothing — a command should finish before it needs a spinner |
| result | scene ops: `create` with a brain-chosen id, `kind`, `region: stage`, `lifetime: turn` |
| speaking | one `speak` |
| quiet | `idle` |

`attention: "never"` on the thought stream is deliberate. The alternative,
`watch`, would have the head staring at its own reasoning.

**Only `present.py` knows the vocabulary.** A region name — `stage`,
`periphery` — appears in exactly one cogiti module. Everything above it deals
in results, not geometry, which is what lets a terminal be a valid
presentation adapter.

## 5. Where the mouth and the voice meet

TTS produces audio and phoneme boundaries; cogiti turns boundaries into
visemes and sends **one** message:

```json
{"type": "speak",
 "visemes": [[0.00, "AA"], [0.08, "M"], [0.31, "sil"]],
 "audio_start_ns": 1234567890,
 "audio": "/tmp/utterance.wav"}
```

`audio_start_ns` is `CLOCK_MONOTONIC` and is the whole trick: the viseme queue
and audio playback are scheduled against the *same* clock, so they cannot
drift apart. Two arrangements work, and both need it:

- **avatari plays the wav** (`--audio`), or
- **the brain plays the audio** and still sends `audio_start_ns`, so the mouth
  lines up with sound the renderer never hears.

avatari interpolates between the discrete events and crossfades shapes over
~70 ms. Sending more events does not make it smoother; snapping between them
is what reads as robotic.

## 6. What exists today

The diagram flatters the current state. As of 2026-09-01:

| | state |
|---|---|
| **audi** | does not exist. Nothing hears anything. Longest lead time of anything planned. |
| **reflexi** | exists, tested, on the box — **not wired in**. cogiti has no resolver adapter and `escalate.py` sends everything to the model. |
| **cogiti** | turn machine has `idle → resolving → thinking → speaking`. No `listening`, `acting`, `confirming`, `choosing`. No `resolve.py`, `table.py`, `present.py`, `speech.py`. |
| **avatari** | runs on the box — **not wired in**. cogiti has no presentation adapter; results print to a terminal. |
| **agent** | real and proven live, `adapters/anthropic/`. |

So one of the four branches works end to end, it is the slowest one, and it
ends in a terminal instead of a face.

**A known prerequisite:** reflexi builds `libreflexi.a`, a static library.
cogiti is Python and needs a shared object to load in-process. Shelling out to
reflexi's CLI is not a substitute — a fork per partial transcript is
milliseconds, and §1 is the reason that matters.

## 7. The rule this file is held to

Everything above is either a contract a component owns or a composition of
two. **Nothing here is a place to put behaviour.** If something in this file
starts describing what cogiti decides rather than how the four are wired, it
belongs in `../cogiti/docs/architecture.md` instead — and if it names a screen,
a microphone or a package, it belongs in `adapters.md` next to this one.
