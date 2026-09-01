# 2026-08-31-semver — every repository says its version in semver

Status: **approved — implementing**
Approved by: Alexander Marinov, 2026-08-31
Blocks: `2026-08-31-inteliboy-out-of-lfs` order 9, which names tarballs after
the version and rewrites their checksums.

## The ask

Versions are semver, not commit hashes. A release is `0.1.0`; anything else is
visibly not a release.

## The seam

    contract:  none on the wire. A naming convention plus a git tag per repo.
    owner:     each repository names itself; this one records the set.
    consumers: the tarball names, /etc/os-release, versions.lock

## Findings

1. **Nothing is versioned because nothing is tagged.** avatari `0` tags,
   reflexi `0`, cogiti and this repository have **no commits at all**. That is
   the entire cause of `avatari-0.0.0-g6458162.tar.xz`.

2. **avatari already asks for semver first.** Its Makefile does
   `git describe --tags --dirty`, and falls back to `0.0.0-g<hash>` only when
   that fails. Tagging is the whole change there; no code moves.

3. **A `v` prefix would break the build, silently.** `x-make-avatari.sh:41`
   globs `/sources/avatari-[0-9]*.tar.xz`, anchored on a digit so it does not
   also match `avatari-heads-`. A `v0.1.0` tag names the tarball
   `avatari-v0.1.0.tar.xz`, which that glob misses without saying so. **Tags
   carry no prefix.**

4. **reflexi has no version mechanism of any kind** — no `VERSION`, no `dist`,
   only `distclean`. It needs avatari's derivation before a tag means anything.

5. **avatari's `.version` file is not decoration.** A dist tarball carries it
   because an unpacked source tree has no git and the LFS build runs offline
   against exactly that tree. Any component whose source reaches the image
   needs the same or it reports `0.0.0-unknown` from inside the build.

6. **lfs's only tag is `LFS_11.2`, and it is stale.** The repository was
   ported to LFS 12.4 in `f431d8f` and `.env` says `LFS_VER=12.4`, so
   `git describe` there reports `LFS_11.2-1-gf431d8f`. It is also prefixed,
   against decision 2. Out of scope by decision 5 — noted so that the next
   person to look at lfs's version does not read that tag as current.

7. **A tag is not an identity.** Tags move, and a dirty tree has no version at
   all. The commit is the only thing that reproduces a build.

## Decisions

1. **`0.1.0` where git is present and can be tagged; `0.0.0` where not yet.**
   So avatari and reflexi are tagged `0.1.0` now. cogiti and this repository
   have no commits, so they are `0.0.0` until they have one.

2. **Tags are unprefixed** — `0.1.0`, never `v0.1.0` (finding 3).

3. **Between releases the version says so.** `git describe --tags --dirty`
   gives `0.1.0-3-g489c9d6`, and `-dirty` when the tree is not clean. Kept
   deliberately: a clean semver means a release and nothing else does.

4. **`versions.lock` records both.** The version to read, the commit to
   reproduce:

       avatari = { version = "0.1.0", commit = "489c9d6…" }

   Semver is what we talk about and what ships; the hash is what makes the lock
   a lock (finding 6).

5. **lfs is not versioned by this change.** `LFS_VER=12.4` is the upstream
   book's version, not lfs's own. Giving lfs a version of its own is a separate
   question and needs a tag distinct from that one.

## Per repo

Orders 1–3 are done. The `versions.lock` format is proven; the file itself is
written by `2026-08-31-inteliboy-out-of-lfs` order 10, after the image boots —
a file headed "the last set proven to work together" should not exist before
anything has been proven.

### avatari [order 1] — tag `0.1.0` ✅
files: none
change: `git tag 0.1.0` at HEAD. The Makefile already derives from it.
**proves it:** `make dist` produces `avatari-0.1.0.tar.xz`, not
`avatari-0.0.0-g6458162.tar.xz`.

### reflexi [order 2] — the derivation, then the tag ✅
files: `Makefile`
change: avatari's `VERSION` block — `.version` if present, else
`git describe --tags --dirty`, else `0.0.0-unknown` — and a `version` target
that prints it. Then `git tag 0.1.0`.
**proves it:** `make version` prints `0.1.0`.

### inteliboy [order 3] — the appliance's own version ✅
files: `distros/inteliboy/distro.conf`, `Makefile`
change: `VERSION=0.0.0` and `PRETTY_NAME="InteliBoy 0.0.0"` — this repository
has no commits, so by decision 1 it is not yet `0.1.0`. `make lock` writes
`version` beside `commit` for every component.
**proves it:** `/etc/os-release` in the next image reads `VERSION="0.0.0"` and
`VERSION_ID=0.0.0` rather than an unset `ID` and a two-part version.

### cogiti — nothing to do
No commits, no code. `0.0.0` by decision 1, and it needs avatari's `VERSION`
block in its first commit rather than a file created in an empty repository
now.

## Not in this change

- Versioning lfs itself (decision 5).
- Deriving `distro.conf`'s `VERSION` from a git tag rather than stating it.
  Worth doing once this repository has tags — a hand-maintained version beside
  a derived one is exactly how the avatari tarballs drifted from their
  checksums. For now the two-line coupling between `VERSION` and `PRETTY_NAME`
  is noted here instead of automated.
- Pushing any tag. They are local until the user pushes them.

## Rollback

`git tag -d 0.1.0` in avatari and reflexi; revert the Makefile edits. Nothing
is pushed and no commit is made, so there is nothing else to undo.
