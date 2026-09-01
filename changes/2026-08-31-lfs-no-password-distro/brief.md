# 2026-08-31-lfs-no-password-distro — a distro states its password, or gets none

Status: **applied to lfs's working tree — awaiting your commit**
Approved by: Alexander Marinov, 2026-08-31 — "I don't mind to remove toor
password from .env", and "find a way to resolve this quickly, if not in the
best way, document it for future work".

> lfs is a tool. The orchestrator edits it; the user commits.

## The ask

An appliance authorised by ssh key should carry no password at all.

## What was wrong, and how it hid

`/etc/shadow` is a **shared file**. A package is the diff of its build, so a
package that touches shadow captures the *whole file*, not its own line —
including whatever root's hash was at that moment.

`4-make-shadow.sh` sets a root password at package-build time from
`LFS_ROOT_PASSWORD`. Every package built after that carries a copy:

    4-make-shadow      root:$6$2Dze1xrUgpfFIhK3$hX…
    14-make-dhcpcd     root:$6$2Dze1xrUgpfFIhK3$hX…
    4-make-openssh     root:$6$2Dze1xrUgpfFIhK3$hX…   installed by the appliance
    8.85-clean         root:$6$2Dze1xrUgpfFIhK3$hX…   installed by the appliance

Verified: that hash is `toor`.

`build-distro.sh`'s "no password configured" branch **wrote nothing** and
printed *"the root account stays locked"*. Both halves were false. The account
was not locked — the merge had faithfully restored a working password from
`4-make-openssh` and `8.85-clean`, neither of which is the shadow package and
neither of which the appliance chose for its accounts. So an appliance that
configured no password shipped one, and the build said the opposite.

Emptying `.env` did not help: the hash never came from `.env` at assembly time,
it came from the packages.

## The fix, and what it costs

**The password becomes a property of the distro, and the no-password case is
written rather than skipped.** The same move made earlier for `IMAGE_SIZE`, for
the same reason: a property of the distro does not belong in the build host's
`.env`.

### lfs [order 1] — the else branch writes `*` ✅
files: `scripts/image/build-distro.sh`
change: when no password is configured, actively write `root:*:` instead of
leaving whatever the packages carried, and replace the false message with one
that says what is true — no password authenticates root anywhere, key logins
are unaffected, use `--autologin` for a console, `init=/bin/bash` is the last
resort.

`*` rather than `!`, measured: sshd built without linux-pam treats a
`!`-prefixed field as a locked *account* and refuses **public key** logins too,
which would make a key-authorised appliance unreachable. `*` denies every
password and leaves keys working.
**proves it:** the appliance assembles with `root:*`; ssh by key succeeds and
by password fails; the boot reaches a root shell via autologin.

### lfs [order 2] — the examples state their own password ✅
files: `distros/{minimal,full,minimal-desktop}/distro.conf`
change: `ROOT_PASSWORD=toor` in each, with a note saying why it lives there.
Without this, order 1 would silently take their password away and leave them
reachable only through `init=/bin/bash`.
**proves it:** `make distro DISTRO=minimal` still sets a password.

### lfs [order 3] — `.env` no longer names a password ✅
files: `.env`
change: `LFS_ROOT_PASSWORD` removed. Nothing global sets a password now.

### lfs [order 4] — a package stops baking one ✅
files: `scripts/packages/blfs/4-make-shadow.sh`
change: set the password only when one is configured, rather than feeding
`passwd` two empty lines — and say in the comment why baking a hash into a
package is the same class of mistake as shipping ssh host keys.

**This does not clean the existing packages.** The four listed above still
carry the old hash and will until they are rebuilt. It does not matter for an
assembled rootfs any more, because order 1 overwrites the field either way —
but the hash is still in the cache. See "For future work".

## What was applied outside lfs

`distros/inteliboy/`, and verified by booting the image:

- `files/root/.ssh/authorized_keys`, 0644 — sufficient, measured.
  `StrictModes` tests `mode & 022`; git records only the executable bit, so
  0600 would not survive a clone anyway.
- `files/etc/ssh/sshd_config` — `PermitRootLogin prohibit-password`,
  `PasswordAuthentication no`, `PermitEmptyPasswords no`.
- `agetty --autologin root` on tty2, tty3 and both console fallbacks in the
  renderer's init script. Verified: `inteliboy login: root (automatic login)`
  and a shell, nothing typed.

The flashable image now reads: `root:*`, no host keys, the key authorised,
two autologin gettys, `console=tty3`, `awk -> gawk`.

## For future work

Known-imperfect, deliberately, because the quick path was taken:

1. **Four packages still carry a `toor` hash in their `/etc/shadow`.** Harmless
   now — order 1 overwrites the assembled field — but it is a secret in a build
   artifact. It clears only when those packages are rebuilt, and rebuilding
   them has its own hazard: see
   `changes/2026-08-31-lfs-package-diff-shrink/`, which this is now a **fifth**
   instance of.

2. **The overlay cannot state a mode.** Adding `files/root/.ssh/` silently
   widened `/root` from 0750 to 0755, because the overlay carries parent
   directories and git gives them 0755. It passes `StrictModes`, so nothing
   breaks, but nothing reports it either. A per-distro `files.modes` of
   `path mode` lines applied after the copy is the fix.

3. **Host keys and `authorized_keys` do not survive an image update**, because
   `/etc/ssh` and `/root` are on the read-only root. The device's identity
   therefore changes on every update, which trains the operator to dismiss the
   one warning meant to signal an attack. This wants the writable data
   partition — still the largest open item.

4. **A fingerprint cannot be verified out of band.** Trust-on-first-use has
   nothing to compare against. The device could show its own fingerprint at
   boot as a group of text; no renderer change is needed.

5. **`sulogin`** on the single-user inittab entries prompts for a password that
   no longer exists. `init=/bin/bash` is the documented way in and is
   unaffected, but single-user mode is effectively gone.

6. **Testing an image contaminates it.** Booting writes host keys into the
   image file. The rule that emerged: *the rootfs is the master, the image is
   disposable* — test the image, then rebuild it before it ships. Done here
   twice, after being caught out once.

## Rollback

Four edits in lfs's working tree, uncommitted: revert them and rebuild the
rootfs. Distros that state a password behave exactly as before; only the
no-password case changed, and it changed from lying to being true.
