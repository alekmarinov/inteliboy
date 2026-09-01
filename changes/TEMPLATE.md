# <change id> — <one line>

Status: draft | approved | landing | landed
Approved by: <person>, <date>

## The ask

One paragraph, in the user's terms. What they want to be true afterwards.

## The seam

Which contract this touches, who owns it, who consumes it.
Additive, or a version bump? If a bump: every consumer lands in this change.

    contract: scene-protocol
    owner:    avatari
    consumers: cogiti, service SDK
    additive: yes — new kind, no version change

## Shared vocabulary

Names every repo must use identically. Anything not listed here is a question
back to the orchestrator, not a local decision.

## Positions

Filled during the survey, in each component agent's own words, including what
it said it would refuse. Kept even when the objection was overruled — a design
whose rejected alternatives are invisible cannot be revisited.

## Per repo

### avatari    [order 1]
files:
change:
proves it:    <the command that fails before and passes after>

### cogiti     [order 2]
...

## Not in this change

What was considered and deliberately left out.

## Rollback

Branch names to delete, lock entry to restore.
