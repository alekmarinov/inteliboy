# 2026-08-31-awk-in-core — every distro gets awk, and the package actually carries it

Status: **applied to lfs's working tree — awaiting your commit**
Approved by: Alexander Marinov, 2026-08-31 ("We must add awk in lfs/core")

## The ask

`awk` should be on every distro. It was missing from the appliance, found while
reading the state of the device at 192.168.1.178 — two status commands failed
with `awk: command not found`.

## The seam

    contract:  distros/core/packages.list — what every distro always installs
    owner:     lfs
    consumers: core, minimal, full, minimal-desktop, and InteliBoy
    breaking:  no. One package added to the base every distro already installs.

## Findings

1. **Only `full` listed gawk.** `minimal`, `minimal-desktop` and InteliBoy had
   no awk at all. InteliBoy's list is the runtime closure of avatari and grub,
   and nothing in that closure links awk, so it was never pulled in.

2. **Adding the package to core would not have been enough.** The built
   `8.61-make-gawk.tar.gz` contained `./usr/bin/gawk` and `./usr/bin/gawkbug`
   and **no `./usr/bin/awk`**. gawk's own `make install` creates that symlink,
   and it has been sitting in `overlay/base/usr/bin/awk -> gawk` since
   2026-08-29 without appearing in any package since.

   This is a third instance of
   `changes/2026-08-31-lfs-package-diff-shrink/`, found by a completely
   different route from the first two: a package is the diff of its build, and
   a link `make install` skips because the base already has it is not in the
   diff. Every distro that installed gawk got gawk and no awk.

3. **`make deps-verify` was already failing before any of this.** Three
   declarations are unsatisfied by the build order:

       8.9-make-lz4        built at 16, needs 8.69-make-make, built at 76
       8.19-make-pkgconf   built at 26, needs 8.69-make-make
       8.27-make-libxcrypt built at 34, needs 8.69-make-make

   Verified against the **committed** `build-packages.sh`, where `make` sits at
   75 and the three at 16/26/34 — the same failure, so it is not caused by this
   change or by `2026-08-31-inteliboy-out-of-lfs`. `components.toml` gives lfs's
   test as `make deps-verify && make deps-check`, so **lfs's own test command
   fails today and has been failing.** Out of scope here; recorded because a
   red test that was already red is how a real regression gets missed.

## Per repo

### lfs [order 1] — the recipe creates the link explicitly ✅
files: `scripts/packages/lfs/8.61-make-gawk.sh`
change: `ln -sfv gawk /usr/bin/awk` after the install, and a `test -L` that
fails the build if it is absent. `ln -sf` replaces the link whether or not it
is there, so it always writes and is therefore always in the diff — immune to
whatever the base layer happens to hold. The comment says why it is explicit
rather than left to `make install`.
**proves it:** the rebuilt package carries `./usr/bin/awk`, `./usr/bin/gawk`,
`./usr/bin/gawkbug`.

### lfs [order 2] — core installs it ✅
files: `distros/core/packages.list`, `distros/full/packages.list`
change: `8.61-make-gawk.tar.gz` added to `core`, after coreutils, and removed
from `full`. `full` and `core` had zero overlapping entries before this, so
re-listing a core package there would have broken that convention.
**proves it:** `make deps-check` — `full`, `minimal` and `minimal-desktop` all
still closed.

## Not in this change

- The three unsatisfied declarations of finding 3. They are lfs's own and
  predate this work; fixing the book order is a separate question.
- The cause behind finding 2 — proposed in
  `changes/2026-08-31-lfs-package-diff-shrink/`, still unapplied.
- **Rebuilding the appliance image.** The image at `build/image.img` and the
  machine at 192.168.1.178 do not have awk. They get it on the next
  `make distro && make image`, which is what you said.

## Rollback

Revert two `packages.list` entries and the recipe; rebuild
`8.61-make-gawk`. The package the rebuild replaced is the one missing the
symlink, so there is nothing worth restoring.
