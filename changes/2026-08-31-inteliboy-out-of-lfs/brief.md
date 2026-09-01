# 2026-08-31-inteliboy-out-of-lfs — lfs takes a distro from a path; InteliBoy's leaves

Status: **approved — implementing**
Supersedes: `2026-08-31-lfs-product-split` (same directory, rewritten after the
design conversation of 2026-08-31; the `PRODUCT` concept it was built on was
dropped — see Decisions)
Approved by: Alexander Marinov, 2026-08-31

> **No agent was run.** The survey was done by hand, against the repositories
> themselves, and every claim below was checked with a command. Where a number
> or a line reference appears, it was read, not remembered.

## The ask

lfs should build a distro handed to it from outside, the way a compiler takes a
source tree. InteliBoy holds its own distro — package list, overlay, recipes,
kernel config, sources — in this repository. Afterwards `grep -ri inteliboy
../lfs` comes back empty, and that stays true.

## The seam

    contract:  distro format (a directory lfs is pointed at)
    owner:     lfs
    consumers: this repository. The only one, and there will be no others.
    breaking:  yes, and that is allowed — owner and consumer land in the
               same change and the lock bumps once at the end.

Nothing outside this project uses lfs. There is no compatibility to preserve,
no deprecation window and no in-band version gate. `versions.lock` records
which lfs this distro was built against; that is the whole of the pinning
story.

**Order is causality.** lfs must be able to take a distro from a path before
InteliBoy's can leave. Move the files first and the image cannot be built at
all.

## Shared vocabulary

| term | means |
|---|---|
| **distro** | one directory: `distro.conf`, `packages.list`, `files/`, `check.ignore`, and now optionally `packages/`, `sources/`, `boot-entries`. There is exactly one of ours |
| `DISTRO` | bare name → `distros/<name>` inside lfs, as today. A path → that directory, wherever it is |
| `ID` | the distro's identifier from `distro.conf`. Names the output directory. Becomes mandatory |
| `OUT` | where `rootfs/` and the image are written. `build/$(ID)` |
| **fixture** | a copy of `distros/minimal` at a path outside lfs, used to test each step. Made by the test, not stored |

The word *product* is not used. InteliBoy is the integration of lfs, cogiti,
reflexi and avatari; a distro is a distro.

## Decisions

Taken in conversation on 2026-08-31, recorded so they are not re-opened. The
alternative is given where one was seriously considered.

1. **The orchestrator edits lfs but never commits it.** It makes the changes
   an approved brief calls for and then stops, handing over a proposed commit
   message; the user commits. No agent writes there at all — the `lfs` agent
   still has read tools only, because the risk that rule addresses (an agent
   patching the build tool to unblock itself) is unchanged. **lfs also carries
   no file of ours** — no `CLAUDE.md`, no agent configuration, nothing
   addressed to a session. `CLAUDE.md`, `components.toml`,
   `.claude/agents/lfs.md` and `docs/DEVELOPMENT.md` were updated to say this;
   an earlier revision of this brief said the orchestrator lands and pins lfs
   changes itself, and that was wrong.

2. **InteliBoy's distro lands in this repository**, at `distros/inteliboy/`.
   Plural directory from the start so a second distro costs a directory rather
   than a rename. *Rejected:* a separate repository for it — one more tree to
   keep in step, to hold a directory that describes the integration this
   repository already is.

3. **No `PRODUCT` concept.** The first draft introduced a level above the
   distro to hold shared recipes and sources. It is unnecessary: making
   `packages` and `sources` search paths expresses "these distros share
   recipes" without lfs knowing that two directories are related, and lfs
   already needed `sources` to be a search path. Grouping distros is this
   repository's business, not the tool's.

4. **Product strings leave lfs by declaration, not by variable substitution.**
   `inteliboy.norender` and the `(with nouveau)` entry both become boot entries
   the distro declares. *Rejected:* a single `RESCUE_CMDLINE` key — it removes
   the hardcoded string but leaves lfs synthesising a menu entry by sniffing
   `modprobe.blacklist=`, which is the same defect better disguised.

5. **One distro, a development one**, until it is good enough to spawn a
   release one. `inteliboy-dev` is not created, which also unblocks
   `changes/2026-08-31-appliance-sshd/` — sshd goes in the one distro.

6. **No backward compatibility anywhere in this change.**

7. **Nothing is committed in any repository until the image boots.** The goal
   is a clean structure and an operational InteliBoy image; history is written
   once that exists. The orders below are therefore the order of *work* and of
   the eventual commits, not a sequence of landings. The cost is accepted and
   stated: for the duration there is no bisect point, and `make dirty` is
   blind in both repositories, not just lfs.

8. **sshd is absorbed into this change.** It was
   `changes/2026-08-31-appliance-sshd/`, blocked on a question decision 5
   answered. It is one package-list line plus one config file in the distro
   being moved, and an operational image is the goal, so it lands here rather
   than as a second change against the same files.

9. **Root logs in over ssh with a password, and the password is unchanged.**
   `LFS_ROOT_PASSWORD=toor` in lfs's `.env` stays as it is. Making it settable
   per distro is possible and is deliberately not done yet.

10. **The image carries whatever avatari's HEAD is when it is staged.** Not a
    pinned or chosen revision: `make stage` runs avatari's `make dist` against
    its current checkout, and that is what goes in. The package cache holds
    `avatari-0.0.0-g6458162` from 2026-08-30 while avatari's HEAD is `489c9d6`,
    so the avatari package is rebuilt as part of this change rather than reused.
    `versions.lock` records which revision it was afterwards; it does not
    select it beforehand.

11. **`IMAGE_SIZE` moves from `.env` into each `distro.conf`**, including
    lfs's own example distros. How big an image needs to be is a property of
    the distro, and `.env` could only ever say one number for all of them —
    the Makefile `export`s `.env` wholesale, so a per-distro value could not
    have won against it even if one had been written. The values are unchanged
    at 7168 MB for now: right-sizing each distro needs a measured rootfs,
    which does not exist until the build runs.

12. **A distro's own recipes are built by lfs, from a target of its own.**
    `make distro-packages DISTRO=<name|path>` stages the distro's `packages/`
    and `sources/` into the build overlay's base layer and builds them. It is
    generic — it takes a distro exactly as `make distro` does and knows nothing
    about InteliBoy.

    *Rejected:* driving it from this repository instead, so that lfs's build
    pipeline is untouched. The concern behind that — **lfs should not dictate
    the structure of its client** — is real, but this was the wrong lever for
    it: both arrangements require the distro directory to have the same shape,
    so neither buys any freedom, and driving it from here would additionally
    couple us to lfs's internals (`overlay/base`, the recipe path convention,
    the names in `.env`) which are not its interface. What lfs dictates is the
    *format of one directory*; where that directory lives and what else the
    repository holds are already ours. If the filenames become a real
    constraint, the cheap answer is `distro.conf` naming them
    (`PACKAGES_DIR=`, `SOURCES_DIR=`) and the complete one is generating the
    directory lfs sees — both additive, neither needed by one distro.

    `make packages` stays distro-agnostic and expensive, which is what keeps a
    second distro costing the base build nothing.

13. **The appliance's output lives in this repository, gitignored.** `OUT`
    covers `rootfs/`, `image.img` and `image.img.nvram`, so a multi-gigabyte
    root-owned tree lands in `inteliboy/build/`. Accepted deliberately: the
    alternative is lfs holding a `build/inteliboy/` directory, which is the
    thing this change exists to remove. `rm -rf` on it needs sudo.

14. **A client's recipes are free of lfs's naming convention.** `x-` marks a
    package the LFS book does not cover and is lfs's business for its own tree.
    A distro's own `packages/` may name its recipes anything. That is not free:
    `order-deps.sh:34` globs `*-make-*.sh`/`[0-9]*-*.sh`, and both
    `build-distro.sh:69` and `list-runtime-packages.sh:25` hardcode
    `(lfs|blfs)`, so all three have to learn about the distro's directory.

    **`build-distro.sh:206` would have hidden the consequence.** Packages in
    `packages.list` that `build_order()` does not know fall into an `unknown`
    bucket and are installed *first*. After the move, avatari and the kernel
    would land there — installing before Mesa instead of after it, working only
    by luck, and reported as a note rather than an error.

15. **`make deps-verify` cannot see a distro's recipes, and could not before
    either.** It runs against lfs's host tree; staged recipes exist only inside
    `overlay/base`. Rather than pretend otherwise, `docs/lfs.md` says the
    dependency checks cover lfs's own packages and not a distro's.

## Findings

Each was verified against the repositories on 2026-08-31.

1. **Nothing of InteliBoy's has ever been committed to lfs.** `git grep -in
   -E 'inteliboy|avatari' HEAD` returns nothing, and `git ls-files` matches no
   product filename. Everything is in the uncommitted working tree. The move is
   `mv`, and several removals are simply "do not commit this".

2. **lfs's tree is 17 entries dirty** — 9 modified, 8 untracked — and mixes
   generic work with InteliBoy's. Sorting it is the first thing; everything
   after is illegible without it. The baseline is recorded below.

3. **`distros/full/packages.list:175-177` installs avatari.** One of lfs's own
   example distros was made to depend on InteliBoy's renderer, temporarily, and
   forgotten. Uncommitted, so the fix is to leave the three lines out of the
   commit. The first draft of this brief missed it entirely.

4. **`build-image.sh` recovers the distro rather than receiving it.**
   `build-distro.sh:387` writes `/etc/lfs-distro` into the rootfs containing
   `DISTRO=$distro`; `build-image.sh:25` reads it back and line 82 resolves
   `distros/$DISTRO_IN_ROOTFS/distro.conf`. Once `DISTRO` is a path that
   round-trip breaks. Fix by copying the resolved `distro.conf` into the rootfs
   at assembly time and reading it from there — build-image then resolves no
   path at all.

5. **`ID` is unset for InteliBoy, and it is about to become load-bearing.**
   `build-distro.sh:42` *sources* `distro.conf`; `ID` has no default;
   `distros/inteliboy/distro.conf` has no `ID=` line and neither does `core`.
   So assembling the appliance today writes `ID=` empty into `/etc/os-release`,
   deletes `/etc/lfs-release` because `"" != "lfs"` (line 308), and creates a
   file named **`/etc/-release`** (line 311). `HOME_URL` is empty for the same
   reason. Invisible so far; not once `ID` names the output directory.

6. **Seven recipes declare `BUILD_REQUIRES:` and leave it empty**, not one as
   the first draft said: the InteliBoy kernel, `x-make-avatari-heads`,
   `x-make-avatari-voices`, `x-make-linux-firmware-iwlwifi`,
   `x-make-linux-firmware-realtek`, `x-make-wireless-regdb`, `17-make-libnl`.
   Harmless while the order is hand-written, dangerous once a resolver places a
   package, because a node with no edges can be placed before gcc. Two of the
   seven are InteliBoy's and are moving.

7. **Do not generate `build-packages.sh` from declarations.** Only 11 of 102
   `lfs/` recipes and 43 of 136 `blfs/` recipes carry a `BUILD_REQUIRES` line
   at all. The book's chapter order is the authority. The resolver places
   *appended* recipes and verifies; it does not own the list. (Kept from the
   first draft, which was right about this.)

8. **The kernel is a leaf and safe to move.** Nothing declares a dependency on
   any kernel package; nothing in the blfs half consumes its output; the
   microcode initrd is assembled at image time from files in the rootfs. Its
   position at `build-packages.sh:119` is inherited from the book's chapter
   order, not from a requirement.

9. **`build-image.sh:63` picks the kernel with `ls .../boot/vmlinuz* | head
   -1`.** One kernel per distro is what makes that safe. Keep the rule, enforce
   it in `query-deps.sh check` where it costs a second, and harden the line to
   refuse on two rather than pick the lexically first.

10. **lfs has no `CLAUDE.md`.** A session there has `README.md` and nothing
    else — no statement of what lfs is, and nowhere the invariant this change
    buys could be written down. It is a precondition, not an afterthought.

12. **Root cannot log in by password as things stand.**
    `4-make-openssh.sh` installs stock upstream `sshd_config`, in which
    `#PermitRootLogin prohibit-password` is commented out — so the compiled-in
    default applies and password auth for root is refused. There is no
    `Include` directive in that file either, so a drop-in fragment does
    nothing; a distro that wants different behaviour ships a whole
    `sshd_config` in its overlay. No distro does today.

13. **The ssh host keys are baked into the package, and are therefore shared
    by every image ever built from this cache.** `packages/4-make-openssh.tar.gz`
    contains `etc/ssh/ssh_host_{rsa,ecdsa,ed25519}_key` — real private keys,
    dated at package build time — because OpenSSH's `make install` runs
    `ssh-keygen -A`. The installed init script contains no key generation. So
    `minimal`, `full` and `minimal-desktop` already ship identical host keys,
    and InteliBoy would too. `changes/2026-08-31-appliance-sshd/` states the
    opposite; that claim is wrong and this brief supersedes it. The fix is
    generic, belongs in lfs, and repairs all four distros at once.

11. **A pre-existing defect, adjacent and not in this change.** `sources/` holds
    `kernel-5.19.2.config`; the wget list ships `linux-6.16.1.tar.xz`. The
    generic recipe copies the 5.19 config onto a 6.16 tree and runs plain
    `make` with no `olddefconfig`. The InteliBoy recipe does it correctly. It is
    an argument for this change — a recipe and its config drifted apart because
    they live in different directories.

## The dirty baseline

lfs is already dirty, so `make dirty` is pre-tripped and blind for the duration
of this change. These 17 are expected. **An 18th is the alarm.**

    M distros/core/packages.list                    M scripts/packages/build-packages.sh
    M distros/full/packages.list                    M scripts/packages/list-runtime-packages.sh
    M distros/minimal-desktop/packages.list         M sources/blfs-11.2.md5sums
    M distros/minimal/packages.list                 M sources/blfs-11.2.wget-list
    M scripts/image/build-image.sh
    ?? distros/inteliboy/                           ?? scripts/packages/lfs/10.3-make-linux-kernel-inteliboy.sh
    ?? scripts/packages/blfs/42-make-alsa-utils.sh  ?? sources/kernel-inteliboy-6.16.config
    ?? scripts/packages/blfs/x-make-avatari.sh      ?? sources/local.md5sums
    ?? scripts/packages/blfs/x-make-avatari-heads.sh
    ?? scripts/packages/blfs/x-make-avatari-voices.sh

**The set grows as the work proceeds, and each addition is named here.** An
entry that appears without being written down is the alarm; the count alone
means nothing while a change is in flight.

| added by | entry |
|---|---|
| order 2 | `M scripts/image/build-distro.sh` |
| order 2 | `M scripts/image/check-distro.sh` |
| order 4 | `distros/inteliboy/boot-entries` (inside an already-untracked directory, so it adds no line) |
| order 5 | `M .env` — `IMAGE_SIZE` removed |
| order 5 | `M distros/{minimal,full,minimal-desktop}/distro.conf` — `IMAGE_SIZE` added |
| order 6 | `M Makefile` — the `distro-packages` target |
| order 3 | `M scripts/packages/blfs/4-make-openssh.sh` — host keys, first-boot keygen |
| order 8 | `M scripts/image/qemu.sh` — opt-in `QEMU_HOSTFWD` |
| order 6 | `?? scripts/resolve-distro.sh`, `?? scripts/packages/build-distro-packages.sh` |
| order 5 | `M .env` — `IMAGE_FILE` removed · `M scripts/image/{qemu,build-docker}.sh` |

22 entries as of order 8. The count fell from 28 when the distro left lfs.
`make status` before and after each order.

**Two other repositories are permanently dirty, and neither is an alarm.**
`cogiti` has no commits at all, so all four of its entries — `.gitignore`,
`CLAUDE.md`, `README.md`, `docs/` — are untracked and always will be until its
first commit. `reflexi` has one entry, its `Makefile`, from
`changes/2026-08-31-semver/`. Neither is touched by this change; an entry
beyond these is the alarm.

This repository is not in the guard at all — `make dirty` walks
`components.toml`, which lists the components and not the orchestrator. It also
has no commits, so nothing here is tracked either.

## Per repo

Branch `inteliboy-out-of-lfs` in each. Order 0 is here; orders 1–6 are edits
to lfs; order 7 spans both; orders 8–10 are here.

**Every lfs commit is the user's.** The orchestrator makes the edits and
proposes the message; it does not run `git commit` in `../lfs`, on any branch,
for any reason.

**Per decision 7, none of this is committed as it is done.** The work happens
in the working trees, the image is built and booted, and only then are the
commits written — in this order, with the file lists below as the record of
which change each file belongs to. That record is the only thing standing in
for a clean history while the trees are dirty, so it is kept accurate as the
work proceeds rather than reconstructed at the end.

### inteliboy [order 0] — write `docs/lfs.md`
files: `docs/lfs.md` (new)
change: what lfs is; that it is a tool with one consumer; its *Hard
boundaries*, of which the first is that it holds its own example distros and
nothing of InteliBoy's, and the fifth that we edit it and never commit it.
Nothing else in this change can be reviewed against a boundary that is not
written down. It lives **here**, not in lfs: the tool carries no file of ours.
**proves it:** it exists, states the invariant of order 7, and `find ../lfs
-iname '*claude*'` returns nothing.

### lfs [order 1] — sort the working tree
files: `scripts/packages/list-runtime-packages.sh`, `distros/{core,full,minimal,minimal-desktop}/packages.list`, `scripts/packages/blfs/42-make-alsa-utils.sh`, `sources/blfs-11.2.{md5sums,wget-list}`, `scripts/packages/build-packages.sh`
change: commit the generic work that has nothing to do with paths — the
`DISTRO_ONLY` mechanism, the per-distro kernel lines, the alsa-utils recipe with
its wget/md5sum entries and its one build-order line. **Leave out** the three
avatari lines in `full/packages.list` (finding 3) and the five InteliBoy lines
in `build-packages.sh` (119, 260–263). `build-image.sh` is not committed here —
its pending work is rewritten path-aware in order 2 rather than landed twice.
**proves it:** `make deps-verify && make deps-check`; `make distro DISTRO=full`
assembles without avatari; `git status` shows 11 entries, all of them either
`build-image.sh` or files that leave in order 6.

### lfs [order 2] — `DISTRO` takes a path
files: `scripts/image/build-distro.sh`, `scripts/image/check-distro.sh`, `scripts/image/build-image.sh`, `Makefile`
change: `DISTRO_DIR` resolves a path as given, a bare name under `distros/`.
`build-distro.sh` copies the resolved `distro.conf` into the rootfs and
`build-image.sh` reads it from there instead of rebuilding a path from
`/etc/lfs-distro` (finding 4). `ID` becomes mandatory for an assembled distro
and `build-distro.sh` refuses without it; `distros/inteliboy/distro.conf` gains
`ID=inteliboy` and `HOME_URL` (finding 5). The pending generic `build-image.sh`
work — `GRUB_TIMEOUT` and `KERNEL_CMDLINE` read from the distro, hidden menu
timeout, verbose-console entry — lands here in its final form.
**proves it:** `cp -r distros/minimal /tmp/ext-distro && make distro
DISTRO=/tmp/ext-distro` assembles; `make distro DISTRO=minimal` still works by
name; a `distro.conf` with no `ID=` is refused with a sentence.

### lfs [order 3] — sshd stops shipping its host keys
files: `scripts/packages/blfs/4-make-openssh.sh`, the sshd init script it installs
change: delete `/etc/ssh/ssh_host_*` after `make install` so no private key is
ever written into the package cache, and have sshd's init script run
`ssh-keygen -A` when the keys are absent, so each device generates its own on
first boot (finding 13). Generic: it repairs `minimal`, `full` and
`minimal-desktop` too. **The openssh package must be rebuilt** — it is the one
package in this change that cannot be reused from the cache.
**proves it:** the rebuilt `4-make-openssh.tar.gz` contains no
`ssh_host_*_key`; two images built from it have different host key
fingerprints.

### lfs [order 4] — the distro declares its boot entries
files: `scripts/image/build-image.sh`, `distros/inteliboy/boot-entries` (new)
change: lfs generates only the two entries it can derive from
`KERNEL_CMDLINE` — the default and the verbose console — and appends whatever
`boot-entries` in the distro directory declares, one `title` and command line
per line, read with `sed` and never sourced, as `build-image.sh` already does
for `distro.conf`. Delete the `inteliboy.norender` entry (line 294) and the
`modprobe.blacklist=` sniffing that synthesises the `(with nouveau)` entry
(line 227) along with the comment naming the laptop. Both move into
`distros/inteliboy/boot-entries`, where the knowledge of that hardware lives.
**proves it:** `grep -rni inteliboy scripts/` returns nothing; a distro with no
`boot-entries` gets exactly two menu entries; InteliBoy's image still offers
rescue and nouveau.

### lfs [order 5] — `OUT` per distro, and the image sized by the distro
files: `Makefile`, `scripts/image/build-distro.sh`, `scripts/image/build-image.sh`, `scripts/image/qemu.sh`
change: `OUT` is `build/<ID>` and holds `rootfs/`, `image.img` and
`image.img.nvram`. **Every image-side script takes the same `DISTRO` argument
and derives `OUT` from it through `resolve-distro.sh -o`** — `build-distro`,
`build-image`, `check-distro`, `build-docker`, `qemu`. `make image` used to
take no distro because there was one shared `rootfs/`; that ambiguity is what
`EXPECT_DISTRO` existed to catch, and it is gone. The guard stays as a cheap
assertion rather than the only defence.

`IMAGE_SIZE` and `IMAGE_FILE` both leave `.env`, for the same reason: the
Makefile `export`s it wholesale, so anything named there beats a per-distro
value and would have made one silently ineffective. `IMAGE_SIZE` is declared by
each distro and refused if it is not a plain number of megabytes (decision 11);
`IMAGE_FILE` defaults to `$OUT/image.img`.

InteliBoy passes its own `OUT` into this repository (decision 13), so lfs ends
up with no directory named after us — `build/` there holds only its own
examples.
**proves it:** `make all DISTRO=full` reports `build/full/rootfs`, `DISTRO=minimal`
reports `build/minimal/rootfs`; `OUT=/tmp/elsewhere` overrides both.
The "already holds another distro" guard stops being the common case. Remove
the stale `image.img`, `inteliboy.img*`, `oldstyle.img`, `unstripped.img` and
`rootfs/` from lfs's root — gitignored, but they are still InteliBoy's output
sitting inside the tool.


### lfs [order 6] — a distro builds the recipes it brings
files: `scripts/resolve-distro.sh` (new), `scripts/packages/build-distro-packages.sh` (new), `scripts/image/build-distro.sh`, `Makefile`
change: `make distro-packages DISTRO=<name|path>` stages the distro's
`packages/` into `$LFS_BASE/scripts/packages/<ID>/` and its `sources/` into
`$LFS_BASE/sources/`, then builds each recipe through the existing
`build-package.sh`. Staging into the overlay's base layer is what makes a
distro's recipe an ordinary recipe: after it, the recipe is at
`/scripts/packages/<ID>/…` and its tarball at `/sources/…`, which is exactly
where every recipe already looks — so no recipe changes at all, and "sources
become a search path" turns out not to be a search path but one more `cp`.

Build order is the sorted file name, which is sufficient for recipes appended
after everything the book builds, and `make deps-verify` is what says so. A
staged recipe with an empty `# BUILD_REQUIRES:` is **refused** (finding 6): an
empty declaration is a node with no edges and the resolver may place it before
the compiler. Two of the four recipes moving have exactly that defect today, so
this check has work to do at order 7.

The path resolution moves into `scripts/resolve-distro.sh` because
`build-distro.sh` and `build-distro-packages.sh` must agree about it, and two
copies of a resolution rule are two rules.
**proves it:** `make distro-packages DISTRO=minimal` reports that minimal
brings no recipes and does nothing; a recipe with an empty `BUILD_REQUIRES` is
refused by name.

### lfs [order 6a] — the DISTRO_ONLY rules are enforced
files: `scripts/packages/query-deps.sh`, `scripts/image/build-image.sh`
change: `query-deps.sh check` gains the rules `DISTRO_ONLY:` only documents
today — at most one kernel per distro, and a `DISTRO_ONLY` package claimed only
by the distro it names (finding 9). `build-image.sh:63` refuses two kernels
rather than picking the lexically first. Catching it at `deps-check` costs a
second; catching it at image time costs the hours of build before it.
**proves it:** a distro naming two kernels fails `make deps-check`.

### lfs + inteliboy [order 7] — the move. **Lands as one commit pair.**
files, leaving lfs:

    distros/inteliboy/                              → distros/inteliboy/
    scripts/packages/blfs/x-make-avatari.sh         → distros/inteliboy/packages/
    scripts/packages/blfs/x-make-avatari-heads.sh   → distros/inteliboy/packages/
    scripts/packages/blfs/x-make-avatari-voices.sh  → distros/inteliboy/packages/
    scripts/packages/lfs/10.3-make-linux-kernel-inteliboy.sh → distros/inteliboy/packages/
    sources/kernel-inteliboy-6.16.config            → distros/inteliboy/sources/
    the three avatari-* lines of sources/local.md5sums → distros/inteliboy/sources/local.md5sums

change: on the lfs side, nothing to delete — the InteliBoy lines in
`build-packages.sh` were never committed (order 1) and the files were never
tracked (finding 1). The kernel recipe's `BUILD_REQUIRES` is declared as it
moves: compiler, binutils, make, bc, flex, bison, perl, kmod. Here, a
`.gitignore` for `distros/inteliboy/sources/*.tar.*` — the checksums and the
kernel config are committed, the tarballs never are.
**proves it:** `grep -ri inteliboy ../lfs` is empty and stays empty. `make
distro && make image` from this repository, then **boot it in qemu**.

### inteliboy [order 8] — sshd in the distro ✅
files: `distros/inteliboy/packages.list`, `distros/inteliboy/files/etc/ssh/sshd_config` (new)
change: add `4-make-openssh.tar.gz` to the package list — already built, and its
runtime closure (openssl, libxcrypt, zlib, glibc) is entirely in `core`, so
nothing else is pulled in. Ship a complete `sshd_config` setting
`PermitRootLogin yes` and `PasswordAuthentication yes`, because the stock file's
defaults refuse both and it has no `Include` (finding 12). The root password
stays `toor` from lfs's `.env` (decision 9). `qemu.sh` gains
`hostfwd=tcp::2222-:22`, without which the daemon cannot be reached to test at
all.
**proves it:** `ssh -p 2222 root@localhost` into the booted image, with the
password, and `ssh-keygen -lf` shows a fingerprint that differs from a second
image built the same way.

### inteliboy [order 9] — `make stage` ✅
files: `Makefile`, `tools/stage.sh`, and a `version` target in avatari
change: runs avatari's `make dist` **and** `make dist-assets` — three tarballs,
not one, and the voices one is conditional — copies them into
`distros/inteliboy/sources/`, and **rewrites `local.md5sums` itself**. Then the
three avatari packages are rebuilt from them, because the cache holds a build
of `g6458162` and the image takes whatever HEAD is (decision 10). This is
the `make avatari-sources` that `x-make-avatari.sh:26` has always claimed
exists. `docs/DEVELOPMENT.md:578` proposed this as `make sources PROJECT=...`
inside lfs; it belongs here instead, in the repository that knows what its
components are, and that line should be updated to say so.
It asks each component for its version rather than re-deriving how one is
named — which is why avatari gained the same `make version` target reflexi did.
Tarballs for any other version are removed from `sources/`, because the recipes
glob `<name>-[0-9]*` and two archives would hand `tar` the wrong one.
**proves it:** `make stage` produced `avatari-0.1.0-dirty.tar.xz`,
`avatari-heads-0.1.0-dirty.tar.xz` and `avatari-voices-0.1.0-dirty.tar.xz`,
removed the `g6458162` ones, and rewrote `local.md5sums` to match. The
`-dirty` is correct and deliberate: avatari's tree carries the uncommitted
`version` target from `changes/2026-08-31-semver/`.

### inteliboy [order 10] — pin
files: `versions.lock` (new), `docs/lfs-products.md`, `docs/DEVELOPMENT.md:17,578`, `.claude/agents/lfs.md`
change: `make lock`. Rewrite `docs/lfs-products.md` — it is built end to end on
the `PRODUCT` noun this change dropped, so it is a rewrite, not an edit, and it
should probably be renamed. Fix `DEVELOPMENT.md:17` ("lfs … the image, and
every package in it") and `:578`. Point `.claude/agents/lfs.md` at
`distros/inteliboy/` instead of `image/`.
**proves it:** `versions.lock` names an lfs revision that built the image that
booted.

## Honesty about verification

Stated in the words `CLAUDE.md` §7 asks for.

- **lfs's `test` is `make deps-verify && make deps-check`.** Those are
  structural checks on the dependency graph. They cannot tell us the image
  boots. `docs/DEVELOPMENT.md:528` already says this.
- **avatari's `test` compiles it and checks its config.** "avatari compiled"
  and "avatari works" are different sentences. Nothing in this change touches
  avatari's code, but the move changes how its tarballs reach the image, and
  nothing proves that end to end except an image that boots.
- **cogiti and this repository have no test command at all.** They cannot
  currently tell us we broke them.
- **Therefore: nothing in orders 0–6 proves the appliance still boots.** The
  only evidence is the qemu boot at order 7, run by hand, once. It is the gate,
  not a formality, and if it is skipped this change is unverified regardless of
  what every other `proves it` reports.
- `scripts/image/qemu.sh` uses a bare `-netdev user` with no `hostfwd`, so the
  booted image cannot be reached from the host. Order 8 adds it; without it
  the sshd half of this change cannot be tested at all.
- **Decision 7 removes the safety net.** Normally a step that breaks something
  is found by the step that follows it. Here every order is uncommitted until
  the end, so a regression introduced at order 2 surfaces at the order 7 boot
  with six orders of changes to search. The file lists above are the mitigation
  and they are not a strong one.

16. **Two defects blocked sshd and were fixed here; the cause is filed
    separately.** The appliance shipped `/sbin/dhcpcd` with no `dhcpcd` user
    and would have shipped one ssh host key shared by every device. Both are
    instances of one lfs defect — a rebuilt package silently ships fewer files
    — written up in `changes/2026-08-31-lfs-package-diff-shrink/`. What this
    change carries is the repair: `14-make-dhcpcd` and `4-make-openssh`
    rebuilt so their packages carry their accounts, the host keys removed from
    the openssh package and generated by its boot script on first start, and
    `distros/inteliboy/files/etc/ssh/sshd_config` replacing the stock one so
    root can log in at all.

17. **A successful build can be discarded by its own cleanup — fixed here,
    unplanned.** `scripts/packages/11-unmount-vkfs.sh` is best effort and says
    so with `set +e`, but it still exits with the status of its last `umount`.
    `build-package.sh:132` re-arms the `ERR` trap immediately before calling
    it, so one already-unmounted `/sys` aborts the build *after* the compile
    succeeded and *before* `tar` runs. The kernel built correctly — its log
    ends `kernel 6.16.1-inteliboy installed` — and the package was never
    written; twenty minutes of work lost to a `umount`.

    Fixed by ending that script with an explicit `exit 0`, which is what
    `set +e` already meant. **This was not in the brief.** It blocked order 7
    and is recorded here rather than tidied away; it belongs with the other
    defects in `changes/2026-08-31-lfs-package-diff-shrink/`, whose subject is
    the same code path's error handling.

## Not in this change

- Generating `build-packages.sh` from declarations (finding 7).
- The 5.19-config-on-6.16-source defect (finding 11). Real, adjacent, and it
  wants its own change — it is a live correctness bug in lfs's generic kernel
  recipe, and filing it here as a bullet is how it gets forgotten.
- The five empty `BUILD_REQUIRES` in recipes that stay in lfs (finding 6).
  Order 5 refuses empty declarations only for staged-in recipes.
- A second distro, `inteliboy-dev` or a release variant (decision 5).
- The writable data partition. Required before services ship.
- Making the root password settable per distro (decision 9).
- The lfs defect behind the missing accounts and shared host keys — proposed in
  `changes/2026-08-31-lfs-package-diff-shrink/`, not applied.
- The other three distros' images, which also ship the shared host keys of
  finding 13. Order 3 fixes the cause for all of them; rebuilding their images
  is not this change's business.

## Rollback

Until the commits are written (decision 7) rollback is `git checkout -- .` plus
deleting untracked files, and the record of what to keep is this brief. In lfs
that is the user's call to make as much as the commits are. After
they are written: branch `inteliboy-out-of-lfs` in lfs and here, delete both.
Order 7 is the only one that crosses repositories, and the files it moves are
untracked in lfs today, so reverting it is moving them back. No `versions.lock`
entry to restore — the file does not exist yet; order 10 creates it.

The one irreversible thing is order 3: it requires rebuilding the openssh
package, which overwrites `packages/4-make-openssh.tar.gz`. Keep the old one
until the image boots.
