# 2026-09-02-stage-5b-authoring — the device writes a service, and asks

Status: **partly landed** — four questions answered 2026-09-02; the
machinery is built and the agent does not yet write the code.
Approved by: the user, 2026-09-02

## The ask

"Keep the ETH price on screen" becomes a service the device wrote, showed you,
and installed only because you said yes. This is **the first stage where an
agent writes code that persists on the device**, and the roadmap gives it its
own boundary for that reason: what a generated service may do, where it runs,
what it may reach, and how you remove one.

## Found while surveying, and already fixed

The 5a broker did its own host matching and never called `trust.check`, so a
service could declare a name that resolves to `127.0.0.1` or a metadata
address — the standard shape of a server-side request forgery, against an
allow-list the user had approved. `trust.py` has refused that since slice 1.
Fixed in cogiti 0.5.1 before writing any of this, because 5b is the stage
where an *agent* writes the manifest that names those hosts.

## The seam

    contract: service manifest (cogiti owns) — additive: `approved` file and
              enforcement of `source_sha`, both already specified in §2/§4

    contract: agent protocol (cogiti owns) — no change. An authoring job is a
              job of kind `author_service`, which docs/jobs.md §2 has named
              since it was written and nothing has ever created.

## The pipeline, from §4

Six steps. Three of them are already possible with what exists:

| step | state |
| --- | --- |
| 1 recognise a standing want | needs an intent and a question |
| 2 authoring job writes it | the agent port exists; the job kind is named and unused |
| 3 dry run against a fake renderer | **nothing exists** |
| 4 static checks | **nothing exists** |
| 5 review gate, out loud | the confirm machinery exists; the wording does not |
| 6 install, record approval with the hash | `manifest.source_sha` is parsed and unenforced |

**Steps 3 and 4 exist so that step 5 is a decision about purpose rather than
about code.** The user is asked whether they want a thing that reads coingecko
every minute. They are not being asked to audit Python — *"a gate that
requires them to is a gate that will be answered yes every time."*

## The questions

**1. What does the static check actually forbid?** §4 lists it: no
`subprocess`, no `eval`/`exec`, no imports outside an allowlist, no filesystem
writes outside its own directory, no socket except through the SDK, every host
in the manifest, size under 32 KB. An AST walk gets all of it. The question is
what happens when it fails: retry the authoring job (§8 allows three
attempts), or stop and say why?

**2. How real is the dry-run sandbox?** §4 says "in the sandbox, against a
fake renderer" and requires *two* valid updates within its own interval plus a
clean SIGTERM exit. We have rlimits and process groups. We do not have
namespaces, seccomp, or a second uid — the shared `cogiti-service` uid from 5a
was decided and never created.

  - *(a)* Dry run under the same rlimits, a fake renderer socket, and a broker
    that permits only the declared hosts. Honest about what it is: a
    behavioural test, not containment.
  - *(b)* Create the `cogiti-service` uid first, so the dry run and the
    installed service both run as somebody who cannot read the secret store.
    Finishes 5a's decision and is a prerequisite for calling this a sandbox.

**3. Who approves, and how?** The gate is spoken and the code is on screen.
"Shall I keep it?" is a confirm, and `confirm` machinery exists. But the
phrases are *part of the decision* — §4 is emphatic that a manifest's
`[phrases]` decides which sentences stop going to the model, so they are read
aloud. Proposal: the spoken gate names the host, the interval, the secrets
(usually none) and **every phrase**, and the card shows the code. Approval is
one yes; there is no partial approval, because "yes but not that phrase" is a
new authoring run.

**4. Where does approval live, and what does it bind?** §4: the hash covers
`main.py` **and** the manifest, because a service that widens its phrase list
has changed what the device hears even though no code moved. Proposal: an
`approved` file holding both hashes, the wording that was read out, and the
time. A service whose files no longer match does not start — it is quarantined
and reported.

## Per repo

### cogiti     [order 1]
files:  `authoring.py` (new: staging, dry run, install), `static_checks.py`
        (new: the AST walk), `manifest.py` (enforce `source_sha`, read
        `approved`), `services.py` (quarantine on mismatch), `main.py` (the
        gate and the intent handler)
proves it: a service authored from a sentence, refused when it imports
        subprocess, refused when its code is edited after approval, and
        installed and running when approved.

### reflexi    [order 2]
files:  `intents/pin_thing.yaml`
change: one intent, `confirm`. "Keep the ETH price on screen", "pin the
        weather", "always show me X".
proves it: `make test`; it must not swallow "what is the eth price", which is
        a question and therefore a job.

## Not in this change

- **5c, routing by voice.** `[phrases]` is still validated and unused. A born
  service is reachable by asking about it, not yet by its own sentences.
- **Modification.** §4 says "modification is birth again" and runs the whole
  pipeline. Correct, and it is the second thing to build, not the first.
- **Secrets for a born service.** Both shipped services need none. A generated
  service asking for a credential is a much larger conversation.

## Failure modes

1. **The gate answered yes every time.** The one §4 names. Steps 3 and 4 are
   the mitigation and they are the work.
2. **The phrase land-grab.** A price ticker that quietly claims "what's the
   time". Built-ins win ties and matching is exact, but neither helps when a
   service claims a sentence no built-in has — hence reading them aloud.
3. **The service edited after approval.** Covered by the hash, and the reason
   the manifest is hashed too.
4. **The agent that writes a service for a question.** "What's the ETH price"
   is a job. §4 step 1 says ask when unsure, and this is one of the few places
   a clarifying question is cheaper than being wrong.

## Rollback

Branch `stage-5b-authoring`; delete it. Nothing is installed by this that a
`rm -rf` of the service directory does not remove, which is §2 working.


## What landed

cogiti 0.6.0, reflexi 0.5.0.

- **Static checks** (`static_checks.py`) — a whitelist, because the adversary
  has a rewrite loop and a blacklist is a list of what somebody already
  thought of. Refuses the forms that make analysis meaningless (`eval`,
  `getattr`, the dunder escapes) rather than trying to analyse them, and
  extracts the hosts the *code* mentions so they can be checked against what
  the *manifest* declares.
- **The dry run** — against a real socket the SDK cannot tell from avatari.
  Two updates, not one: a service that pins a value and then dies has produced
  a screenshot rather than a duty. Plus a clean exit on SIGTERM.
- **The gate's wording** — host, interval, secrets and every phrase.
- **Approval** — binds code *and* manifest; a mismatch quarantines rather than
  starts, and never deletes.
- **The `cogiti-service` uid** — 5a's unfinished decision, now finished. gid,
  then groups, then uid, in that order.
- **`pin_thing`** — and the negative case that caught it swallowing "what is
  the eth price".

## Still open in 5b

**The agent does not write the service yet.** Everything that judges a
generated service exists and is tested; what is missing is the step that
produces one. It needs a decision the brief did not think to ask: the agent
port's `answer` tool returns `say`/`show`/`did`, which is a shape for talking,
not for emitting two files. Either the adapter grows a tool for writing a
staged service, or authoring uses a template the agent fills — and that is a
protocol question, which `CLAUDE.md` §5 says is never delegated and wants its
own decision.

Steps 1 and 6 are also unwired: `pin_thing` resolves but nothing handles it,
and `install()` is tested but not called from a turn.
