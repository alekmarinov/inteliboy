# 2026-09-02-stage-4-jobs — an answer that outlives the turn that asked for it

Status: **draft — not approved. Nothing below is implemented.**
Approved by: —

## The ask

Today the device stops while it thinks. An escalation is awaited inside the
turn (`session.py:120`), so a question that takes Claude twenty seconds is
twenty seconds in which the appliance can do nothing else and, on the evidence
of tonight's traces, is interrupted by any noise in the room and loses the
answer. After this stage a long piece of work runs beside the conversation:
you can ask what it is doing, watch it, cancel it, and be told when it
finishes — and cancelling leaves no process behind.

The roadmap's own bar: *"a long job runs while you ask three unrelated
questions, you can ask what it is doing and watch its logs, and cancelling it
leaves no process behind."*

## What already exists

This stage is much less green-field than the roadmap implies, and the survey
is the reason to say so before proposing work:

| `docs/jobs.md` says | state |
| --- | --- |
| §1 six states | **built** — `db.STATES`, and `turn.py` already knows `needs-input` |
| §2 registry schema | **built** — `job` and `job_log`, ring-buffered |
| §3 process groups, TERM→KILL, reap-then-verify | **built** — `jobs.spawn`, `jobs.cancel` |
| §3 the grandchild test | **built** — `test_slice1.py:87`, and it asserts no false escape |
| §5 backpressure caps | **partly** — `LIMITS` and `Backpressure` exist; nothing queues |
| orphan recovery at startup | **built** — `jobs.recover` |

So the machinery is there and **one thing uses it: timers.** `jobs.spawn` has
exactly two callers, and one of them is a test.

## The seam

    contract: agent protocol (cogiti owns; the Anthropic adapter consumes)
    additive: yes — no wire change. The adapter already streams `thought` and
              `tool` events and does not care who is awaiting it.

    contract: reflexi intent registry (reflexi owns; cogiti consumes)
    additive: yes — five new intents, no format change.

    contract: presentation (avatari owns; cogiti consumes)
    additive: yes — a job log is a `stream` with `attention: watch`, which the
              protocol already has. `docs/jobs.md` §4 fixes the semantics and
              they are already right.

No version bump anywhere. That is worth stating plainly: this stage is large
in behaviour and empty in protocol.

## Shared vocabulary

- **job** — outlives its turn. **command** — finishes inside it. **service** —
  never finishes. Already in `CLAUDE.md` §5; repeated because most of the
  confusion available in this stage is a job being called a command.
- **detached escalation** — an agent job whose turn has ended. Not a new kind:
  `kind = 'agent'` as `docs/jobs.md` §2 already names it.
- **pending question** — a `needs-input` job's question, waiting on a list with
  a deadline. Never a callback.

## The four questions I want answered before writing anything

**1. When does an escalation detach?** Three candidates, and this is the
decision the rest hangs off:

  - *always* — every escalation is a job. Uniform, and makes the common case
    ("what time is it in Tokyo", 3 s) strictly worse: the answer arrives via a
    completion path rather than as a reply.
  - *on a deadline* — it runs inline, and if it has not finished in N seconds
    the turn says "I'm still working on that" and it becomes a job. One
    mechanism, one number to tune. Tonight's measurements put the median
    escalation at 7–14 s, so N is probably 5.
  - *when the resolver says so* — a `long: true` flag in the command table for
    intents known to be slow. Data over code, which this project prefers, but
    it only works for *resolved* intents and escalations are by definition the
    ones that resolved to nothing.

  I favour the second and want it confirmed, because the first is a worse
  device and the third cannot cover the actual case.

**2. Does a detached escalation speak when it finishes, or wait to be asked?**
`docs/jobs.md` §7.7 says one speech queue and everything else waits. But a
device that finishes a job an hour later and announces it unprompted is Stage
12 (proactivity), which is deliberately last and budgeted. My proposal: it
speaks if the same session is still active and idle, otherwise it becomes a
pending item mentioned at the end of the next turn. Never interrupts.

**3. "Stop" is already overloaded.** `docs/jobs.md` §7.5 names it: stop during
speech is barge-in, stop during a conversation about a job is a cancel. We now
have a third — `stop` is a resolved intent today and tonight it resolved from
"never mind" while nothing was running. The turn state must decide, and I want
agreement that the precedence is: speaking → barge-in; a job named or just
mentioned → cancel that job; otherwise → the existing `stop`.

**4. How much of §5 backpressure is in scope?** The caps exist and nothing
queues. I propose implementing the queue and the *"always accept the request,
never silently defer it"* rule, and leaving the token budgets and the shedding
order to Stage 10, where load behaviour lives. Confirm, or pull it forward.

## Per repo

### reflexi    [order 1 — owner lands first]
files:  `intents/list_jobs.yaml`, `job_status.yaml`, `job_logs.yaml`,
        `cancel_job.yaml`, `what_are_you_doing.yaml`; regenerated fixtures
change: five intents. The slot problem is the interesting part and is called
        out in `docs/jobs.md` §6: nobody says "cancel job 01J8ZQ", they say
        "stop that" and "cancel the repository thing". Selection is contextual
        — most recent, just mentioned, only one running — and **ambiguity is a
        question, never a guess**, because cancelling the wrong job is a small
        disaster.
proves it: `make test` (1590 checks) and `make fixtures` regenerated. Negative
        eval cases required: "what are you doing" must NOT resolve to
        `job_status` when nothing is running and it is small talk.

### cogiti     [order 2]
files:  `session.py`, `escalate.py`, `jobs.py`, `turn.py`, `present.py`,
        `providers/jobs.py` (new), `docs/jobs.md` (proposal → specification)
change: detach an escalation past the deadline; the pending-question list;
        queue on backpressure; five providers; a job log as a `stream` with
        `attention: watch`, destroyed in a `finally` on every terminal
        transition (§7.3).
proves it: a scripted session that starts a job, interleaves three unrelated
        turns, asks what is running, cancels it, and asserts the process table
        is clean. The roadmap's bar, as a test.

### inteliboy  [order 3]
files:  `config/commands.toml`, `distros/inteliboy/files/etc/cogiti/commands.toml`
change: five table entries. `linger = 0` for a job panel — it is something to
        act on, not to read.
proves it: `make verify-device` on hardware, and a job started by voice.

## Not in this change

- **Proactive announcement.** Stage 12, budgeted, deliberately last.
- **Token budgets and the shedding order.** Stage 10 — see question 4.
- **`parent_job` depth two.** The schema has it and nothing uses it; an agent
  fanning out to child jobs is real but is not needed to clear this stage's
  bar, and it doubles what cancellation must be correct about.
- **Services.** Stage 5. A job finishes; a service does not.

## Failure modes

`docs/jobs.md` §7 lists eight and I am not restating them. Two are ours to
worry about *first* because the code around them changed tonight:

- **§7.5, the wrong cancel** — question 3 above.
- **§7.7, the interleaved answer** — two jobs finish while you are talking to a
  third thing. There is one speaker, and it is now muted while it talks
  (half duplex, since `libspeexdsp` cancels 0.9 dB on this hardware). A queued
  announcement arriving during a mute is the concrete version of this bug.

## Rollback

Branches `stage-4-jobs` in reflexi and cogiti; delete both. `versions.lock`
restores to the InteliBoy 0.1.0 entry, which is a booted, verified set.
