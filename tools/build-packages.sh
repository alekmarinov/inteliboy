#!/bin/bash
# Build this distro's own packages in the LFS SDK container.
#
#   tools/build-packages.sh [<distro dir>]
#
# ---------------------------------------------------------------------------
# Why this exists
#
# It used to be `sudo make -C ../lfs distro-packages`, which built into lfs's
# single shared overlay — one $LFS mount, one $LFS_PACKAGE upper layer. Two
# builds at once overwrote each other silently, and did:
#
#   6 Sep   a ruby package came out holding 5166 audi files and no ruby. It
#           surfaced two days later as "Ruby 2.5 or higher is required" in the
#           middle of a WebKit configure.
#   8 Sep   an inteliboy-adapters build cleared $LFS_PACKAGE while a ruby
#           rebuild was copying out of it.
#
# lfs now has a flock at .lfs-build.lock, so that corruption is over — but
# serialising means waiting, sometimes hours behind a wpewebkit compile. A
# container has the same shape as the overlay and none of the sharing: the
# image is the lower layer, the container's writable layer is the upper, and
# `docker diff` enumerates it exactly as the upper directory did. Any number
# at once, no mount, no root on the host.
#
# **There is deliberately no fallback.** If Docker is missing this stops. A
# quiet return to the shared overlay would reintroduce precisely what this
# removes, on the day somebody is least expecting it.
set -e

BASE_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )
DISTRO_DIR=${1:-$BASE_DIR/distros/inteliboy}
SOURCES="$DISTRO_DIR/sources"
RECIPES="$DISTRO_DIR/packages"
ID=$(basename "$DISTRO_DIR")
IMAGE=${LFS_SDK_IMAGE:-lfs-sdk:12.4}

# Where the finished packages go. Unchanged, and it has to be: build-repo.sh
# hardlinks the channel out of this directory and build-distro.sh assembles
# the rootfs from it. Distinct file names in a shared directory were never the
# problem — the shared *build* layer was.
LFS_DIR=${LFS:-$BASE_DIR/../lfs}
PACKAGES_DIR=${LFS_PACKAGES:-$LFS_DIR/packages}

# ------------------------------------------------------------------ docker --
command -v docker > /dev/null || {
    echo "build-packages.sh: docker is not installed, and there is no fallback." >&2
    echo >&2
    echo "The old path built into lfs's shared overlay, where two builds at" >&2
    echo "once corrupted each other twice in three days. Falling back to it" >&2
    echo "quietly would bring that back at the worst possible moment, so this" >&2
    echo "stops instead. Install docker, or build in lfs deliberately." >&2
    exit 1; }
docker info > /dev/null 2>&1 || {
    echo "build-packages.sh: docker is installed but not answering." >&2
    echo "  (is the daemon running, and is this user in the docker group?)" >&2
    exit 1; }
docker image inspect "$IMAGE" > /dev/null 2>&1 || {
    echo "build-packages.sh: no image $IMAGE." >&2
    echo "  It is the LFS build base, labelled with the ABI it belongs to." >&2
    exit 1; }

# --------------------------------------------------------------------- abi --
#
# Checked before anything is built, not after. A package compiled against a
# different core is installable only on a system with that core, and the ABI
# id is the only thing that says so: sonames cannot: a binary needing
# GLIBC_2.38 asks for libc.so.6, which is what every glibc since 1997 has
# called itself.
want=$("$LFS_DIR/scripts/packages/abi-id.sh" 2>/dev/null || true)
have=$(docker image inspect --format '{{index .Config.Labels "org.intelibo.lfs.abi"}}' "$IMAGE")
chan=$(docker image inspect --format '{{index .Config.Labels "org.intelibo.lfs.channel"}}' "$IMAGE")
if [ -z "$have" ]; then
    echo "build-packages.sh: $IMAGE carries no org.intelibo.lfs.abi label." >&2
    echo "  An unlabelled base cannot say which core it is, so nothing built" >&2
    echo "  in it can be checked against the channel it would be published to." >&2
    exit 1
fi
if [ -n "$want" ] && [ "$want" != "$have" ]; then
    echo "build-packages.sh: $IMAGE is $have; this tree publishes to $want." >&2
    echo >&2
    echo "  Packages built against one core install only on that core, and" >&2
    echo "  nothing downstream would notice: the channel would take them and" >&2
    echo "  a device would fail at the first exec rather than at install." >&2
    echo "  Refresh the image, or point LFS_SDK_IMAGE at the right one." >&2
    exit 1
fi
echo "Building in $IMAGE  (abi $have, channel ${chan:-unknown})"

mkdir -p "$PACKAGES_DIR" "$BASE_DIR/build/pkglogs"
built=0; skipped=0; adopted=0

for recipe in "$RECIPES"/*.sh; do
    [ -e "$recipe" ] || continue
    name=$(basename "$recipe" .sh)
    flag="$BASE_DIR/build/pkglogs/$name.ready"
    sum_file="$BASE_DIR/build/pkglogs/$name.recipesum"
    sum=$(sha256sum "$recipe" | cut -d' ' -f1)

    # Same decision lfs makes, for the same reasons: the recipe by content,
    # never by mtime — a staged copy's mtime is the time of the copy, and the
    # original's churns on `git checkout` — and its own sources by timestamp,
    # because hashing hundreds of megabytes to learn nothing costs real time.
    why=""
    if [ ! -f "$PACKAGES_DIR/$name.tar.gz" ]; then
        why="not built yet"
    elif [ ! -f "$sum_file" ]; then
        printf '%s\n' "$sum" > "$sum_file"
        adopted=$((adopted + 1))
    elif [ "$(cat "$sum_file")" != "$sum" ]; then
        why="recipe changed"
    elif [ -n "$(find "$SOURCES" -maxdepth 1 -newer "$PACKAGES_DIR/$name.tar.gz" \
                      -name "$name*.tar.*" -print -quit 2>/dev/null)" ]; then
        why="source is newer than the last build"
    fi
    if [ -z "$why" ]; then
        echo "$name: unchanged since it was last built; skipping"
        skipped=$((skipped + 1))
        continue
    fi
    echo "$name: $why"

    work=$(mktemp -d); cid=""
    cleanup() {
        [ -n "$cid" ] && docker rm -f "$cid" > /dev/null 2>&1 || true
        rm -rf "$work"
    }
    trap cleanup EXIT

    mkdir -p "$work/out"
    cp "$recipe" "$work/recipe.sh"
    cp "$BASE_DIR/tools/sdk/pack.sh" "$work/pack.sh"

    # The recipe runs exactly as it does in the chroot: sources at /sources,
    # installing into '/'. It needs to know nothing about being in a container,
    # which is the same promise build-distro-packages.sh makes about being
    # external to lfs.
    log="$BASE_DIR/build/pkglogs/$name.log"
    cid=$(docker run -d \
            -v "$SOURCES":/sources:ro \
            -v "$work":/work \
            -w / "$IMAGE" \
            bash -c 'set -e; bash /work/recipe.sh' )
    if ! docker wait "$cid" | grep -qx 0; then
        docker logs "$cid" > "$log" 2>&1 || true
        echo "$name: the build failed. Last of $log:" >&2
        tail -n 25 "$log" >&2
        exit 1
    fi
    docker logs "$cid" > "$log" 2>&1 || true

    # The layer, read from outside because the inside cannot see it.
    docker diff "$cid" > "$work/diff"

    # Packaged in a container of the finished image, so the helpers it ships
    # describe the build with the same code build-package.sh uses.
    img=$(docker commit "$cid" 2>/dev/null)
    docker run --rm -v "$work":/work "$img" bash /work/pack.sh
    docker rmi "$img" > /dev/null 2>&1 || true

    mv "$work/out/$name.tar.gz" "$PACKAGES_DIR/$name.tar.gz"
    printf '%s\n' "$sum" > "$sum_file"
    : > "$flag"
    built=$((built + 1))
    cleanup; trap - EXIT
done

if [ "$adopted" -gt 0 ]; then
    echo "Recorded $adopted recipe(s) as already built without rebuilding them."
fi
echo "Built $built package(s) for '$ID', $skipped unchanged."
