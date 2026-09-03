# 2026-09-03-stage-5c-routing — saying the sentence a service claimed

Status: **landed** — cogiti 0.9.0.
Approved by: the user, 2026-09-03

## The ask

The device wrote `bitcoin-price` yesterday and its manifest lists five
sentences — "what's the bitcoin price?", "show me bitcoin", "what is BTC
trading at?". None of them do anything: reflexi's blob was compiled before the
service existed, so those sentences escalate to the model like any other.

## The mechanism is already decided

`docs/services.md` §5 chooses it and argues against the alternatives, including
one an earlier version of that document proposed as the right answer. Nothing
here re-opens that:

- **cogiti's own pattern layer.** Before escalating, match the normalised
  utterance against `[phrases].patterns` from every installed manifest.
- **Exact and pattern matching only.** The same tier discipline reflexi's
  pre-matcher has, for the same reason: a born service must not steal traffic
  from a built-in on a fuzzy score.
- **Built-ins always win a tie.**
- **Not a reflexi overlay.** §5 is emphatic: an overlay adds *exemplars to
  intents that already exist*, and a service born at three in the afternoon is
  a **new intent reached by pattern** — two things that rule forbids, plus a
  third collision, since exemplars match by cosine and that is exactly the
  tier ruled out here. "A resolver that stays immutable is one whose accuracy
  can be evaluated before it ships."

**What it costs, in §5's own words:** listed phrasings only. "what is eth at"
reaches the service; "how is ethereum looking" escalates. That is accepted.

## The question the document does not answer

**What happens when a phrase matches?** The service is a standing duty already
pinned to the screen, so "what's the bitcoin price" is not a request to *start*
anything. Three readings:

  - *(a)* **Say the value.** The natural answer to a question — but cogiti does
    not have it. The service connects to the renderer directly and cogiti never
    sees what it drew. It would need the SDK to report each value to cogiti as
    well as showing it: a small addition to the broker protocol, and the only
    option that answers the question asked.
  - *(b)* **Draw attention to the panel.** cogiti says something like "it's in
    the corner" and highlights it. No new protocol, and it answers a different
    question from the one asked.
  - *(c)* **Both** — say the value and glance at the panel.

I favour (a), and it is worth being explicit that it makes the SDK's `show()`
report upward. That is the first time a service tells cogiti anything, and it
is one field.

## Per repo

### cogiti     [order 1]
files:  `phrases.py` (new: the pattern layer), `session.py` (consult it before
        escalating), `service/__init__.py` (report the value, if (a)),
        `broker.py` (accept it, if (a)), `docs/services.md` §5 → specification
change: normalise with `reflexi_normalize` so both layers agree what
        "normalised" means rather than having two ideas of it; match exactly;
        built-ins win; **negative cases**, because §5 says adding a service is
        a reason to add them and not only positive ones.
proves it: "what's the bitcoin price" answers from the service; "what time is
        it" still reaches the built-in; a service claiming "what time is it"
        does not get it.

## Not in this change

- **Recompiling the blob on device.** §5 rejects it on size and this does not
  revisit that.
- **Generalising past listed phrasings.** The model remains the general answer.
- **Removing a service's phrases on removal.** Already true by construction:
  the patterns are read from installed manifests, and removal moves the
  directory.

## Failure modes

1. **The land-grab.** A service claiming a sentence a built-in owns. Built-ins
   win ties, matching is exact, and the phrases were read aloud at the gate —
   three guards, and §4 says the third is the one that catches a claim no
   built-in has.
2. **The stale phrase.** A pattern that outlives its service. Cannot happen if
   patterns are read from live manifests rather than cached, which is the
   whole of §2's discipline applied here.
3. **The false accept.** "Whatever the mechanism, a born service must not
   answer a sentence that was meant for something else."


## What landed, and the thing a device found

Answered (c): say the value **and** glance at the panel. The first half is
built; **the second half is not possible today and that is a finding, not an
omission.** avatari's scene protocol says "the periphery never takes the gaze
at all" — deliberately, so a feed updating once a second does not drag the
eyes back. A service is pinned to the periphery by rule (§9), so there is no
way to glance at one without a change avatari owns.

Proved by asking:

- "what's the bitcoin price?" → "the Bitcoin price: BTC $77613.735", with no
  model call
- "how is bitcoin looking" → escalated, exactly as §5 says it must
- "what time is it" → still the built-in

**And then the device found the case the design implies but nobody had said
out loud.** "Show the weather" resolved to the built-in `pin_thing` rather
than to the weather service that claims that exact phrase. Built-ins win, so
that is the rule working — and the consequence is a service listing a sentence
it will never receive, with nobody any the wiser. The gate now says so before
you approve it: *"I won't get 'show the weather' — that already means
something else. Shall I keep it anyway?"*

## Still open

- **The glance.** Needs an avatari change: either a way to direct attention at
  a pinned object by id, or an exception to the periphery rule. It is a
  presentation-protocol change and avatari owns that contract.
