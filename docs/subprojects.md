# Sub-projects

What can be built while cogiti is being built, by whom, and against what
contract.

The reason this document exists: cogiti's roadmap is ten stages long and most
of them contain one large piece that is not really orchestration at all. Each
of those pieces has a written interface, needs no LLM to develop, and can be
tested on its own. Split out, they can all start now. Left inside cogiti, they
serialise behind it.

**The rule for every entry below:** it is a separate repository, with its own
`CLAUDE.md`, its own eval, and a one-page protocol spec that lives in *this*
repo under `docs/protocols/`. The spec is written first — it is what makes the
work parallel — and it is the only thing the two sides share. No shared code.

The family naming follows reflexi and avatari: a Latin verb, first-person
singular, ending in `-i`. Names are cheap to change; the contracts are not.

---

## The map

```
                        ┌───────────┐
             ears ─────▶│   audi    │──┐
                        └───────────┘  │  transcripts, speech
                        ┌───────────┐  │
             eyes ─────▶│   vidi    │──┤  identity, QR, OCR
                        └───────────┘  │
                                       ▼
   ┌──────────┐   ┌───────────┐   ┌─────────┐   ┌───────────┐
   │ memori   │◀──│  cogiti   │──▶│ agenti  │   │  custodi  │
   │ knowledge│   │           │   │ one job │   │ sandbox,  │
   └──────────┘   └───────────┘   └─────────┘   │ secrets,  │
                        │  ▲                    │ egress    │
                        │  │                    └───────────┘
                        ▼  │
                   ┌───────────┐        ┌───────────┐
                   │  avatari  │        │   probi   │
                   │ (exists)  │        │ harness + │
                   └───────────┘        │ simulator │
                                        └───────────┘
```

---

## 1. `audi` — the ears and the voice

**What it is.** The only process that touches the sound card. Wake word, VAD,
streaming STT, endpointing, and text-to-speech with phoneme timings. It hands
cogiti transcripts and hands back `(visemes, wav path)` for cogiti to send to
avatari as a `speak`.

**Why it is separate.** It is CPU-heavy per frame, it has tight timing
requirements that an orchestrator's event loop should not be near, it is
developed against a microphone rather than against cogiti, and it is the
component most likely to have to move to another machine if the box turns out
too weak — which is the same argument avatari's own `CLAUDE.md` makes about
the brain, and it holds here for the same reason.

**Contract** (`docs/protocols/audi.md`, to write):

```json
→ {"v":1,"op":"listen"}                     cogiti: start a turn
← {"v":1,"ev":"speech_start","ns":...}      barge-in trigger
← {"v":1,"ev":"partial","text":"what is the wea"}
← {"v":1,"ev":"final","text":"what is the weather","ns":...}
← {"v":1,"ev":"speech_end","ns":...}
→ {"v":1,"op":"say","text":"It's 21 and clear.","voice":"amy"}
← {"v":1,"ev":"said","wav":"/run/cogiti/utt-7.wav",
   "visemes":[[0.0,"AA"],[0.08,"M"]],"audio_start_ns":...}
```

The `visemes` array is exactly avatari's `speak` payload, deliberately — cogiti
forwards it rather than translating it, and avatari plays the wav so the
mouth and the sound share one clock.

**Starting point.** `avatari/tools/say.c`, `say-piper.sh` and `speak.sh`
already do the espeak/Piper/Azure tiering and the viseme mapping. `audi` is
that work made into a daemon, plus VAD, plus whisper.cpp, plus a wake word.
The user's own `voice-gateway` repo has the barge-in and endpointing lessons
already learned; read it before designing the turn edges.

**Testable alone:** yes, completely. `audi --cli` reads a wav and prints
transcripts; a person can talk to it with no other component present.

**Blocks:** Stage 2. **Blocked by:** nothing.

---

## 2. `agenti` — the job runner

**What it is.** One process per job. Takes an assembled prompt and a tool
grant on stdin, streams events on stdout, exits. Drivers behind one interface:
`claude-agent-sdk` first, an OpenAI-compatible HTTP driver second, a local
`llama.cpp` driver third.

**Why it is separate.** Cancellation that works, a crash that is contained, and
the SDK's dependency tree kept out of cogiti. Also: it is the only place a
model is called, so it is the only place that has to care about retries,
streaming, token accounting and rate limits.

**Contract** (`docs/protocols/agenti.md`, to write):

```json
→ {"v":1,"op":"run","job":"01J8...","driver":"claude",
   "prompt":{...},"tools":["fetch","read_file"],"budget":{"tokens":40000}}
← {"v":1,"ev":"thought","text":"..."}         → a stream, attention:"never"
← {"v":1,"ev":"tool","name":"fetch","summary":"reading coingecko"}
← {"v":1,"ev":"progress","text":"three of five files"}
← {"v":1,"ev":"question","text":"which repository?"}   → needs-input
← {"v":1,"ev":"result","say":"...","show":{...},"did":[...]}
← {"v":1,"ev":"failed","kind":"offline","detail":"..."}
```

**The result is structured, not prose.** `say` is what to speak, `show` is a
presentation payload, `did` is what it actually did for the audit log. A model
writing prose straight into a text-to-speech engine is how an assistant ends
up reading a bulleted list aloud.

**Testable alone:** yes — a mock driver with scripted outputs, plus a real one
against a key. Its eval is a set of prompts with expected result shapes.

**Blocks:** Stages 3, 4, 5b. **Blocked by:** the protocol spec, which is an
afternoon.

---

## 3. `memori` — the knowledge base

**What it is.** `../../cogiti/docs/memory.md`, as a library and a CLI. Entities, facts,
relations, provenance, contradiction, retrieval and the forget cascade over
SQLite. No models, no network, no avatari.

**Why it is separate.** It is the piece with the clearest boundary and the
best standalone eval in the whole project: a labelled corpus of conversations
with expected extractions, retrievals and refusals. That eval can be built and
run by someone who has never seen cogiti.

**Contract.** A Python API, not a socket — it is a library, like reflexi. That
is a deliberate exception to the socket rule: it is pure computation over a
local database, it has no lifetime of its own, and a process boundary would
buy nothing.

**Testable alone:** yes, and it is the sub-project most worth building against
a real eval set from day one.

**Blocks:** Stage 6. **Blocked by:** nothing. Worth starting early precisely
because the roadmap says to consider pulling Stage 6 forward.

---

## 4. `custodi` — sandbox, secrets, egress

**What it is.** The enforcement half of `../../cogiti/docs/security.md`. Per-service uid
allocation, rlimits and process-group spawn; the secret store with per-service
scoping; the localhost egress broker with per-principal host allowlists; the
append-only audit log.

**Why it is separate.** It is systems work, not AI work, it is testable with
shell scripts and a fake service, and it gates two stages (5 and 7). It is also
the part where a subtle mistake is expensive, so it deserves someone's whole
attention rather than being written in the margins of Stage 5.

**Contract.** A Python library plus one daemon (the proxy). `spawn_confined()`,
`grant()`, `revoke()`, `audit()`.

**Testable alone:** yes. The tests are the interesting part: a service that
tries to write outside its directory, one that tries to reach an undeclared
host, one that forks a grandchild and ignores `SIGTERM`, one whose source hash
no longer matches.

**Blocks:** Stages 5 and 7. **Blocked by:** nothing.

---

## 5. `vidi` — the eyes and identity

**What it is.** Camera pipeline: capture, QR decode, OCR, face detection and
recognition, presence. Publishes events to cogiti. Speaker identification from
voice lives in `audi` but the enrolment and the identity store are here, so
there is one answer to "who is this".

**Why it is separate.** Same argument as `audi` — per-frame CPU, owns a
device, carries biometrics, and needs a camera rather than a brain to develop
against.

**Contract:**

```json
← {"v":1,"ev":"presence","present":true,"count":1}
← {"v":1,"ev":"identity","speaker_id":"alek","confidence":0.94,"via":"face"}
← {"v":1,"ev":"qr","text":"WIFI:S:home;T:WPA;P:...;;"}
← {"v":1,"ev":"text","ocr":"..."}
→ {"v":1,"op":"enroll","speaker_id":"maria"}
```

Note `presence` — it is the least glamorous event and the one Stage 12 needs
most, because a device that talks to an empty room is a device people unplug.

**Blocks:** Stages 8, 9 (the QR half) and 12 (presence). **Blocked by:**
nothing but a camera.

---

## 6. `probi` — the harness and the device simulator

**What it is.** A fake avatari that speaks the real scene protocol and records
every op; a fake `audi` that replays transcripts with realistic partial
timing; a fake agent driver with scripted outputs; a controllable clock; and a
runner for scripted sessions written as YAML.

**Why it is separate — and why it is first.** Every stage of the roadmap says
"eval before and after, both numbers in the commit message", which is a habit
this project inherited from reflexi and which is worth keeping. Without a
harness that runs a whole session without a device, that habit dies at Stage 2.
Building it during Stage 0 costs about a day. Building it during Stage 4 costs
Stage 4.

It doubles as the way to develop cogiti on WSL2, where there is no
microphone worth using, no camera, and a software renderer.

**Blocks:** honest measurement in every stage. **Blocked by:** nothing.

---

## 7. The service SDK and template library

**What it is.** The `cogiti.service` module in `../../cogiti/docs/services.md` §3, plus a small
library of templates: a poller, a webhook watcher, a scheduled task, a log
follower.

**Why it is called out separately.** It is the thing an agent writes against,
and it is therefore what decides whether a generated service is twelve
reviewable lines or three hundred unreviewable ones. **The SDK is the review
gate's real mechanism**, and every capability it does not expose is one a
generated service cannot casually acquire.

It can be built now, against avatari alone, with no cogiti present —
`avatari/tools/avatari_feed.py` is already two thirds of it and its docstring
is the design.

**Blocks:** Stage 5. **Blocked by:** nothing.

---

## Upstream asks: work in the repos that already exist

These are not new projects, but they are parallel work, and some of them are
on cogiti's critical path.

### reflexi

| ask | why | when |
|---|---|---|
| **a shared-library target** (`libreflexi.so`) | cogiti binds by ctypes; only `libreflexi.a` is built today | before Stage 1 |
| **new intents**: `list_jobs`, `job_status`, `job_logs`, `cancel_job`, `what_are_you_doing` | Stage 4 says these belong in the registry, not in cogiti's code | Stage 4 |
| **new intents**: `pin_thing`, `unpin_thing`, `list_services`, `service_status` | same, for Stage 5 | Stage 5 |
| **new intents**: `forget_that`, `what_do_you_know`, `what_have_you_done` | Stages 6 and 7; the trust-facing ones | Stages 6–7 |
| **a runtime pattern overlay** | a service born at 3pm cannot be in a blob compiled at build time. Patterns go through the deterministic pre-matcher and need no embeddings, so an overlay needs no model, no Python and no compiler on the device. This is the elegant answer to the hardest routing problem in the project | Stage 5 |
| **real static embeddings** to replace `hash-v1` | today "temperature" and "weather" are unrelated. Coverage is 75.5% and this is why | any time |
| **trace-mined exemplars** | cogiti's trace log is the corpus; the loop only closes if somebody closes it | continuous |

### avatari

| ask | why | when |
|---|---|---|
| **`chart` kind** | already "designed, not built", and it is the one composition that genuinely earns a kind. Escalated answers want charts | Stage 3 |
| **`list` kind** | same list, and every "here are your options" answer wants it | Stage 3 |
| **input events, renderer → brain** | the channel exists and carries only `hello`. Stage 9's setup flows and any selectable list need it | Stage 9 |
| **region restriction at `hello`** | today a service is confined to the periphery by cogiti's policy at spawn, not by the renderer. A `hello` that declares `region:"periphery"` and is held to it would make the rule enforceable rather than agreed | Stage 5 |
| **`surface` over dmabuf** | the only path to a browser without a display server. Not needed yet; the largest thing on the list | later |

### lfs / distros/inteliboy

| ask | why | when |
|---|---|---|
| **a writable data partition for `/var/lib/cogiti`** | services an agent wrote and everything the device remembers are exactly what an image update would destroy. This is the single most important item in this table | before Stage 5 ships |
| **a `cogiti` init script** | same shape as the avatari one, started after it, restarted on exit | Stage 1 |
| **the Python runtime closure** in `packages.list` | python, sqlite, openssl, curl; computed the same way avatari's closure was | Stage 1 |
| **the models** as their own package | whisper, Piper voices — like `avatari-voices`, big and separately versioned | Stage 2 |
| **update and rollback** | roadmap Stage 11; and a factory reset that is complete | Stage 11 |
| **wifi and time** | `wpa_supplicant` and `iw` are in `packages/` already; `dhcpcd` too. Stage 9 needs them configured by cogiti, not by hand | Stage 9 |

---

## Suggested order

If several sessions can run at once, this is the order that unblocks the most
soonest:

**Now, in parallel, all unblocked:**

1. `probi` — because every "both numbers in the commit message" depends on it.
2. reflexi's `libreflexi.so` — an hour, and Stage 1 cannot start without it.
3. The service SDK, against avatari alone.
4. `audi` — the longest lead time of anything here, and entirely independent.
5. The lfs data partition question — because the answer changes Stage 5's
   design and nobody wants to find that out afterwards.

**Next, once the two protocol specs exist (a day's work in cogiti Stage 0):**

6. `agenti`.
7. `custodi`.
8. `memori`, with its eval corpus.

**When there is a camera:**

9. `vidi`.

**Continuously, by whoever is closest:** reflexi's intents as each stage needs
them, and avatari's `chart` and `list` before Stage 3 lands.

Meanwhile cogiti itself goes stage by stage down `roadmap.md`, and its work is
mostly the routing, the registries, the turn machine and the supervision —
which is what it should be, and is much smaller than the list above once
everything else has a home.
