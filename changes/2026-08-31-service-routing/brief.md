# 2026-08-31-service-routing — cogiti routes to a born service itself

Status: **applied to cogiti's working tree — a design, since cogiti has no code**
Approved by: Alexander Marinov, 2026-08-31

## The ask

Settle `CLAUDE.md` §10's first open question: how an utterance reaches a
service that was born after the resolver's knowledge was compiled.

## The feature underneath it

The most ambitious thing cogiti claims to do. The user says *keep the ETH price
on screen*, no such service exists, so one is written, reviewed and installed
while they wait. It then runs with its own uid, its own directory and its own
pinned region.

What was missing is the way back to it **by voice**. You say *"what is eth at"*
the next day; the resolver's blob was compiled months earlier and cannot match
it. Without routing, a service you can see is a service you cannot talk to, and
every such sentence escalates to the model.

## The seam

    contract:  the resolver port, and the service manifest
    owner:     cogiti owns both
    consumers: any resolver adapter; any born service
    breaking:  no. This change *removes* an ask on the resolver.

There is no landing order: nothing in another repository has to do anything.
That is the unusual property of this change and the reason it was cheap.

## The positions

Recorded in the terms each document used, per the rule that a design whose
rejected alternatives are invisible cannot be revisited.

**cogiti asked for a resolver overlay** and called it the right answer: *"The
resolver gains a small runtime-loadable set of deterministic patterns… cogiti
writes `/var/lib/cogiti/patterns.d/<name>.txt` on install and the resolver
picks it up."*

**A resolver's own design forbids exactly that**, in its safety rules:

> An overlay may only add exemplars to intents that already exist in the base.
> It may not define an intent, a slot, a pattern, or a threshold. Everything
> that decides *what the brain does* stays in the shipped artifact.

Three collisions, not one:

| cogiti asked for | the overlay rule |
|---|---|
| a **new intent** for a service born at 3pm | may only add exemplars to intents that already exist |
| deterministic **patterns** | may not define a pattern |
| the `pattern` tier, because a born service must not win on a fuzzy score | exemplars are matched by cosine — the `similar` tier |

They share the word *overlay* and solve unrelated problems. A resolver's
overlay is about **learned exemplars**: a request that keeps escalating and
keeps resolving to the same *existing* intent should stop escalating. Valuable,
and no help at all to a service that did not exist at compile time.

## The decision

**cogiti keeps its own pattern layer, and it is the mechanism rather than a
stopgap.** The resolver's rule is right and cogiti should not ask for an
exception to it: a resolver that stays immutable is one whose accuracy can be
evaluated before it ships and whose behaviour cannot be changed by anything
installed later. A new thing the device can be asked to do belongs in the
component that already owns the command table, consent and policy.

**What it costs, stated in the doc rather than discovered later.** cogiti's
layer matches listed phrasings only. *"what is eth at"* reaches the service;
*"how is ethereum looking"* does not, and escalates like any other unrecognised
sentence. Generalising past listed phrasings is what on-device recompilation
would buy, and that stays rejected on image size.

## Applied to cogiti ✅

| file | change |
|---|---|
| `docs/services.md` §5 | option 2 removed; a new subsection carries both positions, the three collisions, why the resolver's rule is right, and what the decision costs |
| `docs/services.md` §4 | the review gate now reads the phrases aloud, and the approval hash covers the **manifest** as well as `main.py` |
| `docs/services.md` §2 | the manifest's `[phrases]` block says these are sentences the device stops sending to the model |
| `CLAUDE.md` §10 | the question is struck through and marked settled, with the reasoning in one sentence |
| `docs/ports.md` | records that the resolver is the one port with no capability negotiation |

### The gap this closed on the way past

The review gate was explicitly about *purpose* rather than code — rightly, since
a gate that asks a person to audit Python is a gate answered yes every time. But
it named what a service does, where it reaches and which secrets it wants, and
said nothing about **which sentences it claims**. An agent writes those
patterns, for a service it wrote. A price ticker quietly claiming *"what's the
time"* would take that utterance whenever no built-in matched, and the user had
approved a price ticker.

The existing guards half-covered it: built-ins win a tie, and matching is exact
so nothing is taken on a fuzzy score. Neither helps when a service claims a
sentence no built-in has. Three phrases read aloud cost a second, unlike the
code.

Binding the approval to the manifest hash follows from the same argument: a
service that widens its phrase list has changed what the device hears, which is
a new approval even though no code moved.

### The port gap, recorded not fixed

The resolver is a linked library, so it never connects, so the connect-time
capability negotiation every other port uses does not exist for it. Today
nothing needs it — the contract is one function and every resolver must provide
all of it. But an optional capability was proposed here and rejected, and had
it been accepted cogiti would have had no way to ask whether a given resolver
had it. Adding one is a port change.

## Not in this change

- On-device recompilation of the blob. Still rejected on image size.
- Anything about where `/var/lib/cogiti/services/` lives. **That is the
  deployment's concern**, declared by the platform port's `persist` promise and
  met however a deployment chooses. An earlier draft of this brief treated it
  as a cogiti blocker; it is not, and cogiti is usable out of the box on any
  machine where a named path exists.
- Whether a service may act on a partial transcript. Its patterns are
  pattern-tier by construction, so the existing rule appears to permit
  pre-warming but not committing — unstated, and worth stating when the turn
  machine is written.

## Rollback

Five edits across three files in cogiti's uncommitted tree, which has no
commits at all. `git checkout` reverts them.
