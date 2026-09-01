# lfs, the build tool

**This describes a repository that is not ours to own.** lfs sits beside this
one at `../lfs`. It carries no file of ours — no `CLAUDE.md`, no agent
configuration, nothing addressed to a session. What a session needs to know
about it is written here instead, in the repository that consumes it.

A build tool. It compiles Linux From Scratch 12.4 plus BLFS 11.2 from source,
one package at a time in isolation, archives each as a tarball, and assembles a
selection of those tarballs into a bootable image.

It is a **tool**, not a component of anything. It takes a distro definition
from outside and builds it, the way a compiler takes a source tree. Its one
consumer today is InteliBoy, which lives in another repository and holds its
own distro.

    sudo make packages              build every package from source, once
    make distro DISTRO=<name|path>  assemble a distro into rootfs/
    make check                      resolve every binary against its libraries
    make image                      turn rootfs/ into a bootable image
    make qemu                       boot it

`make packages` takes hours, needs root and docker, and produces tens of
gigabytes. Everything after it is minutes, because it works from the archived
packages rather than from source. Preserving that split is most of what this
repository is for: a second distro must cost the base build nothing.

## Hard boundaries

These are not advisory.

**1. Nothing belonging to a consumer appears in here.** Not a package list, not
a recipe, not a config, not a kernel, not a string in a script, not a comment
naming someone's laptop.

    grep -ri inteliboy .        # must come back empty

A distro that describes something we ship lives in that thing's repository.
The four distros here — `core` and the three examples — are lfs's own, and
`core` is the shared base every distro installs.

When something looks like it needs an lfs change, it is usually a distro
change: a package list, an overlay file, a recipe, a config. Those belong to
the consumer. The lfs change is only the one that no distro directory could
express.

**2. The book's chapter order is the authority on build order.**
`scripts/packages/build-packages.sh` is hand-ordered and stays that way. Only
11 of 102 recipes under `scripts/packages/lfs/` and 43 of 136 under `blfs/`
declare `# BUILD_REQUIRES:` at all, so a resolver cannot derive the order from
a graph that is mostly empty. `order-deps.sh` exists to *place appended
recipes* — a consumer's own, staged in — and to verify, not to own the list.

An empty `# BUILD_REQUIRES:` is worse than an absent one: a node with no edges
can be placed before gcc. Recipes staged in from a distro must declare theirs.

**3. A package is built in isolation and must not reach outside it.** Sources
come from `sources/` (and from the distro's own `sources/`), verified against a
checksum list. Nothing fetches at build time; nothing reads the host.

**4. Secrets are never written into a package.** A package tarball is a build
artifact that gets copied into every image. `ssh-keygen -A` running during
`make install` is the case this rule was written for.

**5. We edit lfs. We do not commit it.** The orchestrator session makes the
changes an approved brief calls for, and then stops: it proposes the commit
message and the user commits. No agent writes there at all — the `lfs` agent
has read tools only. The failure this prevents is an agent, or a session,
patching the build tool in passing to unblock itself and writing that into
someone else's history.

## Layout

    scripts/packages/       the pipeline: build, order, query, install
    scripts/packages/lfs/   102 recipes, LFS book order
    scripts/packages/blfs/  136 recipes. 'x-make-<name>' is a package not in
                            the book; the resolver allows that prefix explicitly
    scripts/image/          build-distro, check-distro, build-image, docker, qemu
    distros/core/           the shared base. Always installed. Names no kernel
    distros/{minimal,full,minimal-desktop}/   the examples, and the test matrix
    sources/                upstream tarballs, wget lists, checksums
    packages/               the built package cache. Expensive, shared, generic
    .env                    versions, paths, JOB_COUNT, LFS_ROOT_PASSWORD

A distro directory is `distro.conf` (identity, `STRIP`, `GRUB_TIMEOUT`,
`KERNEL_CMDLINE`), `packages.list`, `files/` overlaid onto the rootfs, and
`check.ignore`. It may also carry `packages/` and `sources/` of its own.

Each distro names its own kernel. `core` deliberately does not: every distro
needs one and none needs two, which is what `# DISTRO_ONLY:` marks.

## What the tests actually prove

    make deps-verify     the build order satisfies the declared dependencies
    make deps-check      every distro's package list closes over its runtime
    make check           every binary in rootfs/ resolves against its libraries

These are structural. **None of them says the image boots.** There is no test
here that does. An image that has not been booted has not been verified,
however green the checks are — say so in those words rather than implying more.

## Conventions

- Recipes are `#!/bin/bash`, `set -e`, and end a build chain with `|| exit 1`,
  because a failing `&&` chain does not trip `set -e` and the package would be
  recorded as passing while containing nothing.
- Comments explain *why*, especially where a line looks arbitrary. Much of the
  hard-won knowledge here is in them.
- Configuration files are read with `sed`, not sourced. Sourcing lets a config
  file set anything in the script that reads it.

## Known-stale

- `README.md` says LFS 11.2. The repository was ported to 12.4 (commit
  `f431d8f`); BLFS is still 11.2. The README needs updating.
