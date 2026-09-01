# 2026-08-31-appliance-sshd — sshd on the appliance

Status: **draft — not approved. One design question must be answered first.**
Written by: a prior session, from direct inspection.
Approved by: —

## The ask

The appliance has no sshd. It went missing when the InteliBoy distro was scoped
down — the list was computed from the avatari and grub closure, and openssh was
never in it. `minimal`, `full` and `minimal-desktop` all ship it; inteliboy
never did.

## The question to answer before anything else

**Should sshd be in the shipping appliance, or in a development variant only?**

`distros/inteliboy/files/etc/inittab` describes a deliberately sealed device:
no getty on tty1, rescue reachable only through a hidden GRUB entry. A
listening port with root login, and `ROOT_PASSWORD` coming from `.env` into the
image, is a different threat model than that comment implies.

- If this is a **development and administration affordance**, the clean answer
  is a second product — `inteliboy-dev` — which also demonstrates why
  per-product distro definitions are worth having.
- If it is a **product feature**, that is a reasonable call for a device you
  own; it just deserves to be a decision rather than a side effect. Then the
  host key story and the root password story both need an answer.

**Answered 2026-08-31**, by decision 5 of
`changes/2026-08-31-inteliboy-out-of-lfs/`: there is one distro, and it is a
development one until it is good enough to spawn a release variant. So sshd
goes in it, and the host key and root password questions below are the ones
that remain. There is no `inteliboy-dev` to defer it to.

## The seam

None. This is a package list entry, not a contract change.

    owner:     lfs today; this repository after 2026-08-31-inteliboy-out-of-lfs
    consumers: —

Ordering against the split is free: one line either way. Before the split it is
`lfs/distros/inteliboy/packages.list`; after, it is `image/packages.list`.

## Findings

| | |
|---|---|
| the change | one line — `4-make-openssh.tar.gz` |
| rebuild needed | **no.** `packages/4-make-openssh.tar.gz` is already built |
| runtime closure | openssl, libxcrypt, zlib, glibc — **all four already in `core`** |
| boot script | ships with the package; the recipe runs `make install-sshd` from blfs-bootscripts at build time |
| host keys | **not baked in.** No `ssh-keygen` in the recipe, so the bootscript generates them on first start — correct for an appliance, since a baked key would be shared by every device. Verify it actually happens on first boot |
| `/etc/passwd` | the recipe adds an `sshd` user. This is precisely the case `build-distro.sh`'s account-merge logic was written for, so it should be fine — but it is the first thing to check if login breaks |

## Per repo

### lfs *or* inteliboy [order 1] — one line
Add `4-make-openssh.tar.gz` to the product's `packages.list`, in build order.
**proves it:** `make distro && make check`, then boot in qemu and reach it. The
qemu invocation has no `hostfwd` today (`scripts/image/qemu.sh` uses a bare
`-netdev user`), so add `hostfwd=tcp::2222-:22` to test it at all — which is
itself worth keeping.

## Not in this change

- The `hostfwd` line as a permanent change to `qemu.sh` (worth its own,
  trivial, change).
- Key-based authentication, a non-root admin account, or locking the root
  password. All follow from the design question above.

## Rollback

Delete the line. Nothing else changes.
