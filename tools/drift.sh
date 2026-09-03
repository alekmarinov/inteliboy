#!/bin/bash
# Does this device match a build, and where does it not?
#
#     tools/drift.sh root@192.168.1.159
#
# A device patched by hand is a device no image describes, and a soak run
# against one measures a machine that exists nowhere else. This says which
# files under /usr differ from the packages that were built here, so "known
# state" is a thing that can be checked rather than remembered.
#
# It compares hashes, not dates: a push copies files and mtimes drift for
# reasons that mean nothing.
set -u
HOST=${1:?usage: drift.sh <host> [ssh args...]}
shift || true
LFS=${LFS:-../lfs}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# What the packages say /usr should contain.
for pkg in "$LFS"/packages/{cogiti,audi,avatari,reflexi,inteliboy-adapters}.tar.gz; do
    [ -e "$pkg" ] || continue
    sudo tar tzf "$pkg" 2>/dev/null | grep -E "^\./usr/.*[^/]$" \
        | sed 's|^\./||' >> "$tmp/owned"
done
sort -u "$tmp/owned" -o "$tmp/owned" 2>/dev/null || : > "$tmp/owned"
n=$(wc -l < "$tmp/owned")
echo "$n file(s) under /usr come from packages built here"

# Their hashes, from the packages.
: > "$tmp/want"
for pkg in "$LFS"/packages/{cogiti,audi,avatari,reflexi,inteliboy-adapters}.tar.gz; do
    [ -e "$pkg" ] || continue
    d=$(mktemp -d)
    sudo tar xzf "$pkg" -C "$d" 2>/dev/null || true
    ( cd "$d" && sudo find ./usr -type f -print0 2>/dev/null \
        | xargs -0 sha256sum 2>/dev/null ) | sed 's| \./| |' >> "$tmp/want"
    sudo rm -rf "$d"
done
sort -k2 "$tmp/want" -o "$tmp/want"

# And the device's.
#
# The error is NOT swallowed, and the count is checked against what was
# asked for. The first version sent stderr to /dev/null: the device was
# unreachable, the hash list came back empty, join found no pairs, and it
# reported "no drift" — the most reassuring output available for a complete
# failure to look. A checker that cannot say "I could not tell" is worse than
# no checker.
if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 -o BatchMode=yes "$@" "$HOST" \
        "cd / && xargs -0 sha256sum 2>/dev/null" \
        < <(tr '\n' '\0' < "$tmp/owned") \
        | sed 's| /| |' | sort -k2 > "$tmp/have"; then
    echo "cannot reach $HOST — nothing was compared" >&2
    exit 2
fi

got=$(wc -l < "$tmp/have")
if [ "$got" -eq 0 ]; then
    echo "the device returned no hashes at all — nothing was compared" >&2
    exit 2
fi
# Some absence is normal: a package ships files a given device may not have.
# Most of them missing means the comparison did not happen.
if [ "$got" -lt $(( n / 2 )) ]; then
    echo "only $got of $n file(s) came back; refusing to call that a result" >&2
    exit 2
fi
echo "compared $got file(s)"

join -j2 -o 0,1.1,2.1 "$tmp/want" "$tmp/have" 2>/dev/null \
    | awk '$2 != $3 {print "  differs: " $1}' > "$tmp/diff"

d=$(wc -l < "$tmp/diff")
if [ "$d" -eq 0 ]; then
    echo "no drift: every packaged file on the device matches what was built"
else
    echo "$d file(s) differ from the built packages:"
    cat "$tmp/diff"
fi
exit 0
