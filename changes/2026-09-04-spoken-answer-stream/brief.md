# 2026-09-04-spoken-answer-stream — speak the answer as it is written

## The ask

An escalation says nothing for a minute and then delivers a paragraph.
Measured over eleven real turns: fastest 4.5 s, **median 68 s**, slowest 86 s.
Every one of them past five seconds becomes two disjoint utterances — "I'm
still working on that" and, a minute later, "About <your question> — …".

That is the largest remaining break in the conversation, and no detach window
fixes it. The distribution is bimodal: a plain question answers in seconds, a
question that searches takes a minute. A 5 s window keeps 9% of answers whole;
30 s keeps 27% and makes every quick answer wait.

## The seam

`agent-protocol.md` §7 rules out streaming a partial `result`, and the reason
given is sound:

> A result is structured and arrives once. `thought` and `progress` carry the
> sense of movement; a half-built result would tempt the presentation layer
> into rendering something that is about to change.

The objection is about the *structured* half — `show` and `did` — which is
retained on a screen and must not flicker. **Speech is not presentation.** A
spoken sentence is gone the moment it leaves; it cannot be about to change,
and nothing renders it.

So this does not add a partial result. It adds a third informational event
alongside `thought` and `progress`, distinguished by where it is allowed to
go: `say` reaches the speech port and nothing else.

## Shared vocabulary

```json
{"v":1,"type":"say","text":"Sunlight is a mix of colours."}
```

- **Speech only.** Never drawn, never retained, never in `show`.
- **A sentence at a time**, not a token: the speech port synthesises a phrase,
  and a word at a time is neither speakable nor interruptible.
- The terminal `result` still arrives once and still carries `show` and `did`.
  Its `say` is the whole answer, for the trace and the history — **but is not
  spoken again** if anything was streamed.

## Positions

**The presentation layer must not see it.** That is what §7 was protecting and
the rule survives intact: `say` events do not reach `present.py`. The screen
still gets one composed `show` when the result lands.

**Speaking cancels the detach.** The holding line exists because nothing was
happening for five seconds. If the device has begun answering, something is
happening — so a turn that has started speaking does not detach, and there is
no "About X —" prefix because the answer is not late.

**Half duplex is unchanged.** cogiti already mutes while speaking; a sequence
of sentences is one speaking stretch rather than several, and barge-in cancels
the remainder as it cancels any utterance.

**A failure mid-answer is audible.** If the run fails after some sentences were
spoken, the person has heard half an answer and must be told, rather than the
device falling silent.

## Per repo

### cogiti      [order 1]
Owns the protocol. Adds the `say` event to `agent-protocol.md` §4 and moves
the §7 entry from "absent" to "present, and here is the line that keeps its
reasoning". `adapters/agent.py` routes it; `session.py` speaks it and treats
having spoken as reason not to detach.

### inteliboy   [order 2]
The anthropic adapter emits it: `eager_input_streaming: true` on the `answer`
tool so the `say` field arrives while it is being written, split into
sentences.

## Not in this change

- Streaming `show`. The screen composes once, for the reason §7 gives.
- Interrupting the model mid-sentence to re-plan. Barge-in stops speech; it
  does not edit the answer being generated.
- Any change to how a *job's* late answer is delivered. A turn that genuinely
  outlives its person still detaches and still says "About X —".

## Rollback

The adapter stops emitting `say` and cogiti stops receiving them; both halves
are additive and a run with no `say` events behaves exactly as it does today.
