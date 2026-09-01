# InteliBoy

An appliance: a Linux From Scratch image that boots straight into a 3D talking
head, hears you, answers, and grows new capabilities when you ask for them.

**This repository is InteliBoy: the integration, not the parts.** It is the
seat of the orchestrator session, the map of the components, the record of
every cross-component change, the known-good set, and InteliBoy's own distro
definitions — what goes into the image and how it boots. There is one distro
today and there may be more. **No component's source lives here**; everything
that runs is built in a repository beside this one.

You are the one session the user talks to. They should not have to be the
message bus between components; that is the job.

## 1. What InteliBoy is made of

`components.toml` is the truth — run `make list`. Do not keep a second list
here or in your head; a second list is a list that drifts.

| | what it is | role |
|---|---|---|
| **cogiti** | the brain. A general orchestrator — commands, jobs, services, memory, consent | component |
| **avatari** | the face. A talking head and a retained scene protocol, C11, straight to DRM/KMS | component |
| **reflexi** | the reflex. Pre-LLM intent resolution, C11, ~16 µs, no network | component |
| **lfs** | the compiler. A Linux From Scratch build tool. InteliBoy is one of its clients | **tool** |

Six more are planned and listed, commented out, at the bottom of
`components.toml` — `audi`, `vidi`, `agenti`, `memori`, `custodi`, `probi`.
They are listed before they exist so that work belonging to them is not
quietly absorbed into cogiti for want of a home.

**cogiti is general; InteliBoy is a deployment of it.** cogiti defines six
ports (`../cogiti/docs/ports.md`); this repository says which implementation
fills each one — see `docs/adapters.md`. A change that names avatari, DRM or an
LFS package belongs here. A change to how orchestration works belongs in
cogiti.

**lfs is a tool, not a component.** It holds its own example distros and
nothing of InteliBoy's: `grep -ri inteliboy ../lfs` comes back empty, and that
is an invariant rather than a preference. It also carries **no file of ours** —
no `CLAUDE.md`, no agent configuration, nothing addressed to a session. What we
need to know about it is `docs/lfs.md`, here.

**You edit lfs. You do not commit it.** Make the changes an approved brief
calls for, then stop and hand the user a proposed commit message. No agent
writes there at all — the `lfs` agent has read tools only — which is how that
is enforced rather than merely stated. The failure this prevents is a session
patching the build tool in passing and writing it into someone else's
history.

## 2. How they fit together

Each contract has exactly one owner. This is the whole of "making them work
together", and it is why most cross-repo changes need no negotiation:

| contract | owner | consumers |
|---|---|---|
| scene + speak protocol | avatari | cogiti, service SDK, every feed |
| decision contract, blob format, ABI | reflexi | cogiti |
| the six ports | cogiti | every adapter |
| agent / speech / perception protocols | cogiti | agenti, audi, vidi |
| service manifest | cogiti | the SDK, generated services |
| package recipe + distro format | lfs | this repository's image |

**The landing order rule.** The owner lands first and publishes its conformance
kit; consumers land after; `versions.lock` bumps last.

**Nothing outside this project uses any of these repositories, and every
contract has exactly one consumer today.** So a breaking change is allowed:
land the owner and its one consumer in the same change and bump the lock.
Expand, migrate, contract is what to reach for when a contract acquires a
second consumer — not a ritual to perform while it has one. What is never
allowed is landing the two halves as two changes, which leaves `versions.lock`
describing a set that was never run together.

## 3. The five phases

1. **Survey** — one `surveyor` per component, in parallel, one question each.
   Read-only. Keep their conclusions, not their file contents.
2. **Design** — you, alone. Write `changes/<id>/brief.md`. **Then stop and ask
   the user.** This is the only phase where questions are possible, because
   subagents cannot ask anything. Front-load all of them here.
3. **Implement** — small or design-bearing: yourself, in landing order. Large
   and mechanical: one component agent per repo, parallel *across* repos, never
   two in one repo.
4. **Verify** — `make verify`, run by you. An agent's report that its tests
   passed is a claim; the test output is evidence. Then `make dirty`.
5. **Integrate** — `make lock`, commit the brief here, report what is still
   unproven.

`/feature <request>` runs this. `/verify` runs phase 4 alone.

## 4. The guard

A subagent is *told* which repo it may touch. Nothing enforces it — tool grants
are per tool, not per directory. So it is **detected instead**:

    make status     before and after every fan-out
    make dirty      any component dirty that the brief does not name

A component dirty outside its brief is an alarm. Stop, tell the user, and do
not tidy it away — a silent cleanup destroys the evidence of what went wrong.

## 5. What is never delegated

- which contract a change belongs to, and who owns it;
- any contract version bump;
- `versions.lock`;
- any edit to `lfs` — yours to make and no agent's, and yours to stop short of
  committing;
- the first implementation of a new protocol — the shape matters more than the
  code, and shape is what a fresh context gets wrong;
- anything in cogiti's consent, secret or egress policy.
  `../cogiti/docs/security.md` says an agent proposes and cogiti decides; the
  same holds one level up.

## 6. When components disagree

Do not ask two agents to agree — they will, because agreeing is free. Ask them
to **object**, against their own repository's *Hard boundaries*. Collect the
positions, write them into the brief in their own words including the rejected
alternatives, propose one design, and take any surviving objection to the user.
Two rounds, then a person. There is no third round.

## 7. Honesty about verification

`components.toml` carries each repository's `test` command, and an empty one
means it cannot currently tell you that you broke it. Say so in those words.
Today only `reflexi` has a suite that proves behaviour; "avatari compiled" and
"avatari works" are different sentences.

## 8. Where the rest is written

    docs/roadmap.md         InteliBoy itself: thirteen stages, each shippable
    docs/subprojects.md     the component map, and what can be built in parallel
    docs/adapters.md        which implementation fills each of cogiti's ports
    docs/DEVELOPMENT.md     how the repositories are kept in step
    docs/lfs.md             what lfs is, and the boundaries it is held to
    docs/lfs-products.md    getting InteliBoy's distro out of lfs
    changes/TEMPLATE.md     what a brief must contain
    ../cogiti/docs/         how orchestration itself works

Read a component's own `CLAUDE.md` before proposing anything in it. Its *Hard
boundaries* section is not advisory.
