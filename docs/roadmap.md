# cogiti — roadmap

The orchestrator for InteliBoy. Listens, resolves, decides, dispatches,
remembers.

```
audio ──▶ audi ──┐
                 ├──▶ cogiti ──▶ reflexi ──▶ decision
text channel ────┘       │
                         ├── handle   ──▶ command ──▶ avatari
                         ├── confirm  ──▶ ask, wait, then command
                         └── escalate ──▶ agent ──▶ answer + card + speech
                                            │
                                            └──▶ long job / born service
                                                 ──▶ supervisor
```

**Each stage is shippable.** The device must be usable at the end of every one
of them, which is the main constraint on the ordering and the reason a
tempting reordering is usually wrong.

`CLAUDE.md` is the design. This file is the order of work and what "done"
means. Start a stage with a short prompt that names the stage and points at
these two files; do not paste the plan into the prompt.

---

## The shape of the whole thing

| stage | what it adds | the device can, at the end |
|---|---|---|
| 0 | decisions, contracts, stubs | nothing new — but nothing is ambiguous |
| 1 | the text spine | be driven by typing, for every reflexi intent |
| 2 | voice in and out | be used hands-free, with no LLM present at all |
| 3 | one agent, blocking | answer a question it was not programmed for |
| 4 | concurrency and the job supervisor | do something long while still talking to you |
| 5 | feeds, pinning, and born services | grow a new capability at your request |
| 6 | memory | stop asking you what it already knows |
| 7 | credentials and external tools | act on the world, with consent |
| 8 | vision and speaker identity | know who it is talking to |
| 9 | configuration by voice, and the owner's own credentials | be set up without a keyboard, and spend nobody else's quota |
| 10 | persona and load behaviour | be honest when it is overloaded |
| 11 | update, backup and reset | be updated without forgetting you |
| 12 | proactivity | speak first, at the right moment, rarely |

Stages 11 and 12 are new and are not optional. 11 is the stage that makes
everything the user taught the device in 5–8 survivable; 12 is the difference
between an appliance that answers and an assistant.

---

## Stage 0 — Decisions and contracts

No behaviour. This stage exists because the decisions are expensive to reverse
and a coding agent will pick one arbitrarily if you leave them open.

**Decided, in cogiti's `CLAUDE.md` §4** — language, process model, agent runtime,
inference location, avatari transport, persistence, session model, reflexi
binding and time. Each carries what it rules out.

**Still to produce in this stage:**

- Module stubs for cogiti's `CLAUDE.md` §6 with signatures and docstrings, no logic.
- The line-JSON protocol specs for the two seams cogiti does not own:
  `agenti` (job runner) and `audi` (speech). One page each. They are what makes
  those repos startable in parallel — see `subprojects.md`.
- `config/commands.toml` with three entries and no code behind them, to prove
  the shape before Stage 1 depends on it.
- The eval harness skeleton: a scripted session runner with a fake avatari, a
  fake clock and a fake agent. Every later stage adds cases to it; building it
  now costs a day and building it at Stage 4 costs the stage.

**Done when:** someone reading `CLAUDE.md` can explain what cogiti will not do,
and `probi` can run an empty scripted session end to end.

---

## Stage 1 — The text spine

Prove the whole path with no voice and no LLM.

Text on stdin or a socket → reflexi → command table → avatari renders. Handle
and confirm verdicts both work. Escalate logs and says "I can't do that yet."

The command table is the new artifact: a declarative map from intent id to an
action, its slot bindings and its avatari presentation. Same principle as
reflexi's registry — adding a command is data, not code. `../../cogiti/docs/command-table.md` is
its contract.

**Also in this stage, because they are cheap now and awkward later:**

- The turn state machine (`../../cogiti/docs/architecture.md`), including the confirm path with
  a timeout that expires into *cancelled*, never into *yes*.
- The avatari client: reconnect with backoff, re-declare on connect, `hello`
  with namespace `brain`, capability negotiation stored and honoured.
- `busy` sent the moment a turn starts, before any work.
- The trace log, one line per turn.

**Done when:** typing "what's the weather in Sofia" renders a weather card, and
"power off" asks for confirmation before doing anything — and killing avatari
mid-session and restarting it leaves the next turn working.

**Do not:** touch audio, LLMs, memory, or concurrency.

**Eval:** a scripted session per reflexi intent, asserting the scene ops
emitted. This is the file every later stage appends to.

---

## Stage 2 — Voice in and out

STT behind a backend interface with one implementation. TTS out. Wake word or
push-to-talk. Barge-in, so the user can interrupt speech.

The implementation lives in `audi`, its own repo and its own process, because
it is CPU-heavy, has to be developed against a microphone rather than against
cogiti, and is the one component most likely to have to move to another
machine if the box turns out too weak. cogiti's half of this stage is a client
and a protocol, and is small.

Latency work belongs here: start feeding reflexi on partial transcripts rather
than waiting for the final one. A pattern-tier match on a partial is safe to
act on early; a similarity-tier match is not, because the next word can change
it. That distinction is available in the decision (`tier`), so use it.

Barge-in is a three-party dance and worth writing down: `audi` reports speech
started, cogiti sends avatari `{"op":"stop"}` and stops the current job's
speech, and only then does it start listening for the new turn.

**Done when:** the device is usable hands-free for all of reflexi's intents,
with no LLM in the system at all, and talking over it stops it mid-word.

**Do not:** design the STT interface around one vendor's streaming semantics.

**Eval:** recorded utterances through the real STT into the same scripted
session harness; word-error rate and end-of-speech-to-first-word latency, both
in the commit message.

---

## Stage 3 — Escalation to one agent

The first LLM in the system. Escalate spawns a single agent, synchronously,
blocking the turn. It returns an answer, a card for avatari, and speech.

Deliberately blocking. Concurrency is Stage 4 and mixing them makes both hard
to debug.

Prompt assembly gets its own module now, even though it has little to
assemble yet — Stages 6 and 7 both feed it, and retrofitting it is worse.

**The agent's output is structured, not prose.** It returns a result object:
what to say, what to show, and what it did. Prose straight from a model into
a text-to-speech engine is how an assistant ends up reading a bulleted list
aloud. The presentation layer, not the model, decides what a result looks
like.

**Also here:** the honest-failure path. No network, no key, model returns an
error — each has a spoken answer and none of them is silence.

**Done when:** an escalated question produces a spoken answer and a rendered
card, and pulling the network cable produces a spoken apology instead of a
hang.

**Do not:** give the agent tools beyond what it needs to answer. Actions come
later, deliberately.

---

## Stage 4 — Concurrency and the job supervisor

The hardest engineering stage. Agents detach, cogiti stays responsive, a job
registry tracks what is running. `../../cogiti/docs/jobs.md` is the proposal; agree the
lifecycle and the schema before writing any of it.

- Job lifecycle: spawn, running, needs-input, done, failed, cancelled.
- Status, progress and log streaming to avatari. The stream protocol already
  exists and its `attention` semantics are already right: a thought stream is
  `never`, a running job's log is `watch`.
- Cancellation that actually kills children. Process groups, `SIGTERM` then
  `SIGKILL` on a deadline, and a test that asserts no grandchild survives.
- New reflexi intents: `list_jobs`, `job_status`, `job_logs`, `cancel_job`.
  These belong in reflexi's registry, not in cogiti's code.
- Backpressure: what happens at the Nth concurrent job, and what the device
  says when it happens.
- **needs-input is the subtle one.** A job that stops to ask a question has to
  reach the user through the same turn machine everything else uses, without
  hijacking a conversation that has moved on. Queue it, surface it as a
  pending question the user can be told about, and let them answer when they
  answer.

**Done when:** a long job runs while you ask three unrelated questions, you
can ask what it is doing and watch its logs, and cancelling it leaves no
process behind.

**Do not:** let an agent write to avatari directly. Output goes through cogiti,
or two agents will fight over the screen.

**Eval:** a scripted session that starts a job, interleaves turns, cancels it,
and asserts the process table is clean.

---

## Stage 5 — Feeds and pinning

The stage the whole project is for. `../../cogiti/docs/services.md` is its contract.

Generalise `feed-weather.py` into a **feed contract**: a process that owns a
pinned region, refreshes independently, reconnects, and disappears when it
stops. Most of this already exists as `avatari/tools/avatari_feed.py` and its
docstring is the design — read it before writing anything.

Then the harder half: **an agent authoring a new service on request, and
registering it so it survives reboot.**

Split it, because the first half is a week and the second is the interesting
risk:

**5a — services as data.** The manifest, the supervisor, install and remove by
hand, restart on failure with backoff, start on boot. Ship two hand-written
services (clock, weather) through the same path an agent will use. Nothing
here involves an LLM, and it is all testable without one.

**5b — the authoring pipeline.** An agent writes a service into a staging
directory from a template, runs it against a fake renderer, produces a
manifest, and stops. cogiti presents the diff and what it wants to reach, the
user approves once, and only then is it installed. The approval records the
source hash.

**5c — routing to a born service.** A service that answers "what's the ETH
price" has to be reachable by that sentence, and reflexi's blob was compiled
before the service existed. The stopgap is cogiti's own pattern layer in front
of reflexi; the real answer is a reflexi pattern overlay loaded at runtime.
See cogiti's `CLAUDE.md` §11.

This is the first stage where an agent writes code that persists on the
device. It needs its own boundary: what a generated service is allowed to do,
where it runs, what it may reach, and how the user removes one. All four are
in `../../cogiti/docs/services.md` and `../../cogiti/docs/security.md`.

**Done when:** "pin the ETH price" produces a working feed that survives
reboot, "unpin it" removes it and leaves nothing behind, and a service that
crashes on a loop is stopped and reported rather than restarted forever.

**Do not:** ship agent-authored services without a review step. Do not let a
service reach the stage. Do not give a service a credential it did not
declare and the user did not grant.

---

## Stage 6 — Memory

The knowledge base. Entities — people, projects, places, preferences — with
relationships and provenance. `../../cogiti/docs/memory.md` is the proposal.

- Retrieval before asking. Query memory before putting a question to the user.
- Write path: what gets extracted from a conversation, and when.
- Provenance: stated by the user, inferred, or observed. These are not equal,
  and conflating them is how the device confidently repeats a wrong guess.
- Forget on request, including anything derived from the forgotten fact.
- Contradiction: newer wins, but the older value stays visible in history.

Feeds prompt assembly from Stage 3 and identity from Stage 8.

**Done when:** you can ask about a project without re-explaining it, and
"forget that" actually removes it, including the two things that were inferred
from it.

**Consider moving earlier** — before or during Stage 4 — if you find yourself
re-explaining context to every agent. Poor agent output is usually missing
context, not a missing model capability. Moving it is cheap; the only thing
Stage 6 depends on is that jobs exist to carry the retrieval.

**Eval:** a labelled set of conversations with expected extractions, expected
retrievals and expected refusals to guess. Precision on the write path matters
far more than recall: a wrong fact is worse than a missing one.

---

## Stage 7 — Credentials and external tools

MCP client, plus direct APIs where MCP does not reach. A secret store with
per-service and per-job scoping.

The security boundary is the work here, not the plumbing: which agent gets
which credential, what requires user consent at the moment of use, and what is
never delegated regardless of what the user says. Get this wrong once and the
device sends an email on behalf of someone who did not ask. `../../cogiti/docs/security.md`.

- Consent is per action and per session, never a standing grant, for anything
  that writes.
- The audit log is append-only and readable by the user, in the device's own
  words: "yesterday at four I sent a message to X on your behalf."
- Egress goes through the broker, so a service or job reaching a host it did
  not declare is a refusal and a log line, not a surprise.

**Done when:** an agent can act against one real external service, with
consent prompts on anything that writes, and the audit log can be read back
aloud.

---

## Stage 8 — Vision and speaker identity

Camera pipeline, in `vidi`. QR decoding, OCR, image understanding, face
recognition, and speaker identification from voice.

Identity is the point, not the perception. It feeds Stage 6 — the device knows
who it is talking to, and memory is scoped accordingly.

Biometric templates stay local, are enrolled explicitly, and are never derived
silently from someone who happened to walk past. Enrolment is a conversation,
not a background task.

**Done when:** the device greets the person in front of it by name, reads a QR
code shown to the camera, and answers a question about a project differently
for two enrolled people.

---

## Stage 9 — Configuration by voice

Change voice and avatar model from installed options. Network setup, including
the wifi password by spelling, by camera, or by QR — which is why this follows
Stage 8.

Multi-turn flows with retry and confirmation are the shape here, and they are
their own small state machine. Reusable, because Stage 5's approval and Stage
7's consent are the same pattern. Build it once, in `turn.py`, and make the
three flows data.

**Done when:** the device can be brought onto a new network without a
keyboard, and a wrong password is recovered from rather than restarted.

---

## Stage 10 — Persona and load behaviour

Threaded through everything else but worth a dedicated pass: it complains when
overloaded, always accepts a new request, degrades honestly rather than
silently, and admits what it does not know.

Load shedding is a product decision, not a technical one. Decide what gets
dropped first and say so out loud when it happens. The proposed order, from
first to last: feed refresh rate, then optional presentation (a chart becomes
a line of text), then background jobs, then agent quality (a smaller model),
and never the turn in front of the user.

**Done when:** starting five jobs makes it say what it is putting off, and
finishing them makes it catch up without being asked.

---

## Stage 11 — Update, backup and reset

New, and not optional. From Stage 5 onward the device holds things the user
cannot get back: services an agent wrote for them, and everything it
remembers.

- A writable data partition separate from the root image, so an image update
  is not a factory reset. This belongs to the lfs repo and is the one item on
  this roadmap with a hard dependency outside it.
- Export and import of `/var/lib/cogiti` as one archive, over the network or
  to a USB stick, with secrets excluded by default and included on request.
- Update: new image, same data. Rollback: the previous image, same data.
- Factory reset that is explicit, spoken back before it happens, and complete.
- A schema version on the database and a migration path. The first migration
  after a user has real memory in it is the one that has to work.

**Done when:** an image update leaves every service and every memory intact,
and a factory reset leaves none of them.

---

## Stage 12 — Proactivity

Also new. Everything until now is a response. A timer that fires, a job that
finishes, a service that sees something worth mentioning, a calendar event
approaching — these are the device speaking first, and they are the difference
between an appliance and an assistant.

The engineering is small; the policy is the whole stage:

- What may interrupt speech (nothing), what may interrupt silence (little),
  and what waits for the user to be present (most of it).
- Presence: it should not talk to an empty room. `vidi` answers this and it is
  why this follows Stage 8.
- A quiet queue: things worth saying when next spoken to, which is where
  almost everything belongs.
- A hard budget on unprompted speech per hour, and an intent to turn it off.

**Done when:** a job that finished an hour ago is mentioned when you next walk
up to it, and nothing has interrupted you in the meantime.

---

## Working through this

Start each stage with a short prompt, not a long one:

> Read `CLAUDE.md` and `docs/roadmap.md`. We are starting Stage 4, the job
> supervisor. Before writing code, propose the job lifecycle and the registry
> schema, and tell me what you think the failure modes are. Do not implement
> anything until we have agreed on the shape.

Then implement in pieces within the stage. The design docs carry the context
between sessions; the prompt only says where you are.

Two habits worth keeping from reflexi:

- Every stage gets an eval or a test that can be run before and after a
  change, and both numbers go in the commit message.
- When something needs new code, ask first whether it could be data. The
  command table, the intent registry and the service manifest all exist so the
  answer is usually yes.

And one more, specific to this repo:

- Every stage names the unit of work it is about — command, job or service
  (cogiti's `CLAUDE.md` §5). Most of the confusion available in this project is a job
  being discussed as if it were a service.

## What runs in parallel

Stages 2, 5, 6 and 8 each have a large piece that is a separate repository with
a written interface, and those repositories do not have to wait for cogiti.
`subprojects.md` lists them, what they contract to, and the order that gets
the most work started earliest.
