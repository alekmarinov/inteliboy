#!/bin/bash
# Builds every component that ships source into the image, and puts its
# tarballs where the distro's recipes look for them.
#
#   tools/stage.sh [<distro directory>]
#
# This is the step that used to be a manual 'make dist', a manual copy and a
# hand-edited checksum file. x-make-avatari.sh has claimed since it was written
# that the tarballs are produced "by 'make avatari-sources', which runs
# avatari's own 'make dist' and copies the tarballs here" - and no such target
# existed anywhere. Two consequences of it being manual are already recorded:
# the checksums in local.md5sums named tarballs that no longer existed, and the
# package cache held a build of the renderer nobody had chosen.
#
# It belongs here rather than in lfs because knowing what InteliBoy is made of
# is this repository's job. lfs is handed a directory; it does not know that
# avatari has a git tag.
set -e

BASE_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )
cd "$BASE_DIR"

DISTRO_DIR=${1:-$BASE_DIR/distros/inteliboy}
SOURCES="$DISTRO_DIR/sources"
[ -d "$SOURCES" ] || { echo "No sources directory at $SOURCES"; exit 1; }

# Components whose source is built into the image. reflexi and cogiti are not
# here yet: reflexi has no dist target and cogiti has no code. When they gain
# one, they are added here and nowhere else.
COMPONENTS="avatari"

for c in $COMPONENTS; do
    repo="$BASE_DIR/../$c"
    [ -d "$repo" ] || { echo "$c: no repository at $repo"; exit 1; }

    ver=$(make -s -C "$repo" version)
    [ -n "$ver" ] || { echo "$c: 'make version' said nothing"; exit 1; }
    case "$ver" in
        *-dirty) echo "$c $ver  (uncommitted changes - the version says so on purpose)" ;;
        *)       echo "$c $ver" ;;
    esac

    make -s -C "$repo" dist
    make -s -C "$repo" dist-assets

    # Every tarball this component produced for this version. The glob is
    # anchored on the version rather than on the name, so an older tarball
    # left in the component's tree from a previous build is not picked up.
    found=0
    for t in "$repo"/*-"$ver".tar.xz; do
        [ -e "$t" ] || continue
        cp -f "$t" "$SOURCES/"
        echo "  staged $(basename "$t")"
        found=$((found + 1))
    done
    [ "$found" -gt 0 ] || { echo "$c: 'make dist' produced no tarball for $ver"; exit 1; }
done

# Anything for another version is stale: the recipes glob '<name>-[0-9]*' and
# would be handed two archives and extract from the wrong one.
for t in "$SOURCES"/*.tar.xz; do
    [ -e "$t" ] || continue
    keep=no
    for c in $COMPONENTS; do
        ver=$(make -s -C "$BASE_DIR/../$c" version)
        case "$(basename "$t")" in *-"$ver".tar.xz) keep=yes ;; esac
    done
    if [ "$keep" = no ]; then
        echo "  removing stale $(basename "$t")"
        rm -f "$t"
    fi
done

# The checksums are rewritten rather than edited. They exist to catch a
# truncated copy, not to make a supply chain claim about our own code - these
# tarballs have no upstream url, which is why they are here and not in one of
# the wget lists.
( cd "$SOURCES" && md5sum *.tar.xz > local.md5sums )
echo
echo "$SOURCES/local.md5sums:"
sed 's/^/    /' "$SOURCES/local.md5sums"
