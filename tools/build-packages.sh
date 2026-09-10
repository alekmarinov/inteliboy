#!/bin/bash
# Build this distro's own packages in the LFS SDK container.
#
#   tools/build-packages.sh [<distro dir>] [<recipe>...]
#
# Naming recipes builds only those, which is how a single package is retried
# without waiting for the other eight — and how this was first tried at all,
# against a scratch LFS_PACKAGES so a test could not reach the cache the
# channel is built from.
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
[ $# -gt 0 ] && shift
ONLY=("$@")
# Absolute, because a bind mount cannot be relative: docker reads a path with
# no leading slash as the *name* of a named volume and says so in terms that
# do not obviously mean "you passed a relative path".
DISTRO_DIR=$( cd -- "$DISTRO_DIR" &> /dev/null && pwd )
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
mkdir -p "$PACKAGES_DIR"
PACKAGES_DIR=$( cd -- "$PACKAGES_DIR" &> /dev/null && pwd )

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
# Declared by the distro, so this does not depend on lfs being reachable.
#
# It used to come only from lfs/scripts/packages/abi-id.sh, and with lfs absent
# `want` was empty and the comparison below was skipped without a word. A
# build that quietly performs no ABI check is worse than one that stops: the
# package installs and the device dies at its first exec.
want=$(sed -n 's/^TARGET_ABI="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' \
           "$DISTRO_DIR/distro.conf" 2>/dev/null | tail -1)
if [ -z "$want" ]; then
    echo "build-packages.sh: $DISTRO_DIR/distro.conf declares no TARGET_ABI." >&2
    echo "  Without it nothing can say which core these packages are for, and" >&2
    echo "  a package built against the wrong one installs and then does not" >&2
    echo "  run. Add TARGET_ABI=\"<abi>\" to distro.conf." >&2
    exit 1
fi

# And cross-checked against lfs when lfs is here, because two sources of one
# fact that disagree is worth stopping for — it means either this file or that
# build base has moved and nobody said so.
measured=$("$LFS_DIR/scripts/packages/abi-id.sh" 2>/dev/null || true)
if [ -n "$measured" ] && [ "$measured" != "$want" ]; then
    echo "build-packages.sh: distro.conf says TARGET_ABI=$want but the lfs" >&2
    echo "  tree next door measures $measured. One of them is stale, and" >&2
    echo "  guessing which would publish packages for a core nobody has." >&2
    exit 1
fi
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
# The packer belongs to lfs, and ships with the base it describes.
#
# It was a copy here, and a copy per consumer has to track every change to a
# format it does not own — forever, silently, and wrongly the first time
# somebody forgets. So this checks that the image carries it and stops if it
# does not, rather than reinstating a local one: a fallback copy is precisely
# how the two would diverge again, and the divergence would not announce
# itself. It would arrive as a package that installs and then does not work.
docker run --rm "$IMAGE" test -r /usr/lib/lpkg/pkg-pack.sh 2>/dev/null || {
    echo "build-packages.sh: $IMAGE has no /usr/lib/lpkg/pkg-pack.sh." >&2
    echo >&2
    echo "  The image predates the packer being shipped with it. Rebuild it:" >&2
    echo "      make -C ../lfs sdk-docker TAG=12.4" >&2
    echo >&2
    echo "  There is deliberately no local copy to fall back to. The package" >&2
    echo "  format is lfs's to define, and a second copy of it here would" >&2
    echo "  drift out of step without saying so." >&2
    exit 1; }

echo "Building in $IMAGE  (abi $have, channel ${chan:-unknown})"

mkdir -p "$PACKAGES_DIR" "$BASE_DIR/build/pkglogs"
built=0; skipped=0; adopted=0

for recipe in "$RECIPES"/*.sh; do
    [ -e "$recipe" ] || continue
    name=$(basename "$recipe" .sh)
    if [ ${#ONLY[@]} -gt 0 ]; then
        wanted=no
        for w in "${ONLY[@]}"; do
            [ "$w" = "$name" ] || [ "$w" = "$name.sh" ] && wanted=yes
        done
        [ "$wanted" = yes ] || continue
    fi
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
    # Under its own name: pack.sh takes the package name from the file, and a
    # recipe copied to "recipe.sh" produces a package called recipe.tar.gz.
    cp "$recipe" "$work/$name.sh"
    # What this package owned last time, so a rebuild is not mistaken for one
    # package overwriting another's files.
    : > "$work/mine"
    if [ -f "$PACKAGES_DIR/$name.tar.gz" ]; then
        tar tzf "$PACKAGES_DIR/$name.tar.gz" 2>/dev/null \
            | sed 's|^\./||' | grep -v '/$' > "$work/mine" || true
    fi

    # The recipe runs exactly as it does in the chroot: sources at /sources,
    # installing into '/'. It needs to know nothing about being in a container,
    # which is the same promise build-distro-packages.sh makes about being
    # external to lfs.
    log="$BASE_DIR/build/pkglogs/$name.log"
    cid=$(docker run -d \
            -v "$SOURCES":/sources:ro \
            -v "$work":/work \
            -w / "$IMAGE" \
            bash -c "set -e; bash /work/$name.sh" )
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
    # /sources as well: pkg_validate resolves the recipe's SOURCE glob against
    # it to derive the version, so a packer that cannot see the tarball
    # produces a package with no identity and no abi stamp.
    docker run --rm -v "$SOURCES":/sources:ro -v "$work":/work "$img" \
        bash /usr/lib/lpkg/pkg-pack.sh "$name"
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
