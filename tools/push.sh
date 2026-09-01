#!/bin/bash
# Put a freshly built component onto a running appliance, without an image.
#
#   tools/push.sh <host> <package.tar.gz> [init-script-name]
#
# The loop this replaces is: make distro, make image, write three gigabytes,
# reflash, reboot. This is about a minute, and the appliance keeps running.
#
# What it will not do is push a package wholesale. A built package carries more
# than the component:
#
#   /etc/<name>.conf   the distro's files/ overlay owns this. Pushing the
#                      package's copy silently replaces the appliance's
#                      configuration with the build default.
#   .meta/             build bookkeeping - which files this package created and
#                      which it modified. Not for a device.
#   /tmp/<name>.log    the build log, which the package picked up because /tmp
#                      was inside the overlay.
#
# So it pushes usr/ and nothing else, and says what it skipped. A push that
# quietly rewrote /etc would be discovered days later, on the one device where
# the config mattered.
set -e

HOST=${1:?usage: push.sh <host> <package.tar.gz> [service]}
PKG=${2:?usage: push.sh <host> <package.tar.gz> [service]}
SERVICE=${3:-}
KEY=${SSH_KEY:-$HOME/.ssh/alek_github_id_rsa}
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR -o ConnectTimeout=10"

sshq() { ssh $SSH_OPTS -i "$KEY" "$HOST" "$@"; }

[ -f "$PKG" ] || { echo "no such package: $PKG"; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# --------------------------------------------------------------- select --
tar tzf "$PKG" | grep -v '/$' | sed 's|^\./||' > "$WORK/all"
grep '^usr/' "$WORK/all" > "$WORK/send" || true
grep -v '^usr/' "$WORK/all" > "$WORK/skip" || true

if [ ! -s "$WORK/send" ]; then
    echo "$PKG installs nothing under usr/; nothing to push"
    exit 1
fi

echo "pushing $(wc -l < "$WORK/send") file(s) from $(basename "$PKG") to $HOST"
if [ -s "$WORK/skip" ]; then
    sed 's|^|  skipping /|' "$WORK/skip"
fi

# ------------------------------------------------------------------ new --
# Say which files the device does not have yet. A new data file that a new
# binary needs is the failure this catches: pushing only the binary leaves a
# renderer that starts and then cannot load a shader.
sshq 'while read -r f; do [ -e "/$f" ] || echo "  new: /$f"; done' < "$WORK/send" || true

# ----------------------------------------------------------------- stop --
if [ -n "$SERVICE" ]; then
    sshq "[ -x /etc/rc.d/init.d/$SERVICE ] && /etc/rc.d/init.d/$SERVICE stop || true" \
        | sed 's/^/  /'
fi

# ----------------------------------------------------------------- send --
tar xzf "$PKG" -C "$WORK" ./usr
# --warning=no-timestamp: an appliance with no RTC is often behind the build
# host, and every file then looks like it is from the future. Worth silencing
# rather than reading fourteen identical warnings; worth knowing about, which
# is what the clock check below is for.
tar czf - -C "$WORK" usr \
    | sshq "tar xzf - -C / --warning=no-timestamp && echo '  sent'"

# ---------------------------------------------------------------- start --
STARTED=no
if [ -n "$SERVICE" ]; then
    if sshq 'grep -qw inteliboy.norender /proc/cmdline'; then
        echo "  NOT started: this device booted the rescue entry, so its init"
        echo "  script declines to start the renderer. That is correct. Reboot"
        echo "  into the default entry, or run /usr/bin/$SERVICE by hand."
    else
        sshq "/etc/rc.d/init.d/$SERVICE start" | sed 's/^/  /'
        STARTED=yes
        sleep 4
    fi
fi

# --------------------------------------------------------------- verify --
# A push is not finished when scp exits 0. It is finished when the thing on the
# device reports the version that was built and is running.
# Reading --version off the file proves the file arrived. It says nothing about
# what is running: a process started before the push keeps executing the old
# inode, and Linux is happy to let the file be replaced underneath it. That
# combination once reported the new version and a live pid, and both were true
# while the device was running the old binary. So the running process is asked
# what it is executing, and a deleted inode is a failure, not a footnote.
echo "on the device now:"
# Captured rather than piped: `sshq ... | sed` returns sed's status, so the
# remote exit 3 below was reported in words and swallowed in the exit code —
# a push that announced its own failure and then succeeded.
status=0
out=$(sshq "
  b=/usr/bin/${SERVICE:-}
  [ -x \"\$b\" ] && echo \"  on disk: \$(\$b --version 2>&1)\"
  echo \"  clock:   \$(date -u '+%H:%M:%S') UTC\"
  p=\$(pgrep -x '${SERVICE:-nothing}' 2>/dev/null || true)
  if [ -z \"\$p\" ]; then
      echo '  process: not running'
  else
      exe=\$(readlink /proc/\$p/exe)
      case \"\$exe\" in
        *'(deleted)')
          echo \"  process: pid \$p is running a DELETED binary — the push replaced\"
          echo '           the file underneath it. Until it restarts, what is on'
          echo '           screen is still the old build.'
          # Only a failure if a restart was attempted. On a device that
          # declined to start the service — the rescue entry — the push itself
          # is fine and the restart is the operator's to do, so saying so is
          # right and failing is not.
          [ '$STARTED' = yes ] && exit 3 || exit 0 ;;
        *) echo \"  process: pid \$p, running \$exe\" ;;
      esac
  fi
") || status=$?
printf '%s\n' "$out" | sed 's/^/ /'
echo "  host clock: $(date -u '+%H:%M:%S') UTC"
exit $status
