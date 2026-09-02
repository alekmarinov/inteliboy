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

# Components whose source is built into the image. Each must answer `make
# version`, `make dist` and `make dist-assets`; a component with nothing to
# ship beyond its source answers the last one with true.
#
# audi's assets are the large ones and they are not its source: the speech
# models, and the Python wheels its dependencies come as. They are fetched for
# the *appliance's* Python rather than this workstation's — see
# docs/python-on-the-appliance.md, which is the trap that costs a day.
COMPONENTS="avatari reflexi cogiti audi"

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
    # Copied only when the content differs. The dist targets build
    # reproducibly — --sort=name --mtime=@0 --numeric-owner — so an unchanged
    # component produces a byte-identical tarball, and copying it anyway would
    # move its mtime and force a rebuild of a package that has not changed.
    #
    # That is not a micro-optimisation. The distro build decides what to
    # rebuild by comparing each recipe against its staged sources, so a
    # gratuitous copy of the 167 MB voice pack is a full reinstall of it.
    found=0
    for t in "$repo"/*-"$ver".tar.xz; do
        [ -e "$t" ] || continue
        name=$(basename "$t")
        if [ -e "$SOURCES/$name" ] && cmp -s "$t" "$SOURCES/$name"; then
            echo "  unchanged $name"
        else
            cp -f "$t" "$SOURCES/"
            echo "  staged $name"
        fi
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
# This repository's own adapters, which are not a component with a version of
# its own. They are the deployment's answer to "which model, which voice" — the
# one thing cogiti refuses to have an opinion about — so they ship from here.
#
# The wheels are fetched for the appliance's Python, never this one's. Only
# `anthropic` and its dependencies: audi brings its own, and duplicating them
# would put two copies of numpy in the image.
ADAPTERS_VER=$(git -C "$BASE_DIR" describe --tags --always --dirty 2>/dev/null || echo 0.0.0)
echo "inteliboy-adapters $ADAPTERS_VER"
rm -rf "$BASE_DIR/build/adapters"
mkdir -p "$BASE_DIR/build/adapters/inteliboy-adapters-$ADAPTERS_VER/wheels"
cp -r "$BASE_DIR/adapters" \
      "$BASE_DIR/build/adapters/inteliboy-adapters-$ADAPTERS_VER/adapters"
rm -rf "$BASE_DIR/build/adapters/inteliboy-adapters-$ADAPTERS_VER/adapters/anthropic/.venv"
pip download -q --only-binary=:all: --python-version 3.13 --implementation cp \
    --abi cp313 --abi none --platform any --platform manylinux2014_x86_64 \
    --platform manylinux_2_17_x86_64 anthropic \
    -d "$BASE_DIR/build/adapters/inteliboy-adapters-$ADAPTERS_VER/wheels"
tar cJf "$SOURCES/inteliboy-adapters-$ADAPTERS_VER.tar.xz" \
    -C "$BASE_DIR/build/adapters" --owner=0 --group=0 --numeric-owner \
    --sort=name --mtime=@0 "inteliboy-adapters-$ADAPTERS_VER"
rm -rf "$BASE_DIR/build/adapters"
echo "  staged inteliboy-adapters-$ADAPTERS_VER.tar.xz"

# Anything from a previous version of ourselves.
for old in "$SOURCES"/inteliboy-adapters-*.tar.xz; do
    case "$old" in
        *"inteliboy-adapters-$ADAPTERS_VER.tar.xz") ;;
        *[!*]*) [ -e "$old" ] && rm -f "$old" && echo "  removing stale $(basename "$old")" ;;
    esac
done

( cd "$SOURCES" && md5sum *.tar.xz > local.md5sums )
echo
echo "$SOURCES/local.md5sums:"
sed 's/^/    /' "$SOURCES/local.md5sums"
