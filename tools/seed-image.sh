#!/bin/bash
# Write secrets into a copy of an image, for a device that cannot be reached
# after it boots.
#
#   tools/seed-image.sh <image.img> <secret-name> [more names...]
#
# It never modifies the image you built. It writes `<image>-provisioned.img`,
# and that name is the safety mechanism: an image carrying a credential must
# not be confusable with the one you hand to somebody, copy to a USB stick, or
# keep as a release artifact. `build/*-provisioned.img` is gitignored.
#
# ------------------------------------------------------------------------
# Prefer provisioning after boot. This exists for when you cannot.
#
# A credential inside an image is a credential in every copy of that image, on
# every device flashed from it, in every backup of the build directory, and in
# whatever anyone tars up to send somewhere. Revoking it means reflashing every
# device rather than deleting one file. That is the same failure this project
# has already fixed twice: ssh host keys shared by every image, and a root
# password hash riding inside four packages.
#
# `tools/push.sh` and an ssh key in the distro overlay mean a booted device can
# be provisioned in a second, with the credential never touching a build
# artifact. Reach for this only when the device has no network on first boot,
# or when flashing many at once makes logging into each one impractical.
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
OUT="${IMG%.img}-provisioned.img"

[ -f "$IMG" ] || { echo "no such image: $IMG"; exit 1; }
for name in "$@"; do
    [ -f "$STORE/$name" ] || { echo "no such secret: $STORE/$name"; exit 1; }
    mode=$(stat -c %a "$STORE/$name")
    [ "$mode" = 600 ] || { echo "$STORE/$name is mode $mode, expected 600"; exit 1; }
done

echo "copying $(basename "$IMG") -> $(basename "$OUT")"
cp --reflink=auto "$IMG" "$OUT"

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
echo "Flash it to one device. Every device flashed from it shares them, and"
echo "revoking means reflashing rather than deleting a file."
