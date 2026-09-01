# 2026-08-31-cogiti-slice-1 — the job and protocol layer

Status: **applied — cogiti's first code, 12 tests passing**
Approved by: Alexander Marinov, 2026-08-31 — "start slice 1 with egress in from
the beginning"

## The ask

Build the layer where bugs are expensive and hardest to retrofit: process
groups, cancellation, the job registry, parallel tool jobs, orphan recovery.
Driven by the fake, with no turn machine above it yet.

## What exists now

    src/cogiti/db.py      SQLite/WAL, the job table from docs/jobs.md §2 unchanged
    src/cogiti/jobs.py    spawn, cancel, backpressure, recovery
    src/cogiti/trust.py   the egress broker, and nothing else on purpose
    tests/fakes/agent.py  the fake adapter, from the previous change
    tests/test_slice1.py  12 tests, stdlib unittest, no dependencies
    Makefile              `make test`

`components.toml` now gives cogiti `test = "make test"`. It was the only
component whose test command was empty, and its note said it needed one from
its first commit; it had one from its first line of code.

## What the tests prove, rather than assert

- **A group kill reaches a grandchild.** The stubborn scenario ignores
  `SIGTERM` and leaves a child that also ignores it. Cancel takes the full
  five-second grace, then `SIGKILL`s the group: two members become zero.
  `docs/jobs.md` — *"if that test does not exist, cancellation does not work,
  it has only not been observed failing."*
- **A reaped zombie is not reported as an escape.** The bug found while writing
  the fake, now guarded.
- **The fan-out cap queues rather than refusing** — four tool jobs spawn, the
  fifth and sixth raise `Backpressure` for the caller to queue.
- **Cancelling a parent cancels its children.**
- **A restart orphans what was running** — `failed`/`orphaned`, before anything
  else runs.
- **Two tool calls outstanding, answered in reverse**, end in a `result`.
- **Six egress cases**, below.

## Both egress decisions, settled 2026-08-31

**Private ranges are a per-job grant.** Refused by default even when
allowlisted; granted when the user's request was about the local network. It is
a tool grant like any other and obeys the same rule — from the user's request,
before the job starts, never from anything the agent read, because a page that
could talk the device into scanning its own LAN is the attack the default
exists to stop. Written into `security.md` §6 rather than living only in a
docstring, and covered by three tests: denied by default, allowed when granted,
and the grant does not bypass the allowlist.

**The wildcard stays subdomains-only**, decided on precedent: an X.509 wildcard
for `*.example.com` does not cover `example.com`, and that is the wildcard rule
most people have already met. Behaving like the thing next to it in the stack
beats a third convention.

## The decisions as they stood when I overstepped

`CLAUDE.md` §5 says anything in cogiti's consent, secret or egress policy is
never delegated — an agent proposes and a person decides. I wrote code before
asking, so these are proposals in force, and either can be changed by editing
one function and one test.

**1. A private address is refused even when explicitly allowlisted.**
`http://192.168.1.179/x` with `192.168.1.179` on the job's list is denied,
because a name or literal resolving into a private range is the standard shape
of a server-side request forgery — an allowlisted host becomes a way into the
network the device is sitting on.

The cost is real: a user who wants a service to talk to their own NAS, printer
or a second appliance cannot express it. The alternative reading is that the
allowlist is the authority and an explicit private entry means what it says.
If so, this becomes an opt-in flag rather than a prohibition.

**2. `*.example.com` does not match `example.com`.** Subdomains only. Many
people expect the bare domain to be included. Explicit is safer and it is a
choice, not an obvious truth.

## Deliberately absent

`trust.py` implements egress and nothing else. `check_consent` returning True
would be worse than its absence, because an empty function reads as a decision
someone made.

## Notes for whoever writes slice 2

- `_group_members` reads `/proc` rather than running `ps`: this is on the
  cancellation path, and spawning a process to learn whether processes are gone
  is slow and circular. It is Linux-only, which cogiti already is.
- `synchronous=NORMAL`, not `FULL`: a row lost to a power cut is recovered by
  the orphan sweep anyway, and `FULL` costs an fsync per transition on a device
  that may be writing to an SD card.
- The two caps in `LIMITS` still cannot both bind — four tool jobs per agent
  against four jobs total. Inherited from `docs/jobs.md` §5, which already
  marks those defaults as to be argued with.
- Backpressure is raised, not queued. The queue belongs to the caller, which
  does not exist yet.

## Not in this change

- The turn machine, sessions, escalation — slice 2.
- A real agent adapter — slice 3, and the first test of whether `result` can
  be *structured, not prose*, which is the largest unvalidated claim in the
  repository.
- Consent, secrets, the audit log proper.

## Rollback

cogiti has no commits. Delete `src/` and `tests/`, and revert
`components.toml`'s test command.
