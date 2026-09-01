# Building someone else's product

A proposal. Today lfs is a tool that happens to contain one of its users.
Making that user external costs less than it looks, because most of the
machinery is already generic — and one piece of it, the dependency ordering,
is *already* the right answer and is only waiting to be used.

The goal, in one sentence: **lfs becomes a tool for building a custom image,
and InteliBoy becomes a client of it**, holding everything about itself in its
own repository, with its own history and its own release cadence.

---

## 1. What is InteliBoy's, inside lfs, today

Five things, in three different mechanisms. The count is what matters: a
single `--distro-dir` flag would move the first one and leave the other four
behind, which is worse than not starting, because it would look done.

| what | where | why it is not lfs's |
|---|---|---|
| the distro definition | `distros/inteliboy/` — `distro.conf`, `packages.list`, `files/etc/{inittab,avatari.conf,rc.d/init.d/avatari}`, `check.ignore` | describes one appliance |
| the application recipes | `scripts/packages/blfs/x-make-avatari.sh`, `-heads.sh`, `-voices.sh` | builds one project's own software |
| a product kernel | `scripts/packages/lfs/10.3-make-linux-kernel-inteliboy.sh`, `sources/kernel-inteliboy-6.16.config` | one appliance's hardware and drivers |
| the build order entries | `scripts/packages/build-packages.sh` lines 119 and 261–263 | a generic list naming a specific product |
| the source checksums | `sources/local.md5sums` — three `avatari-*` lines | checksums of one project's tarballs |

There is a sixth, invisible one: the hand-off itself. `x-make-avatari.sh:26`
says the tarballs are produced "by `make avatari-sources`, which runs avatari's
own `make dist` and copies the tarballs here" — **and that target does not
exist in the Makefile.** The step is a manual `make dist`, a manual copy, and a
manual edit of `local.md5sums`. Externalising the product is also the
opportunity to make that step belong to somebody.

## 2. The shape: a product directory

A **product** is one directory, owned by its own repository, holding everything
the five rows above hold. lfs is pointed at it and builds it.

```
inteliboy/image/                    ← in the InteliBoy repo
  product.conf                      identity, kernel cmdline, strip, image size
  packages.list                     what to install on top of core
  files/                            the rootfs overlay
  check.ignore
  packages/                         product package recipes
    x-make-avatari.sh
    x-make-cogiti.sh
    10.3-make-linux-kernel-inteliboy.sh
  sources/                          product tarballs and their checksums
    local.md5sums
    kernel-inteliboy-6.16.config
  stage                             produces sources/ from the sibling repos
```

`product.conf` is today's `distro.conf` — the identity block, `STRIP`,
`GRUB_TIMEOUT`, `KERNEL_CMDLINE` — unchanged. The word *product* is used for
the bundle because it is more than a distro definition now: it also carries
recipes and sources. Inside it, a distro is still a distro.

The three other distros in `distros/` — `minimal`, `full`, `minimal-desktop` —
stay exactly where they are. They are lfs's own examples and its test matrix,
and a tool with no worked examples is harder to use, not cleaner. `core`
certainly stays: it is the shared base every product builds on, which is lfs's
own content by definition.

## 3. Three extension points, one of which is free

**a. The distro directory.** `build-distro.sh` hardcodes

```sh
DISTRO_DIR="$BASE_DIR/distros/$distro"
```

Change to: an absolute or relative path in `$PRODUCT` is used as-is; a bare
name still resolves under `distros/`. Everything downstream of that line is
already generic — the package list merge, the file policy, the identity files,
the overlay copy, the stripping. `check-distro.sh` and `build-image.sh` take
the same treatment. This is a few lines in three scripts.

**b. The package recipes — and the ordering, which is already solved.**

`order-deps.sh` globs

```sh
for f in scripts/packages/*/*-make-*.sh scripts/packages/*/[0-9]*-*.sh
```

and derives an order from the `# BUILD_REQUIRES:` and `# REBUILD_AFTER:`
declarations in the scripts themselves. It already allows the `x-` prefix
explicitly, "because packages which are not in the book are named
`x-make-<name>`, and a glob anchored on `[0-9]` would leave them out of the
graph without saying so".

**So a product's recipes need no position in any list.** Stage them into
`scripts/packages/<product>/` for the build, and the existing resolver places
them from their own declarations. `make deps-verify` then checks the result,
which is a stronger guarantee than the hand-maintained order gives today.

What this asks for in return is *not* that `build-packages.sh` becomes
generated. Measured: only **11 of 102** scripts under `scripts/packages/lfs/`
and **43 of 136** under `blfs/` carry a `# BUILD_REQUIRES:` line at all. For
the book packages the authority on order is the book's chapter order, and no
resolver can derive that from a graph which is mostly empty.

The workable version is narrower and safer: the hand-ordered list stays the
authority for everything lfs ships, and the resolver is used only to **place
appended product packages** relative to it, with `make deps-verify` checking
the result. Product recipes are the one set where full declarations can be
required, because they are new and there are few of them.

The kernel needed thought and has now had it — see §8. It moves, and the
decision to make it per-distro was already taken; what is left is where the
recipe lives.

**c. Sources and checksums.** `sources/local.md5sums` is checked by each recipe
with `grep " avatari-[0-9]" local.md5sums | md5sum -c -`. Make the sources
directory a search path rather than one directory: lfs's own `sources/` plus
the product's. The recipe's check is unchanged; only where the file is found
moves.

And give the product a `stage` script that runs each component's `make dist`,
copies the tarballs in, and **rewrites `local.md5sums` itself**. That is the
missing `make avatari-sources`, living where it belongs: in the repo that knows
what its components are.

## 4. Where the artifacts go

Today `rootfs/`, `image.img` and `image.img.nvram` are written into the lfs
working copy, and `make distro` refuses to overwrite a rootfs that has not been
archived — a guard that exists precisely because one directory is shared by
every distro.

Give the output a home per product:

```
OUT ?= build/$(PRODUCT)
    $(OUT)/rootfs/
    $(OUT)/image.img
    $(OUT)/image.img.nvram
```

with `OUT` overridable, so InteliBoy can point it into its own tree or at a
scratch disk. Two products can then be built side by side, and the
"already holds another distro" guard becomes a much rarer conversation.

**What stays in lfs, deliberately:** the toolchain tarball, the built package
cache (`packages/`), and the upstream sources. They are generic, they are
expensive — hours and tens of gigabytes — and they are shared by every product.
A second product should cost the base build zero. That is the whole economic
argument for lfs being a tool.

| generic and expensive → stays | product-specific → moves out |
|---|---|
| `lfs-tools-*.tar.gz`, the toolchain | the distro definition |
| `packages/`, the built base packages | the product's own recipes |
| `sources/` upstream tarballs and wget lists | the product's tarballs and checksums |
| `scripts/`, the whole pipeline | the product kernel and its config |
| `distros/core` and the example distros | the output image |

## 5. The interface, once it exists

```sh
# in the InteliBoy repo
make image                      # runs, underneath:

lfs$ make packages              # once, shared by every product
lfs$ make distro   PRODUCT=/path/to/inteliboy/image
lfs$ make check    PRODUCT=/path/to/inteliboy/image
lfs$ make image    PRODUCT=/path/to/inteliboy/image OUT=/path/to/inteliboy/build
lfs$ make qemu     OUT=/path/to/inteliboy/build
```

lfs never mentions InteliBoy. InteliBoy never contains a package build system.
The seam is one directory and one variable.

A product declares which lfs it was built with, in `product.conf`:

```
LFS_VERSION=12.4
LFS_MIN_REV=f431d8f
```

so a product that needs an extension lfs does not have yet fails with a
sentence instead of a strange error — the same discipline as avatari's `hello`
capability reply, applied to a build tool.

## 6. Migration, in steps that each leave lfs working

The house rule from every other repo here: each step is shippable, and
`make distro DISTRO=inteliboy` keeps working until the last one.

1. **`PRODUCT` resolves a path.** `build-distro.sh`, `check-distro.sh`,
   `build-image.sh`. A bare name still means `distros/<name>`. Nothing moves
   yet; prove it by building inteliboy from `distros/inteliboy` given as a full
   path.
2. **`OUT` per product.** Default `build/$(PRODUCT)`, with the current paths as
   the fallback so nothing in muscle memory breaks.
3. **Sources become a search path.** Two directories, then N.
4. **Generate `build-packages.sh` from `order-deps.sh order`**, and make
   `deps-verify` a build-time check rather than a manual one. This is worth
   doing on its own merits and it is what makes step 5 free.
5. **Product recipes are staged in.** `scripts/packages/<product>/` is
   populated from `$PRODUCT/packages/` before the build; the glob and the
   resolver already handle it. `update-scripts` needs to copy it into
   `$LFS_BASE` alongside `scripts/`.
6. **Move `distros/inteliboy/`, the three `x-make-avatari*` recipes, the
   inteliboy kernel and its config, and the three `avatari-*` checksum lines**
   into the InteliBoy repo. Delete the four lines from `build-packages.sh` —
   which by now is generated, so there is nothing to delete.
7. **Write `stage`** in the product, replacing the manual tarball copy and the
   `local.md5sums` edit, and give it the `make dist` calls for every component.
8. **A second product**, even a trivial one, built from an external directory.
   Until something other than InteliBoy has been built this way, the tool is
   not proven agnostic — it is only rearranged.

## 7. What this buys, beyond tidiness

- **A product's history is its own.** "Which kernel config, which package list,
  which init script shipped in 0.3" is answered by the InteliBoy repo's log,
  not by correlating two repositories by date.
- **lfs can be updated without touching the product**, and a product can be
  pinned to an lfs revision it is known to build under.
- **The base build is shared.** A second appliance costs the hours once.
- **The source hand-off gets an owner** — the step that today is a manual copy
  and a hand-edited checksum, and is the most likely way to ship a stale binary
  into an image.
- **lfs becomes publishable.** A general LFS build tool with a product
  extension point is something other people can use; a build tool with one
  customer's appliance inside it is not.

---

## 8. The kernel, specifically

Checked, because it is the one package whose position looked load-bearing.
It is not, and the decision to make it per-distro has already been taken —
what is left is where the recipe lives.

**What is already true:**

- `distros/core/packages.list` deliberately omits the kernel: "The kernel
  itself is NOT here... Each distro names the kernel package it wants in its
  own list." All four distros do.
- `# DISTRO_ONLY:` exists as a marker, and `list-runtime-packages.sh` says it
  was invented for exactly this: "The per-distro kernels are the case this
  exists for — every distro needs a kernel and no distro needs two, so the
  variants cannot be handed to whoever asks for everything."
- **Nothing declares a dependency on a kernel package.** `BUILD_REQUIRES`,
  `RUNTIME_REQUIRES` and `REBUILD_AFTER` across every script: no hits for any
  kernel. It is a leaf.
- Nothing in the blfs half consumes kernel build output. The cpu microcode is
  assembled as an early initrd at *image* time (`build-image.sh:218`), from
  files in the rootfs, not from a build-order edge.
- Its position at line 119 of roughly 290 is inherited from the LFS book's
  chapter order, not from a requirement. The whole blfs section is built
  after it.

**Three things to fix before moving it:**

1. **The declarations are empty.** `10.3-make-linux-kernel-inteliboy.sh:40-41`
   is literally `# BUILD_REQUIRES:` and `# RUNTIME_REQUIRES:` with nothing
   after them, and `10.3-make-linux-kernel.sh` has no declaration at all.
   Harmless while the order is hand-written; actively dangerous the moment a
   resolver places the package, because a node with no edges can be placed
   before gcc. Declare what it actually needs — the compiler, binutils, make,
   bc, flex, bison, perl, kmod for `modules_install` — before relying on
   automatic placement.
2. **`build-image.sh:63` picks the kernel by `ls /boot/vmlinuz* | head -1`.**
   One kernel per rootfs is what makes that safe today, which is a good reason
   to keep the per-distro rule rather than an argument against it. It should
   still refuse on finding more than one instead of picking the lexically
   first.
3. **`DISTRO_ONLY:` is documentation, not enforcement.** Nothing checks that a
   distro names at most one kernel, or that a `DISTRO_ONLY` package is claimed
   only by the distro it names. `query-deps.sh check` is where that belongs.

**A separate defect found while checking.** `sources/` holds
`kernel-5.19.2.config` and `kernel-inteliboy-6.16.config`, and the wget list
ships `linux-6.16.1.tar.xz`. The generic recipe copies the **5.19.2** config
onto a 6.16.1 source tree and then runs plain `make`, with no
`olddefconfig` — so every symbol added to the kernel in four years is resolved
by whatever the build decides, unreviewed. The InteliBoy recipe does this
correctly: its own config, then `scripts/config` for the divergences, then
`make olddefconfig`. This is worth fixing on its own, and it is also an
argument for the move: a recipe and the config it uses drifted apart because
they live in different directories with nothing tying them together.

**What "per-distro" should mean here.** Not one recipe per distro — three of
the four distros share the generic one and should keep sharing it. lfs ships a
**default kernel recipe** for its own example distros; a product may bring its
own, carrying its config beside it:

```
inteliboy/image/
  packages/10.3-make-linux-kernel-inteliboy.sh
  sources/kernel-inteliboy-6.16.config
```

Placement then needs nothing clever. The kernel has no dependents, so appending
it after everything lfs builds is correct by construction — and with the
declarations from fix 1 in place, it is correct by derivation too.
