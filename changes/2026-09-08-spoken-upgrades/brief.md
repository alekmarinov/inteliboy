# 2026-09-08-spoken-upgrades — the device offers its own updates

Status: approved
Approved by: Alexander Marinov, 2026-09-08

## The ask

The appliance should notice when its own software has updates waiting, put a
short notice on the screen rather than interrupting, and upgrade itself when
asked to out loud — confirming first what will change, and saying when it is
finished. The finishing announcement is to use the general background-job
machinery, not a mechanism invented for this.

## The seam

No contract changes. Every piece is additive inside an existing one.

    contract: command table + job kinds
    owner:    cogiti
    consumers: this repository's commands.toml
    additive: yes — one new job kind, one new timer field, one new
              output intent. No version bump; no consumer but us.

The `lpkg` argv appears **only** in this repository. cogiti CLAUDE.md §11:
"if a proposal names a specific product, device or renderer, it is in the
wrong repository". `providers/shell.py` is the declared seam.

## Shared vocabulary

    update            the reflexi intent id (not `upgrade`, not `software_update`)
    upgrade           the cogiti job kind
    notice            show-only announcement, pinned to the periphery
    repeat_s          timer field: fire every N seconds instead of once

## Positions

**reflexi** would refuse `verdict: handle` for this intent. "Destructive
intents never resolve on a similarity score… A 0.73 cosine must not turn off
the device" (CLAUDE.md:35-36). An unattended software update that can reboot
the appliance is in that family, and the loader rejects `destructive: true`
with `handle` anyway. It also refuses fixing any resulting false accept by
raising `accept` in thresholds.toml — the right fix is a reject exemplar.
It warns that "update" collides head-on with `set_location`'s "update my
location to {location}", and that `reboot` already owns "restart the system":
without negatives in the same change we would silently steal set_location
traffic.

**cogiti** would refuse four things: auto-answering the confirm ("a `confirm`
is never auto-answered by cogiti, by a timeout, or by an agent"); naming a
package manager anywhere in its own source; blocking the loop on the upgrade
("cogiti never blocks"); and making the announcement a model sentence
("templates, never model output"). It observes that a provider cannot do the
long half at all — 250 ms default timeout, `shell.run` capped at 5 s — so this
must be a job. It prefers a generic recurring timer over a bespoke updates
poller, so that "N updates ready" and "that's done" are one mechanism used
twice, and says plainly: resist a seventh port, resist a new service. Services
own the periphery, not the mouth — and a service cannot speak at all
(`broker.py:96-102` stores `value` and never forwards it).

**lfs** reports that lpkg has no self-replacement check of any kind, no lock of
any kind, and no rollback: the journal is written and never read. It would
propose exactly one lfs change — a `flock` under /var/lib/lpkg — because
cogiti can serialize itself but cannot serialize against an administrator at
an ssh prompt. Not taken in this change.

## Per repo

### reflexi   [order 1]
files:  intents/update.yaml, eval/core.yaml, eval/negatives.yaml,
        eval/destructive.yaml, tests/fixtures/{tokens,normalize}.txt
change: one intent, `verdict: confirm`, `destructive: true`, thresholds to
        match reboot.yaml (0.80/0.15). Negatives for "update my location".
proves it: `make report` before (crowding), then
        `make blob && make fixtures && make test && make eval` — eval exits
        non-zero on any regression; both numbers go in the commit message.

### cogiti    [order 2]
files:  src/cogiti/timers.py, src/cogiti/table.py, src/cogiti/main.py,
        src/cogiti/present.py, tests/
change: (a) `repeat_s` on a timer, so a duty can recur; (b) job kind
        `upgrade`, added to `Command.JOBS` and the `start_job` dispatch,
        capped at one in flight in `_check_caps` — lpkg has no lock, so the
        cap is the only serialization there is; (c) `notice`, the show-only
        sibling of `announce`, pinned to PERIPHERY, which already means
        "conversation never shoves it aside".
proves it: `make test`.

### inteliboy [order 3]
files:  distros/inteliboy/files/etc/cogiti/commands.toml
change: the `update` command, its confirm wording, the recurring check, and
        the argv — `lpkg sync` then `lpkg list --upgradable --no-sync`,
        parsed as `$1 $2 $4`; the upgrade names packages explicitly.
proves it: on the device, and by verify-image.

## Not in this change

- **A bare `lpkg upgrade`.** One core package in the channel makes lpkg refuse
  the whole transaction and install nothing; the kernel would come along
  uninvited while grub.cfg still names the old vmlinuz. The set is explicit.
- **Upgrading cogiti in the same transaction as everything else.** cogiti is
  a `system`-class package and lpkg will replace it under the running process:
  already-open files survive on their old inode, everything opened afterwards
  is the new version, and a restart mid-transaction orphans the lpkg child.
  So: everything else first, announce, then cogiti and a restart.
- **A flock in lpkg.** The only part that could not live here. An lfs brief.
- **Judging whether it is a good moment to speak.** `announce` speaks over
  whatever is happening and says so at main.py:728. Screen-first sidesteps it.
- **Reading the journal / rolling back a failed upgrade.** Nothing reads it
  today; that is lpkg's to fix if it ever should be.

## Left to fix, bundled with the next change

**The duty tasks are not cancelled at shutdown.** `run_duties` spawns one
`asyncio.ensure_future(self._duty(...))` per duty and keeps no handle, so
stopping cogiti prints

    Task was destroyed but it is pending!
    task: <Task pending coro=<Cogiti._duty() running at main.py:560>>

Seen on 192.168.1.117 after `lpkg upgrade` restarted the brain. Harmless — the
process is already exiting — but a duty mid-check dies without tidying up, and
the timers next door already do this properly: keep the handles, cancel them in
the `finally` that closes the loop. A second one joins it, seen on the same
restart — `FaceOutput._arm_expiry.<locals>.countdown`, the task that takes a
card off the screen after its linger. Same shape, same fix, same place. Deferred deliberately rather than
forgotten; the user asked for it bundled rather than shipped on its own.

## Rollback

Each half is independently revertable: the intent by deleting one yaml and
rebuilding the blob, cogiti by reverting three small additions, the commands
by editing the table. Nothing here changes an existing shape, so nothing else
has to move back with it.
