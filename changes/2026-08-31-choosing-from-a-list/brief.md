# 2026-08-31-choosing-from-a-list — a `choosing` turn state

Status: **applied to cogiti's working tree — a design, since cogiti has no code**
Approved by: Alexander Marinov, 2026-08-31

## The ask

A way to present a list and let the user pick: by number, by saying the item's
name, or by navigating up and down with the voice.

## Why it is a primitive and not a skills feature

It arrived while designing how the skill catalogue is chosen from, but a
catalogue is one caller. Removing a service, disambiguating two things that
half-match, offering several memory results and choosing a head all want the
same interaction. Building it inside skills would have meant building it again
three times, and the third one would have been subtly different.

So it is a state in the turn machine, alongside `confirm`.

## The distinction that shapes it

`jobs.md` §6 already argued the opposite case, and it is right:

> nobody says "cancel job 01J8ZQ". They say "stop that", "cancel the repository
> thing", "never mind". Which means job selection is mostly contextual — the
> most recent job, the one just mentioned, the only one running — and ambiguity
> is a question, not a guess.

Both hold, for different sets:

- **contextual reference** for a small set the user already knows — turning
  that into a numbered menu is a regression in naturalness dressed as rigour;
- **an enumerated list** for browsing a set they have *not* seen, where there
  is no "that one" to point at because they do not yet know what is there.

The catalogue is the second kind. Job cancellation stays the first.

## The design

**Three ways to pick, all resolved by cogiti itself.** Item names are cogiti's
data and were never in the resolver's blob — the same arrangement as routing to
a born service, and the same reason: a deterministic layer here, the resolver
left immutable.

| said | means |
|---|---|
| "three", "the third one" | by position |
| "the tracker one" | by name, exact or pattern, never on a score |
| "down", "next", "up", "that one" | by cursor, only where there is a screen |

**Never on a similarity score.** Two items that both partly match is a question
— *"the tracker or the ticket one?"* — not a guess, for the reason `jobs.md`
gives about cancelling the wrong thing.

**Navigation needs a screen, and cogiti knows whether it has one.** A cursor the
user cannot see is not navigation. With no presentation adapter the list is
spoken, the first few with their numbers, then *"or say more"* — and up and
down are not offered. Reading twelve items aloud is not a menu, which was the
open question this started from.

**A list does not trap the user.** Numbers, ordinals, navigation words and the
item names are captured; everything else resolves normally, and a real intent
abandons the choice and says so. "Cancel" and "never mind" always leave. A
`choosing` that goes unanswered expires into cancelled, exactly as a `confirm`
does.

**Selecting is not consenting.** Picking item two from *"which service shall I
remove?"* identifies a target and authorises nothing; removal is `consented`
and still asks with the record from `security.md` §3. This one matters: a list
is a cheap, low-attention interaction, and consent must not become something a
person can give by saying "two".

**The list is a composition, not a new kind** — a group of text, each child
numbered, exactly like the consent view. No adapter changes.

## Applied to cogiti

| file | change |
|---|---|
| `docs/architecture.md` §3 | `choosing` added to the state table, and a subsection covering all of the above |
| `docs/skills.md` §6 | the catalogue question marked answered, pointing at the general mechanism |

The diagram in §3 is not redrawn — `choosing` is noted as a fourth branch
alongside `confirm`, left out to keep it legible. An ASCII diagram that has to
show every branch stops showing the common path.

## Not in this change

- Whether the skill catalogue shows everything or only what the user asked for.
  Still open in `skills.md` §6, and a question about that catalogue rather than
  about lists.
- What a cursor looks like. The adapter owns that, as it owns every other
  question about the screen.
- Ordinal and cardinal parsing beyond the obvious. It is deterministic and
  small, but "the last one" and "the one before that" are real and unlisted.

## Rollback

Two edits in cogiti's uncommitted tree.
