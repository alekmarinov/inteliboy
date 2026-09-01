# 2026-08-31-cogiti-skills — cogiti names no deployment, and gains a skill layer

Status: **applied to cogiti's working tree — a design, since cogiti has no code**
Approved by: Alexander Marinov, 2026-08-31 — for part 1, and for the reading of
part 2 recorded under Decisions.

## The ask

cogiti must be self-contained: no mention of any other project, and everything
outside it reached through an extension point rather than a name. A **skill**
— in the sense of a packaged set of instructions that teaches an agent how to
operate a particular service — is that extension point. It is first-party:
the user's own, on the user's own device (decision 3).

## The seam

    contract:  the six ports, and (proposed) the skill definition
    owner:     cogiti
    consumers: every deployment, and the agent behind the agent port
    breaking:  no. Part 1 removes names. Part 2 adds a layer that did not exist.

## Decisions

1. **cogiti names no deployment, anywhere.** Not in prose, not as a reference
   implementation, not as a relative path.

2. **A skill does not replace an adapter.** They are different layers:
   **skills teach, adapters carry.** See the analysis below — no port can be
   filled by a skill, for structural reasons rather than stylistic ones.

3. **`CLAUDE.md` §9 stands as written.** "A general plugin API for third
   parties" remains a non-goal. Skills are first-party: authored or reviewed
   by the user who owns the device. The skill layer is how *cogiti's own agent*
   learns to use an outside service, not a socket for other people's code.

4. **A skill is content, and content is never authority.** `security.md` §4
   already says it. A skill may describe how to call something; it may not
   grant the ability to. Tools and egress hosts are granted per job, before the
   job starts, from what the user asked for — never expanded because a skill
   asked. This is the property that keeps a skill from being an injection
   vector, and it is the reason a skill is not simply "a small adapter".

## Part 1 — no other project is named ✅

Applied. `grep -riE '\bavatari\b|\breflexi\b|\binteliboy\b|\blfs\b|…'` across
`CLAUDE.md`, `README.md` and `docs/` returns nothing, and no `../` path
remains.

What was there, and what replaced it:

| where | was | now |
|---|---|---|
| `README.md` | a paragraph naming the first deployment and pointing at `../inteliboy` | a deployment lives in its own repository and is not named here, with the reason |
| `docs/ports.md` ×5 | *Reference implementation: reflexi / avatari / audi / vidi / agenti* | a statement of the **range** of valid adapters, which is what the note was for |

The substance was kept in every case. `README.md` already stated the rule
correctly — *"A deployment supplies adapters for the ports it wants… cogiti
contains nothing about it"* — and then contradicted it in the next paragraph.

## Part 2 — the skill layer ✅ (written as `docs/skills.md`)

### Why no port can be a skill

Checked against `docs/ports.md` rather than assumed. Each fails for a
structural reason:

| port | why a skill cannot fill it |
|---|---|
| **resolver** | a linked library called inline on every utterance *and every partial transcript*, at microsecond scale, whose purpose is to decide **without a model call**. A skill is a model call |
| **presentation** | *ownership per connection* so cogiti and a service share one adapter without colliding, and *last-write-wins, never queued* — "ten prices arriving during one frame should show the tenth". A stateful channel with concurrent writers below frame latency |
| **speech** | continuous audio both ways, partial transcripts feeding the resolver, barge-in |
| **perception** | continuous, and at the lowest trust level the system has |
| **agent** | a category error: this is the port a model is called through. A skill is content flowing *inside* it, not the pipe |
| **platform** | `supervise`, `confine`, `egress`, an unprivileged uid. Privileged operations, and §1 forbids an agent being the principal for them |

The common thread: every port is below a model call in latency, or a
continuous stream, or a stateful multi-writer connection, or a privileged OS
operation. A skill is none of those.

### The three extension points, kept distinct

|  | **port adapter** | **service** | **skill** |
|---|---|---|---|
| is | a supervised process | a generated program | text the agent reads |
| lives | as long as cogiti | outlives the conversation | one turn |
| authority | a principal in §1 | a principal in §1 | **none — it is content** |
| supplied by | the deployment's configuration | an agent, at the user's request | the user, reviewed |
| answers | how this device works | one recurring duty | how to use an outside service |

Renaming "adapter" to "skill" would collapse the first and third columns, and
`security.md` §1 lists *"a presentation adapter — trusted to draw, never to
know anything"* as a principal while §4's defence is *"content is never
authority"*. One word for both merges a trusted principal with the category
the injection defence exists to distrust.

### What a skill declares

- **What it is for**, in one line, so the agent can decide whether to load it.
- **What it requires**: the tools it expects and the hosts it will reach.
  Declared so cogiti can *refuse*, not so cogiti will grant. A skill naming a
  host outside the job's allowlist fails at the broker and is logged as a
  security event, exactly as an injected instruction would be.
- **A version**, and what it was written against.

The declaration is a request, and the answer is cogiti's. That asymmetry is
the whole design.

## The four questions, answered

1. **Where they live, and the danger that creates.** On the platform port's
   writable path, because they are the user's — which makes them mutable while
   the system runs. That is the one genuinely dangerous property here: if
   anything that runs can write a skill, an agent can author instructions the
   next agent reads as guidance. A self-authorising loop, and the exact shape
   of §4's attack with the injection coming from inside.

   Two defences, both required. **The directory is writable by no service
   uid** — structural, via the platform port's `confine`, so a generated
   service can no more author a skill than leave its own directory. And
   **cogiti loads a skill only at a digest the user has approved**, so a
   changed file is either something the user did and can confirm, or something
   that should not have happened and is now visible.

2. **A skill never reaches an adapter.** A skill about the screen teaches the
   agent *what to ask cogiti for*; the presentation adapter still carries it
   and cogiti still decides. Stated explicitly in `skills.md` §2, because
   "a skill for the renderer" is the phrase most likely to be read as a second
   path to the stage, and there is exactly one path to the stage.

3. **A skill is in `security.md` §1 now, as trusted with nothing** —
   *"inform an answer | authorise anything: no tool, no credential, no host,
   no install. It is content"*. The table was silent on the newest thing in
   the system; it no longer is.

4. **`teaches_v` against the port vocabulary**, checked against what the
   adapter negotiated at connect. A skill written for a newer vocabulary than
   the adapter declares is not loaded, and cogiti names the skill and the
   capability — the same failure as a missing port capability, for the same
   reason.

## What was applied

| file | change |
|---|---|
| `docs/skills.md` | new. Six sections: the three-way distinction, what a skill may and may not do, the declaration-as-request, the mutability problem and its two defences, what it is not, and what is still open |
| `docs/security.md` | §1 principal table gains a skill row |
| `README.md` | doc index gains `docs/skills.md` |

## Amendment, 2026-08-31 — a shipped catalogue, not written skills

Dynamic authoring is set aside. **Skills ship with the deployment, read-only,
and the user chooses which are on.** The only runtime state is the enabled set.

This was a simplification that paid for itself three times:

- **The weakest point in the design is gone.** Approving four kilobytes of
  instructions by ear was not review. Enabling a catalogue entry is a consent
  decision built from the skill's *declaration* — "it lets the assistant reach
  tracker.example.com, and use the http tool" — which is a question a person
  can answer out loud.
- **The self-authorising loop becomes impossible rather than defended against.**
  If nothing running can write a skill, an agent cannot author instructions the
  next agent reads as guidance. There is nowhere to write one, so the digest
  rule and the uid rule are both unnecessary.
- **`CLAUDE.md` §9 gets stronger, not weaker.** A skill is first-party because
  it shipped with the deployment and was reviewed by whoever shipped it. No
  mechanism brings anyone else's skill onto the device at all.

It is also the same shape as the routing decision taken the same day in
`changes/2026-08-31-service-routing/`: the artifact stays immutable so it can be
reviewed once before it ships, and the mutable part is small, declarative, and
lives where policy already lives. There it is which patterns route to a service;
here it is which skills are on.

**What it costs, stated in the doc:** a skill for a service nobody anticipated
needs a new deployment, exactly as a new intent does. Worth paying while the
catalogue is small; deferred rather than answered.

## Still open, and recorded in `skills.md` §6

- **How the catalogue is presented and chosen from.** Reading twelve skills
  aloud is not a menu. Probably: the user asks for what they want and the
  device offers the one match, with the full list on screen as a group of text.
  Neither half is designed.
- **Whether the enabled set is per user or per device** — which turns on
  `CLAUDE.md` §10's unresolved question about one conversation or several.
- **What happens to an enabled skill that an update removes.** The choice
  refers to something gone. Silently forgetting is wrong; so is failing to
  start.
- Whether the presentation vocabulary should be the first skill.

## Not in this change

- Implementing any of it. cogiti has no code; this is a design.
- The first actual skill.
- Amending `CLAUDE.md` §9 (decision 3).
- A skill format, a loader, or `docs/skills.md`. They follow the answers above.

## Rollback

Everything is in cogiti's uncommitted tree, which has no commits at all yet:
delete `docs/skills.md` and revert the two edits. Nothing else depends on it.
