# 2026-08-31-consent-record — the consent question is derived, and shown as well as spoken

Status: **applied. No renderer change is needed and none is proposed.**
Approved by: Alexander Marinov, 2026-08-31 — the idea, and option (a).

## The ask

What the user is asked to approve should be presented concisely on the
renderer: not only as text, but graphically, so it can be understood rather
than merely heard.

## The seam

    contract:  consent — cogiti's alone
    owner:     cogiti
    consumers: every deployment with a screen; deployments without one are
               unaffected and still speak the question
    breaking:  no, and no second repository is touched.

**There is no landing order, because only one repository changes.** The
consent view is a composition of scene kinds that already exist, so the
renderer needs nothing — see the decision below.

## The finding that made this more than a feature

`security.md` §3 already required that *"the prompt states the effect in the
world, not the mechanism"*. It did not say **who writes that sentence**, and
that omission was the hole.

If the agent phrases the question, then a manipulated agent phrases it in its
own favour, and every mitigation in §4 ends at the last honest component. The
user is the final check, and the final check was reading text written by the
thing it is checking.

So the record is **derived from the call that is about to be made** — the
recipient, the host, the amount, the path — not from the agent's account of it.
A manipulated agent can still change *what it asks for*; it can no longer
change *what the user is told it asked for*. The two can no longer disagree.

That is the part worth having whether or not anything is ever drawn.

## Why a picture, specifically

"Send money to an account you have not used before" and "send money to your
landlord, as you did last month" are the same sentence shape and different
decisions. Heard once, at the moment of use, the difference is easy to miss.
What is actually being weighed — who, what, how much, whether it can be taken
back — is a small graph, and a small graph is what a screen is for.

## Applied to cogiti ✅

`docs/security.md` §3 gains:

- **the consent record** — `id, class, effect, actor, resources[], reversible,
  on_refusal, expires` — built by cogiti from the concrete action;
- **two renderings, one record**: spoken always, because a device may have no
  screen, generated from cogiti's own templates and never from model prose —
  the same rule that makes the agent port return a structured answer rather
  than text to read aloud; and shown, where a screen exists, over the
  presentation port;
- **the screen never carries the answer.** Consent is spoken or pressed on a
  physical control, never inferred from the display, and a `confirm` still
  expires into cancelled.

It also closes an open question in `skills.md` §6: approving a changed skill is
a consent decision, and what the user is shown is the record — which tools,
which hosts — rather than four kilobytes of instructions to be judged by ear.

## The decision: the renderer draws it, and needs no change to

**Option (a), and it turned out to cost nothing.** The renderer's protocol sets
an explicit test for a new kind:

> *Something earns its own kind only when the renderer can do it genuinely
> better than a composition could — data-driven geometry, per-frame updates, or
> interaction. A chart qualifies... `weather` never qualifies.*

A consent view is a title, a few labelled resources and an undo note: a group
of text objects. The same shape as `weather`, which that rule names as never
qualifying. Symbols need no kind either — the protocol is explicit that there
is no icon kind and does not need one, because a warning sign, an arrow and a
currency symbol are ordinary characters in a `text` object with per-glyph font
fallback.

So the consent view is described by cogiti as a composition, drawn by any
adapter that draws at all, and **no renderer changes** — which also means it
works on the day cogiti can first ask a question, rather than waiting on a
second repository to land something.

What cogiti sends is an ordinary group:

    {"op":"create","id":"consent/1","kind":"group","children":[
      {"kind":"text","style":"title",   "text":"Send EUR 240 to Maria Petrova"},
      {"kind":"text","style":"caption", "text":"to maria@example.com"},
      {"kind":"text","style":"caption", "text":"! new recipient - not used before"},
      {"kind":"text","style":"caption", "text":"cannot be undone"}]}

Every field comes from the record, and the record came from the call. It earns
a kind of its own only if it ever needs what a composition cannot do, and it
does not need that in order to be understood.

## The enhancement path, for later

If a group of text stops being enough — if the difference between a familiar
recipient and a new one wants a real diagram rather than a warning glyph — the
next step is **a separate component that composes the record into a scene**:
record in, scene out. It earns its place when that composition becomes ongoing
design work. An iconography for "money leaves your account", "a message reaches
a person", "this cannot be undone" is a design system, not orchestration logic,
and cogiti's non-goals already exclude it having *"a web UI, a settings app, or
any screen of its own"*.

Two things make deferring it safe. The **record is the seam either way**, so a
composer inserted later changes no contract. And **the safety property does not
depend on any of this** — it comes from the record being derived from the call
rather than from the agent, which is already true.

If it does become a component it needs a name and an entry in
`components.toml`, and it would be the first component whose job is
*explanation* rather than a capability.

## Not in this change

- A `consent` scene kind. It does not earn one, by the renderer's own test.
- An iconography. That is the work the enhancement path exists to hold.
- Consent on a device with no screen and no physical control — still spoken,
  still the weakest case, and unchanged by this.

## Rollback

cogiti's edit is one section in an uncommitted tree with no commits at all;
`git checkout` reverts it. Nothing else has been touched.
