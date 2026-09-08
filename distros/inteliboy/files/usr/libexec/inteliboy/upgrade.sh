#!/bin/sh
# Install available updates, leaving the brain until last.
#
# Run as a cogiti `run` job, which means: detached, in its own process group,
# one at a time, and nobody waiting on it. Its stdout is what the job reports.
#
# ---------------------------------------------------------------------------
# Why this is a script and not a line in commands.toml
#
# Three things have to happen in an order, and two of them are refusals:
#
#   1. Never a bare `lpkg upgrade`. It collects every upgradable package,
#      including core ones — and cmd_install refuses a core package on a
#      running system, failing the *whole* transaction and installing nothing.
#      One glibc in the channel would turn every update into a silent no-op.
#      It would also take the kernel: a new vmlinuz lands while grub.cfg still
#      names the old one, the old one is never removed, and modules may be
#      replaced under the running kernel. Invisible until the next boot.
#
#   2. cogiti last, and alone. lpkg replaces files under a running program:
#      what is already open keeps its inode and survives, but everything
#      opened afterwards is the new version, so a long-lived cogiti ends up
#      half of each. Worse, this script is cogiti's child — if cogiti restarts
#      while its own upgrade is in flight, the child is orphaned and goes on
#      rewriting files beneath the process that replaced it.
#
#   3. So the announcement has to happen while there is still a cogiti to make
#      it. Everything else is upgraded first and this script exits; cogiti says
#      "that's done"; only then does the detached tail below replace cogiti and
#      restart it. The restart is the last thing that happens, to nobody.
#
# There is no rollback. lpkg writes a journal and nothing reads it, so a failed
# upgrade leaves whatever it managed and says so — which is the honest report
# rather than a promise this cannot keep.
set -e

LOG=/var/log/lpkg-upgrade.log
SELF=cogiti

exec 2>>"$LOG"
echo "--- upgrade $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$LOG"

# What the channel is offering, minus ourselves. `--no-sync` because the duty
# that prompted this synced within the hour, and because sync writes prose to
# stdout that would land in the middle of the list.
others=$(lpkg list --upgradable --no-sync 2>/dev/null | awk -v me="$SELF" '$1 != me { print $1 }')

if [ -n "$others" ]; then
    # shellcheck disable=SC2086 — deliberate word splitting: a package list.
    lpkg upgrade --yes $others >>"$LOG" 2>&1
    echo "upgraded: $(echo $others | tr '\n' ' ')"
else
    echo "nothing but myself to upgrade"
fi

# Ourselves, after this script has exited and the announcement has been made.
# setsid so the restart cannot kill the upgrade that causes it: without its own
# session this is cogiti's child, and cogiti is about to stop.
if lpkg list --upgradable --no-sync 2>/dev/null | awk '{print $1}' | grep -qx "$SELF"; then
    echo "and myself, in a moment"
    setsid /bin/sh -c '
        sleep 20
        lpkg upgrade --yes cogiti >>'"$LOG"' 2>&1
        /etc/rc.d/init.d/cogiti restart >>'"$LOG"' 2>&1
    ' >/dev/null 2>&1 </dev/null &
fi
