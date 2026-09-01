# 2026-08-31-fake-agent-driver — the first thing to build, and why

Status: **applied to cogiti's working tree — a design, since cogiti has no code**
Approved by: Alexander Marinov, 2026-08-31

## The ask

How to build the fake agent adapter that `architecture.md` §8 already promises,
so a proof of concept can be written without a model behind it.

## Why it comes first

The agent port is the only required port with a wire. Its fake is therefore the
first thing worth building — and it is also the **reference implementation** of
the port, because whoever writes a real adapter will read it before reading the
prose. That makes its quality a contract question rather than a testing one.

## The design

**A real process on real pipes.** Not an in-process object. The port requires
*a separate process in its own process group*, and an object exercises none of
what that exists for: cancellation, the group kill, and the framing — the three
things most likely to be wrong.

**It does not share cogiti's codec.** It writes JSON by hand, from the document
rather than from cogiti's modules. Sharing the serialisation makes both sides
agree by construction, and a test proving the code equals itself proves
nothing. Inconvenient exactly once; the reason the fake can catch anything.

**It must be able to misbehave.** A fake that only emits well-formed happy
paths tests almost nothing. `architecture.md` §8 now carries the table: ignore
`SIGTERM`, spawn a surviving grandchild, ask a question and never stop waiting,
die without a result, return prose where structure was required, emit a bad
`v`, request an ungranted tool, overrun a budget, declare a capability short,
flood the stream. Each row maps to a stated failure mode or a stated rule, and
together they are the acceptance criterion for the port implementation.

## Deferred, deliberately

- **Stepped execution.** A control channel letting the harness release one
  event at a time, so a barge-in lands exactly between two events instead of
  after a sleep-and-hope. Every hard case is of that shape — barge-in during
  `thinking`, `jobs.md` failure mode 5's *stop*, failure mode 7's two answers
  at once. Deferred until the first such bug, but **the fake is designed with
  room for it**: the channel cannot arrive on stdin, which already carries
  `run` and brokered tool results, so it will want a second descriptor.
  Leaving space costs nothing now; retrofitting changes every scenario file.
- **Speaking an older `v`.** Worth testing version discipline when there is a
  second version to be older than.

## Not in this change

- The message schema itself. Blocked on whether a `tool` event is a request
  cogiti brokers or a notification of something the adapter already did — the
  question under discussion, and the one that decides whether that event is a
  blocking call or a log line.
- The fake presentation and speech adapters. Same pattern, later.

## Rollback

One section added to `docs/architecture.md` §8 in an uncommitted tree.
