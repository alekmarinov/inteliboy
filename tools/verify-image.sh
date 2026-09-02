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

echo "== the blob reflexi will actually load"
sudo ls -l "$MNT/usr/share/reflexi/reflexi.blob" | sed 's/^/  /'
printf '\n  %d ok, %d missing\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
