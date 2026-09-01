# 2026-08-31-agent-port-tools — cogiti runs the tools; the adapter asks

Status: **applied to cogiti's working tree — a design, since cogiti has no code**
Approved by: Alexander Marinov, 2026-08-31

## The ask

Settle what a `tool` event on the agent port means, because the message schema
cannot be drafted until it is known whether that event is a blocking call or a
log line.

## What was ambiguous

`ports.md` gave the agent port as
`run(prompt, tools, budget) -> thought | tool | progress | question | result | failed`
and never said who *executes* a tool. `jobs.md:47` has a job `kind` of
`'agent' | 'tool' | 'author_service'`, implying cogiti spawns them; the `tool`
event implies the adapter is doing something. Both readings were live.

## The decision

**A `tool` event is a request with an id. cogiti executes it and answers. The
adapter never runs one itself.**

This makes `security.md` §1 mechanical rather than aspirational — *an agent is
never a principal; it proposes and cogiti decides* — and every tool use lands in
the audit log by construction rather than by an adapter's good manners.

### The split that was proposed and dropped

An earlier proposal in this discussion had two kinds of `tool` event: brokered
for anything crossing the sandbox boundary, a notification for work inside it.
It was dropped as unnecessary. `run(prompt, tools, budget)` already defines what
a tool *is* — the granted set — so anything an adapter does internally is
simply not a tool on this wire. It is the adapter's own business, bounded by
`confine` and the egress broker.

The boundary was already drawn by the grant; a second one in the protocol would
have been a chance for the two to disagree, which is where these systems leak.

### Two consequences worth stating

**`tools` in `run` is the whole of what a job can reach.** An ungranted tool is
less refused than absent: there is no channel to ask through, and asking anyway
is a security event rather than an error.

**A brokered call is a job, not a function call.** `architecture.md` §1 says the
loop does not compute and does not block; a four-second tool would do both. So
cogiti spawns it as a job of kind `tool` with its own process group, budget and
cancellation. A slow tool cannot stall the turn machine, and cancelling the
agent kills the tool with it, since both are groups under the same job.

## The cost, named rather than discovered

An adapter wrapping a coding-agent SDK must intercept that SDK's own tool
handling and proxy it here, instead of letting the SDK run its loop. That is
real work and it is the main practical objection. It is the price of cogiti
remaining the only thing on the device that acts, and it is worth paying,
because the alternative puts the loop somewhere cogiti cannot see.

## Applied to cogiti

`docs/ports.md`, the agent port: who executes, what `tools` means, why internal
adapter work is not on the wire, why a brokered call is a job, and the SDK cost.

## What this unblocks

The message schema. It was the only thing waiting on this: `tool` is now known
to be a request/response pair needing an id, which is the part of the schema
that could not be guessed.

## Amendment — tool calls run in parallel

I first recommended lockstep: one outstanding tool call, on the grounds that
the agent path has no deadline and concurrency cost a tree-shaped registry.
Overruled, correctly.

Two things I had weighed wrongly:

- *"an escalation answered: whatever it takes"* says there is no **hard
  budget**, not that latency is free there. The user is waiting either way, and
  three 800 ms fetches are 2.4 s serial against 0.8 s parallel.
- **Every current model API emits parallel tool calls natively** — multiple
  `tool_use` blocks, a `tool_calls` array. Lockstep would make every adapter
  serialise what the model already parallelised. That is not only slower, it
  changes what was asked: three independent fetches become sequential, and a
  failure in the first forces the adapter to invent a policy for the other two.
  Pushing that into adapters is what the port exists to avoid.

**The decision: several tool calls may be outstanding. Adapters correlate by
`id`, never by arrival.**

It needed less machinery than I claimed, because the existing backpressure
policy already covers it — *"on exceeding: queue, and say so"*. cogiti bounds
the fan-out and queues beyond it; the adapter is told nothing and simply waits
longer, so the cap stays cogiti's business and out of every adapter.

Three rules that had to be stated rather than assumed:

- a failed tool does **not** cancel its siblings — the agent decides what a
  failure means;
- cancelling the agent cancels all of them, each being a process group under
  the same parent;
- the fan-out queue is the **one** case exempt from "never silently defer",
  because a tool queued inside an escalation is not the user's request. It is
  an internal step of an errand they have already been told about, and
  narrating it would be reporting on the scheduler.

### The schema comment this fixed

`jobs.md` said `-- a job may start one child job, no deeper`, written when a
child meant authoring a service. Once a brokered tool call is a child job that
line had two readings, one of which allowed an agent exactly one tool call for
its lifetime. It now reads: several child jobs, in parallel, none of which may
start their own — depth two, breadth capped in `load.toml`.

## Not in this change

- The schema itself.
- What happens to an in-flight tool result when its agent is cancelled first.
  Dropping it is the obvious answer and it should be written down rather than
  assumed.
- The actual fan-out number. `concurrent tool jobs per agent` is proposed at 4
  alongside a total of 4, which cannot both bind; those defaults are already
  marked "to be argued with once there are real numbers" and this adds one more
  to argue about.

## Rollback

One section in `docs/ports.md`, in an uncommitted tree.
