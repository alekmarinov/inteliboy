# 2026-09-02-stage-5a-services — a standing duty, not a conversation

Status: **approved** — four questions answered, 2026-09-02.
Approved by: the user, 2026-09-02

## The ask

A service is work with no end: the clock in the corner, a price, a build
status. It starts at boot, restarts when it crashes, owns a pinned corner of
the screen, and is removed by asking. 5a builds all of that **without an LLM
anywhere near it**, and ships two hand-written services — clock and weather —
through exactly the path an agent will later use in 5b. If the path is only
ever exercised by generated code, its first user is also its first test.

`docs/services.md` is the contract and is unusually complete: the manifest,
supervision, removal and the limits are all specified. This brief is mostly
about the four places it does *not* decide, plus honest scoping.

## The seam

    contract: service manifest (cogiti owns; the SDK and 5b consume)
    additive: yes — new file format, no existing consumer

    contract: presentation (avatari owns; a service consumes directly)
    additive: no change at all. §1: a service gets "its own presentation
              connection, its own namespace, pinned region only", and the
              port already requires per-connection namespace ownership. The
              conversation and the pinned world cannot collide because they
              are different regions on different connections.

`avatari/tools/avatari_feed.py` is the design of the connection half, and the
roadmap says to read it before writing anything. Its three rules — reconnect
with backoff, **re-declare on every connect**, notice promptly — are each a bug
the weather feed shipped first. The middle one is the subtle one: after a
renderer restart the value has not changed, so a feed that only sends on change
pins nothing.

## Shared vocabulary

- **service** — never finishes. **job** — outlives its turn. **command** —
  finishes inside it.
- **namespace** — equals the service name, per the manifest. Not a new concept:
  the presentation port already owns it.
- **needs-attention** — stopped after a crash loop, and the device says so next
  time it is spoken to. Not a state a service sets.

## The four decisions, as taken

1. **The broker socket is built now.** A service asks cogiti to fetch and
   cogiti checks the manifest. An allow-list nobody enforces is documentation,
   and 5b installs agent-written code against exactly this manifest.
2. **One shared `cogiti-service` uid.** Cheap, and it stops a service reading
   `/var/lib/cogiti/secrets`, which today it simply could. Per-service uids
   later.
3. **All four limits, with the CPU rate sampled by the supervisor.** The harder
   option, deliberately: `RLIMIT_CPU` is a lifetime total and the manifest says
   per minute, so using it would be a setting that quietly means something else
   and kills a long-running service after some hours.
4. **`[phrases]` is validated and unused.** The format stays stable across 5a
   and 5c, and nothing is invented twice.

## The questions, as asked

**1. How does a service reach the network?** §1 says "only the hosts it
declared, enforced by the egress broker", and the broker lives in cogiti. A
service is a separate process, so enforcement means it asks cogiti rather than
opening a socket itself — which is a new local protocol, and the largest single
piece of work in 5a.

  - *(a)* Build the broker socket now. Correct, and it is the difference
    between an allow-list that is enforced and one that is documentation.
  - *(b)* Ship only services that need no network in 5a — the clock — and take
    weather with the broker in a later slice. Smaller, and leaves the SDK's
    most quoted example (`svc.get_json`) unwritten.
  - *(c)* Let the SDK open sockets directly and treat `[network] allow` as
    advisory for now. **I do not recommend this and would rather not**: it
    makes the manifest lie, and 5b installs agent-written code against exactly
    that manifest.

**2. What uid does a service run as?** §1 says "a name, a namespace, a uid".
Everything on the appliance runs as root today, including the renderer, which
is a deliberate choice recorded in the avatari init script. A per-service uid
is real isolation and means creating users on an appliance that has none.

  - *(a)* Root for 5a, with the limits below doing the containing, and a uid in
    the same slice as the broker. Honest, and matches how the device already
    runs.
  - *(b)* One shared `cogiti-service` uid now — cheap, and stops a service
    reading `/var/lib/cogiti/secrets`, which today it could.
  - *(c)* A uid each. Correct and the most work.

**3. Which limits are actually enforced in 5a?** `[limits]` names four.
`memory_mb`, `open_files` and `processes` map onto `setrlimit` at spawn and are
nearly free. `cpu_seconds = 30` is specified **per minute**, which `RLIMIT_CPU`
cannot express — it is a total, not a rate. Proposal: the three rlimits now,
and the CPU rate with the supervisor's sampling later, rather than pretending
`RLIMIT_CPU` means what the manifest says.

**4. Do the two shipped services get voice patterns in 5a?** `[phrases]` is in
the manifest and §5 is a whole section about reaching a born service by voice —
but the real answer there is a reflexi pattern overlay loaded at runtime, which
is 5c. Proposal: the manifest carries `[phrases]` and 5a **validates but does
not use it**, so the field is never invented twice, and "show me the clock" is
5c's problem.

## Per repo

### cogiti     [order 1 — owns the manifest and the supervisor]
files:  `service/` (new package: the SDK), `services.py` (new: manifest,
        supervisor, install, remove), `providers/` or job kinds for
        `list_services`, `service_status`, `pause_service`, `remove_service`,
        `docs/services.md` (proposal → specification for the 5a half)
change: parse and validate a manifest; start at boot in manifest order after
        the adapters; restart with 1/2/4…60 s backoff; **three failures inside
        a minute stops it** and marks `needs-attention`; SIGTERM then SIGKILL
        to the process group after 5 s; removal that moves the directory to
        `removed/<name>-<timestamp>/` and takes the patterns, egress entries
        and secret grants with it.
proves it: a service that crashes on a loop is stopped and reported rather
        than restarted forever; removal leaves nothing behind; a renderer
        restart leaves the panel pinned, which is the bug avatari_feed.py
        exists to prevent.

### reflexi    [order 2]
files:  `intents/list_services.yaml`, `service_status.yaml`,
        `pause_service.yaml`, `remove_service.yaml`
change: four intents. `remove_service` is `confirm` for the same reason
        `cancel_job` is: removal is a voice command, voice commands are
        misheard, and §7 keeps thirty days of undo precisely because of it.
proves it: `make test`, fixtures regenerated, negative cases.

### inteliboy  [order 3]
files:  `services/clock/`, `services/weather/`, table entries, distro packaging
change: the two hand-written services, shipped through the same path an agent
        will use.
proves it: they survive a reboot on hardware.

## Not in this change

- **5b, the authoring pipeline.** No agent writes a service here. This stage
  exists to make 5b reviewable.
- **5c, routing by voice.** `[phrases]` is validated and unused.
- **The CPU rate limit.** See question 3.
- **Per-service uids**, unless question 2 says otherwise.

## Failure modes

1. **The panel that vanished at a renderer restart.** The one bug
   `avatari_feed.py` was written about. Re-declare on connect, always.
2. **The crash loop nobody hears about.** §6: worse than a service that is off.
3. **The credential that outlived its service.** §7.3 — a revoked grant that
   survives removal is a credential belonging to nothing.
4. **The service that starts before the renderer.** Manifest order is not
   dependency order; the SDK reconnects, so this must be survivable rather
   than sequenced.
5. **The manifest that stopped being the truth.** §2: cogiti holds nothing
   about a service that is not derivable from its directory. The moment there
   is a second place, `rm -rf` stops working and restart stops being safe.

## Rollback

Branch `stage-5a-services` in cogiti and reflexi; delete both. No image is
built from this until it works, so `versions.lock` stays at InteliBoy 0.1.0.


## What landed

cogiti 0.5.0, reflexi 0.4.0, two services here. On the appliance:

- both start at boot, both connect to the renderer, and `services: clock,
  weather` appears in the log;
- the broker **refuses the clock the exact URL it grants the weather**, the
  only difference being one line of manifest — which is the allow-list being
  enforcement rather than documentation;
- a renderer restart is noticed within a second by both, and both re-declare.

Three bugs, none of which the tests could have found:

1. **The SDK was not importable by a service.** cogiti's launcher puts itself
   on `sys.path`, not in `PYTHONPATH`, so a child inherited nothing. Both
   services died on their first line, three times each, and were stopped by
   the crash-loop rule — working perfectly, and saying nothing about why.
2. **Because their stderr was a pipe nobody read.** §9's failure mode wearing
   a hat: the supervisor captured the reason and showed no one.
3. **The SDK had no keepalive.** A socket's death is discovered on a write, so
   the weather — which writes every fifteen minutes — did not reconnect at
   all after a renderer restart, while the clock came back in ten seconds.
   This is the exact bug `avatari_feed.py` was written about, reimplemented
   by someone who had read the file.

## Still open in 5a

- **The services are not in an image.** They live in `/var/lib/cogiti/services`
  on the device, deployed by hand; the distro does not package them yet.
- **The shared `cogiti-service` uid is not created.** Services run as root, so
  the isolation decided in question 2 is not yet real.
- **`approved` and `source_sha` are parsed and unenforced.** They belong to
  5b's review gate, which is what 5a exists to make possible.
