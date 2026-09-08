#!/bin/bash
# Look inside the built image for the things tonight was about. A build that
# succeeded is not evidence that it contains what you think.
set -e
IMG=${1:?usage: verify-image.sh <image.img>}
LOOP=$(sudo losetup -f); MNT=$(mktemp -d)
cleanup() { sudo umount "$MNT" 2>/dev/null || true
            sudo losetup -d "$LOOP" 2>/dev/null || true
            rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT
sudo losetup -P "$LOOP" "$IMG"
sudo mount -o ro "${LOOP}p2" "$MNT"

ok=0; bad=0
have() {  # have <description> <file> <pattern>
    if sudo grep -q -- "$3" "$MNT$2" 2>/dev/null; then
        printf '  ok    %s\n' "$1"; ok=$((ok+1))
    else
        printf '  MISS  %s   (%s)\n' "$1" "$2"; bad=$((bad+1))
    fi
}
echo "== identity"
sudo grep -E "^(PRETTY_NAME|VERSION)=" "$MNT/etc/os-release" | sed 's/^/  /'

echo "== tonight's fixes, in the image"
have "speaks through the adapter that hears" /usr/lib/cogiti/cogiti/main.py "_marks_for"
have "half-duplex muting"                    /usr/lib/cogiti/cogiti/main.py "half_duplex"
have "answers expire"                        /usr/lib/cogiti/cogiti/main.py "_arm_expiry"
have "linger in the command table"           /etc/cogiti/commands.toml "^linger"
have "reader does not block on a turn"       /usr/lib/cogiti/cogiti/adapters/audi.py "_turn_finished"
have "an empty final starts no turn"         /usr/lib/cogiti/cogiti/session.py "genuinely empty"
have "config paths relative to the file"     /usr/lib/cogiti/cogiti/config.py "def resolve"
have "init: own process group"               /etc/rc.d/init.d/cogiti "setsid"
have "init: unconditional stop"              /etc/rc.d/init.d/cogiti "stack_pids"
have "device knows its own ip"               /usr/lib/cogiti/cogiti/providers/device.py "device.ip"
have "get_ip in the table"                   /etc/cogiti/commands.toml "get_ip"
have "hearing_check in the table"            /etc/cogiti/commands.toml "hearing_check"
have "azure recogniser present"              /usr/bin/inteliboy-hear "azure"
have "jobs outlive their turn"               /usr/lib/cogiti/cogiti/detach.py "DETACH_AFTER_S"
have "the service supervisor"                /usr/lib/cogiti/cogiti/services.py "CRASH_LIMIT"
have "the egress broker"                     /usr/lib/cogiti/cogiti/broker.py "allow-list"
have "the service SDK"                       /usr/lib/cogiti/cogiti/service/__init__.py "class Service"
have "the authoring pipeline"                /usr/lib/cogiti/cogiti/authoring.py "REQUIRED_UPDATES"
have "static checks on generated code"       /usr/lib/cogiti/cogiti/static_checks.py "ALLOWED_IMPORTS"
have "approval binds code and manifest"      /usr/lib/cogiti/cogiti/approval.py "manifest_sha"
have "device readings a service may ask for" /usr/lib/cogiti/cogiti/readings.py "READINGS"
have "routing to a born service"             /usr/lib/cogiti/cogiti/phrases.py "def match"
have "pin_thing in the table"                /etc/cogiti/commands.toml "pin_thing"

# The account is created at boot rather than by a package — see the init
# script for why — so what is checked here is that the boot will do it.
have "the service account is created at boot" /etc/rc.d/init.d/cogiti "cogiti-service"
have "the undo bin is bounded"               /usr/lib/cogiti/cogiti/services.py "KEEP_REMOVED_DAYS"
have "a question is not interrupted by it"   /usr/lib/cogiti/cogiti/session.py "awaiting_answer"

echo "== the brain can see the screen"
if sudo grep -q "screenshot" "$MNT/usr/bin/avatari" 2>/dev/null; then
    printf '  ok    the renderer answers screenshot\n'; ok=$((ok+1))
else
    printf '  MISS  no screenshot op in the renderer\n'; bad=$((bad+1))
fi

echo "== no services shipped (they are born on request now)"
n=$(sudo ls "$MNT/var/lib/cogiti/services" 2>/dev/null | wc -l)
printf '  %s    %s service(s) pre-installed\n' \
    "$([ "$n" = 0 ] && echo ok || echo MISS)" "$n"
[ "$n" = 0 ] && ok=$((ok+1)) || bad=$((bad+1))

echo "== the echo canceller"
if sudo test -e "$MNT/usr/lib/libspeexdsp.so.1"; then
    printf '  ok    libspeexdsp.so.1\n'; ok=$((ok+1))
else
    printf '  MISS  libspeexdsp.so.1\n'; bad=$((bad+1))
fi

echo "== what the lfs12.4-blfs12.4 channel added"
# Both were unresolved on the first build of this channel, and the first one
# is the face: Mesa 25.1.8 links SPIRV-Tools, so libEGL does, so avatari does.
# An image without it assembles, passes every other check, and boots to a
# black screen.
for lib in libSPIRV-Tools.so libglib-2.0.so.0; do
    if sudo test -e "$MNT/usr/lib/$lib"; then
        printf '  ok    %s\n' "$lib"; ok=$((ok+1))
    else
        printf '  MISS  %s\n' "$lib"; bad=$((bad+1))
    fi
done
# fc-cache is what failed out loud when glib was absent, so its output is the
# evidence that it ran rather than that it merely exists.
n=$(sudo ls "$MNT/var/cache/fontconfig" 2>/dev/null | wc -l)
printf '  %s    font cache built (%s entries)\n' \
    "$([ "$n" -gt 0 ] && echo ok || echo MISS)" "$n"
[ "$n" -gt 0 ] && ok=$((ok+1)) || bad=$((bad+1))

echo "== the screen is part of the conversation"
have "what is on screen keeps the turn open" /usr/lib/cogiti/cogiti/session.py "mid_conversation"
have "the presenter knows what it left up"   /usr/lib/cogiti/cogiti/present.py "def on_screen"

echo "== it can reach its own channel"
# distro.conf had no REPO_URL until 0.17.0, so build-distro.sh wrote a
# commented-out stub and every image before this one booted unable to sync or
# upgrade. Invisible until a device was flashed fresh, because the appliance in
# use had been given the line by hand.
if sudo grep -q '^REPO_URL=' "$MNT/etc/lpkg/lpkg.conf" 2>/dev/null; then
    printf '  ok    %s\n' "$(sudo grep -m1 '^REPO_URL=' "$MNT/etc/lpkg/lpkg.conf")"
    ok=$((ok+1))
else
    printf '  MISS  /etc/lpkg/lpkg.conf has no REPO_URL - this image cannot upgrade\n'
    bad=$((bad+1))
fi

echo "== the face boots asleep"
# Only the first start of the boot: cogiti sends one wake when it begins
# serving, so a renderer restarted later must come back awake or nothing would
# ever open its eyes.
have "avatari is started with --asleep" /etc/rc.d/init.d/avatari "asleep=--asleep"
have "and a restart comes back awake"   /etc/rc.d/init.d/avatari "AVATARI\" \$asleep"

echo "== it can offer its own updates"
# lpkg 11 is the first with a transaction lock. Before it, two upgrades at
# once interleaved over the same files and the loser rebuilt its owners index
# from a half-written database — and the appliance is about to start running
# upgrades on its own, unattended.
v=$(sudo grep -m1 '^VERSION=' "$MNT/usr/bin/lpkg" 2>/dev/null | cut -d= -f2)
if [ "${v:-0}" -ge 11 ] 2>/dev/null && sudo grep -q 'flock' "$MNT/usr/bin/lpkg"; then
    printf '  ok    lpkg %s, with the transaction lock\n' "$v"; ok=$((ok+1))
else
    printf '  MISS  lpkg %s has no flock — unattended upgrades would race\n' "${v:-?}"
    bad=$((bad+1))
fi
have "the hourly check"                /etc/cogiti/commands.toml "every_s"
have "the spoken update, asking first" /etc/cogiti/commands.toml "Shall I install"
if sudo test -x "$MNT/usr/libexec/inteliboy/upgrade.sh"; then
    printf '  ok    upgrade.sh, which leaves the brain until last\n'; ok=$((ok+1))
else
    printf '  MISS  upgrade.sh\n'; bad=$((bad+1))
fi

echo "== the credentials it was seeded with"
# Names and modes only - never the contents. A missing one is silent until
# the device is in front of someone: cogiti starts, listens, and has nothing
# to escalate to.
for name in anthropic.api_key azure.speech_key azure.speech_region; do
    f="$MNT/var/lib/cogiti/secrets/$name"
    if sudo test -s "$f" && [ "$(sudo stat -c %a "$f")" = 600 ]; then
        printf '  ok    %-22s %s bytes, mode 600\n' "$name" "$(sudo stat -c %s "$f")"
        ok=$((ok+1))
    else
        printf '  MISS  %-22s (seed with: make seed-image SECRETS=%s)\n' "$name" "$name"
        bad=$((bad+1))
    fi
done

echo "== the blob reflexi will actually load"
sudo ls -l "$MNT/usr/share/reflexi/reflexi.blob" | sed 's/^/  /'
printf '\n  %d ok, %d missing\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
