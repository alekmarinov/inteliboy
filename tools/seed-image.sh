#!/bin/bash
# Write secrets into the image, in place.
#
#   tools/seed-image.sh <image.img> <secret-name> [more names...]
#
# One image, and it carries its credentials. That is a decision, not an
# oversight: a second `-provisioned` copy meant seven gigabytes of duplicate
# and one more thing to pick the wrong one of.
#
# ------------------------------------------------------------------------
# So: THE BUILT IMAGE IS A SECRET. Treat build/ as you would a private key.
#
# A credential inside an image is a credential in every copy of that image, on
# every device flashed from it, in every backup of the build directory, and in
# whatever anyone tars up to send somewhere. Revoking it means reflashing every
# device rather than deleting one file. That is the same failure this project
# has already fixed twice: ssh host keys shared by every image, and a root
# password hash riding inside four packages.
#
# It is also our key rather than the owner's, which does not survive contact
# with a second user — see changes/2026-09-01-user-owned-credentials/brief.md,
# which is the plan for undoing all of this.
#
# `tools/push.sh` and an ssh key in the distro overlay mean a booted device can
# be given its credentials in a second, with them never touching a build
# artifact. That remains the better way whenever the device can be reached.
#
# One image seeded here should go to one device. If it goes to several, they
# share a credential and you have chosen the thing the paragraph above
# describes.
# ------------------------------------------------------------------------
set -e

IMG=${1:?usage: seed-image.sh <image.img> <secret-name> [more...]}
shift
[ $# -gt 0 ] || { echo "name at least one secret to install"; exit 1; }

STORE=${COGITI_SECRETS:-$HOME/.local/state/cogiti/secrets}
STATE_DIR=${COGITI_STATE_DIR:-/var/lib/cogiti}
OUT="$IMG"

[ -f "$IMG" ] || { echo "no such image: $IMG"; exit 1; }
for name in "$@"; do
    [ -f "$STORE/$name" ] || { echo "no such secret: $STORE/$name"; exit 1; }
    mode=$(stat -c %a "$STORE/$name")
    [ "$mode" = 600 ] || { echo "$STORE/$name is mode $mode, expected 600"; exit 1; }
done

LOOP=$(sudo losetup -f)
MNT=$(mktemp -d)
cleanup() { sudo umount "$MNT" 2>/dev/null || true
            sudo losetup -d "$LOOP" 2>/dev/null || true
            rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

sudo losetup -P "$LOOP" "$OUT"
sudo mount "${LOOP}p2" "$MNT"

DEST="$MNT$STATE_DIR/secrets"
sudo install -d -m 700 "$DEST"
for name in "$@"; do
    # install rather than cp: the mode is set as the file is created, so it is
    # never briefly world-readable inside the image.
    sudo install -m 600 "$STORE/$name" "$DEST/$name"
    echo "  installed $STATE_DIR/secrets/$name"
done
sync

echo
echo "$(basename "$OUT") carries $# secret(s)."
echo "It is now a secret itself. Flash it to one device; every device flashed"
echo "from it shares them, and revoking means reflashing rather than deleting"
echo "a file."
