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

echo "== the account a service runs as"
if sudo grep -q "^cogiti-service:" "$MNT/etc/passwd" 2>/dev/null; then
    printf '  ok    cogiti-service exists: %s\n' \
        "$(sudo grep '^cogiti-service:' "$MNT/etc/passwd")"
    ok=$((ok+1))
else
    printf '  MISS  no cogiti-service account; services would run as root\n'
    bad=$((bad+1))
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

echo "== the blob reflexi will actually load"
sudo ls -l "$MNT/usr/share/reflexi/reflexi.blob" | sed 's/^/  /'
printf '\n  %d ok, %d missing\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
