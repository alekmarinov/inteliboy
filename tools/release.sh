#!/bin/bash
# Give the appliance its next version, and tag it.
#
#     tools/release.sh patch     0.1.3 -> 0.1.4    fixes only
#     tools/release.sh minor     0.1.3 -> 0.2.0    anything new
#     tools/release.sh --check                     verify, change nothing
#
# **The major stays 0 until the appliance is a production release.** Semver
# says 0.y.z is where anything may change, which is exactly true here, and a
# 1.0.0 is a promise about compatibility that nothing is ready to make. So this
# refuses to produce one: `major` is not a level it accepts, and the day it
# should be, that is a deliberate edit here rather than a typo at a prompt.
#
# `distro.conf` states the version twice — VERSION and again inside
# PRETTY_NAME — because lfs *reads* that file rather than sourcing it, on
# purpose, so one field cannot refer to another. Two copies of a number is a
# drift waiting to happen, so nothing hand-edits them: this writes both, and
# --check fails if they ever disagree with each other or with the git tag.
#
# The tag is unprefixed, like every component's: `0.2.0`, not `v0.2.0`.
set -e

BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONF="$BASE/distros/inteliboy/distro.conf"

version_in_conf() { sed -n 's/^VERSION=\(.*\)$/\1/p' "$CONF" | tail -1; }
version_in_pretty() {
    sed -n 's/^PRETTY_NAME="[^ ]* \(.*\)"$/\1/p' "$CONF" | tail -1
}
latest_tag() { git -C "$BASE" tag --list --sort=-v:refname | head -1; }

check() {
    local v p t bad=0
    v=$(version_in_conf); p=$(version_in_pretty); t=$(latest_tag)
    printf '  VERSION      %s\n  PRETTY_NAME  %s\n  git tag      %s\n' \
           "$v" "$p" "${t:-(none)}"
    if [ "$v" != "$p" ]; then
        echo "distro.conf disagrees with itself: VERSION=$v, PRETTY_NAME says $p" >&2
        bad=1
    fi
    if [ -n "$t" ] && [ "$v" != "$t" ]; then
        echo "distro.conf says $v but the latest tag is $t; an image built now" >&2
        echo "would claim a version nobody released." >&2
        bad=1
    fi
    return $bad
}

case "${1:-}" in
    --check|"") check; exit $? ;;
    patch|minor) LEVEL=$1 ;;
    major)
        echo "The major stays 0 until the appliance is a production release." >&2
        echo "1.0.0 is a promise about compatibility; make it deliberately," >&2
        echo "by editing this script, not by passing an argument." >&2
        exit 1 ;;
    *) echo "usage: release.sh [patch|minor|--check]" >&2; exit 1 ;;
esac

[ -z "$(git -C "$BASE" status --porcelain)" ] || {
    echo "the tree is dirty; commit first — a tag should name a state that exists" >&2
    git -C "$BASE" status --short >&2
    exit 1
}

CUR=$(version_in_conf)
IFS=. read -r MA MI PA <<< "$CUR"
case "$LEVEL" in
    patch) PA=$((PA + 1)) ;;
    minor) MI=$((MI + 1)); PA=0 ;;
esac
NEXT="$MA.$MI.$PA"

# Both fields, from one number, in one place.
sed -i -e "s/^VERSION=.*/VERSION=$NEXT/" \
       -e "s/^PRETTY_NAME=\".*\"$/PRETTY_NAME=\"InteliBoy $NEXT\"/" "$CONF"

git -C "$BASE" add "$CONF"
git -C "$BASE" commit -q -m "InteliBoy $NEXT"
git -C "$BASE" tag -a "$NEXT" -m "InteliBoy $NEXT"

echo "$CUR -> $NEXT, committed and tagged."
echo "Push the tag too, or nobody else has it:  git push && git push --tags"
