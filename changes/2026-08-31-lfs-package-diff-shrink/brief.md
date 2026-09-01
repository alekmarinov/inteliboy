# 2026-08-31-lfs-package-diff-shrink — a rebuilt package silently ships less

Status: **draft — a proposal to lfs, not approved**
Written by: the orchestrator session, from a defect found on a booted appliance.
Approved by: —

> **This is a proposal.** lfs is a tool. The orchestrator may edit it when an
> approved brief says to; the user commits. **None of the four orders below has
> been applied.** One adjacent defect in the same code path *was* fixed, under
> `2026-08-31-inteliboy-out-of-lfs`, because it blocked that change — see
> finding 10.

## The ask

Rebuilding one recipe can make its package quietly ship fewer files than
before, and nothing says so. The package cache is then wrong for every image
built afterwards. Make it impossible to lose a file without being told.

## The seam

    contract:  package format — a package is the overlay diff of its build
    owner:     lfs
    consumers: every distro assembled from the package cache
    breaking:  no. The proposal adds a check and a declaration; no package
               format change, no distro change.

## What a package is

`scripts/packages/build-package.sh`:

    :108   mount -t overlay -olowerdir=$LFS_BASE,upperdir=$LFS_PACKAGE,…
    :180   tar cfz "$package_name" -C "$LFS_PACKAGE" .     the package IS the upper layer
    :182   copy-or-del.sh "$LFS_PACKAGE" "$LFS_BASE"       …then merged down into the base
    :184   rm -rf "$LFS_PACKAGE"/*

A package is a **diff, not a manifest**: exactly the files that build wrote.
After a successful build the diff is merged into the base, which is how the LFS
system accumulates for the next package. That design is sound and is not what
this brief proposes to change.

## Findings

1. **A second build of a recipe is not the same as its first.** After the merge,
   a rebuild sees its own previous output in the lower layer. Any step that
   *checks first and skips* then writes nothing, nothing is copied up, and the
   package loses those files. Three such steps exist in `4-make-openssh.sh`
   alone:

   | what | the guard | result on rebuild |
   |---|---|---|
   | the `sshd` account | `useradd … 2>/dev/null \|\| true` | user exists → no write → no `/etc/passwd` in the package |
   | the host keys | `make install` runs `ssh-keygen -A`, which skips existing keys | no keys in the package |
   | `sshd_config`, `ssh_config`, `moduli` | upstream's own install rule | `already exists, install will not overwrite` |

2. **`make packages` never triggers it.** `build-package.sh:81` skips a recipe
   whose `tmp/<name>.ready` flag exists, so a full pipeline run builds each
   recipe once and every diff is complete. **`Makefile:168` invokes the
   single-package target as `build-package.sh -f …`, always forced.** So this
   is a trap for whoever iterates on a recipe, not for the pipeline.

3. **The two recipes built twice by design are unaffected.**
   `10-make-freetype` and `8.51-make-python` each appear twice in the build
   order via `REBUILD_AFTER`. `make install` rewrites its files unconditionally,
   so their second diff is still complete. Only check-then-skip steps lose
   anything.

4. **It is silent three times over.** The recipe swallows it (`|| true`);
   upstream's "install will not overwrite" is an ordinary message and the build
   exits 0; and the new package is written with no comparison against the one
   it replaces, so a package that shrank looks exactly like one that was always
   that size.

5. **It had already happened here, before this was noticed.**
   `4-make-openssh.tar.gz` carried `sshd_config`, `ssh_config`, `moduli` and
   host keys but **no `/etc/passwd`**; `14-make-dhcpcd.tar.gz` carried no
   `/etc/passwd` either. So the `sshd` account already existed in the base when
   openssh was first built here. `build-distro.sh:239` describes the same
   symptom — "how `/etc/passwd` lost the dhcpcd and sshd accounts while both
   packages were installed" — and the account-merge written to fix it can only
   preserve an account that *some* package carries. It cannot conjure one that
   none does.

6. **What it cost on a real device.** The appliance shipped `/sbin/dhcpcd` with
   no `dhcpcd` user, so it had no network at all. And because
   `4-make-openssh.tar.gz` carried the generated host keys, every image built
   from that cache would have answered with the same fingerprint, with the
   private half sitting in the build tree.

7. **It bit again during the repair.** Rebuilding openssh to fix the account
   dropped `sshd_config`, `ssh_config` and `moduli` from the package — the
   files were in the base by then, so upstream refused to overwrite and the
   diff lost them. Recovered only by purging them from the base and building a
   third time.

8. **One recipe still has the defect, latent.** Of the four that create service
   accounts — `14-make-dhcpcd`, `4-make-openssh`, `12-make-fcron`,
   `12-make-dbus` — the first three now carry `/etc/passwd`. **`12-make-dbus`
   does not.** It is in no distro list in use, so it has not been noticed.

9. **A separate defect found alongside, with a different cause than it looks.**
   The boot reported `Starting dhcpcd on the eth0 interface… [ OK ]` for a
   daemon that died immediately. `lib/services/dhcpcd:47-48` does call
   `evaluate_retval`; the reason it passes is `DHCP_START="-b -q"` in
   `/etc/sysconfig/ifconfig.eth0` — dhcpcd backgrounds itself and exits 0
   before the child discovers the missing user. The service script is shipped
   by `14-make-dhcpcd`, the config by `9.5-configure-network`.

10. **Adjacent, in the same post-build path, and already fixed under
    `2026-08-31-inteliboy-out-of-lfs`.** `11-unmount-vkfs.sh` is best effort
    (`set +e`) but exits with the status of its last `umount`, and
    `build-package.sh:132` calls it with the `ERR` trap armed. A kernel that
    compiled and installed cleanly was discarded before `tar` ran. Fixed with
    an explicit `exit 0`. Named here because it is the same weakness as the
    rest of this brief: **the packaging step's error handling cannot tell a
    successful build from a failed one.**

11. **A fifth instance, and the one that shows the defect is not only about
    losing things.** `/etc/shadow` is a shared file, so a package captures the
    whole of it. `4-make-shadow.sh` sets a root password at build time, and
    `14-make-dhcpcd`, `4-make-openssh` and `8.85-clean` each carry a copy of
    that hash — verified to be `toor`. So the diff mechanism *gains* a secret
    as readily as it loses an account: a build artifact ends up holding a
    credential that nothing declared and nothing reports.

    Fixed at the assembly end under
    `changes/2026-08-31-lfs-no-password-distro/`, which now writes the field
    rather than trusting what the packages carried. The packages themselves
    still hold the hash until rebuilt.

## The proposal

### lfs [order 1] — a rebuild may not silently ship less
files: `scripts/packages/build-package.sh`
change: the data needed is already read. `:160-164` loads the previous
package's file list into `$mine`, purely to tell "this package modified
someone else's file" from "this is my own file from last time":

    tar tzf "$LFS_PACKAGES/${name}.tar.gz" | sed 's|^\./||' | grep -v '/$' > "$mine"

Add the set difference: **any path in `$mine` absent from the new upper layer
is a file this rebuild stopped shipping.** Report each one and fail, unless an
explicit override says the removal is intended — a recipe that deliberately
stops installing something is a real case and should have to say so.

This catches the whole class at once: accounts, keys and config files alike,
and anything else a future recipe guards. It is the cheapest fix and the one
with the widest reach.
**proves it:** rebuild `4-make-openssh` twice in a row; the second is refused,
naming `etc/passwd`, `etc/ssh/moduli`, `etc/ssh/ssh_config`,
`etc/ssh/sshd_config`.

### lfs [order 2] — service accounts stop depending on a diff
files: the four account-creating recipes, `scripts/image/build-distro.sh`
change: declare the account in the recipe rather than leaving it to be captured
as a side effect —

    # ACCOUNT: sshd 50 /var/lib/sshd /bin/false

— and have `build-distro.sh` create declared accounts while assembling, next to
the account-merge it already does. An account then cannot be lost, because it
is no longer carried by accident. Narrower than order 1 and worth having as
well: order 1 makes the loss loud, order 2 makes it impossible for the case
that has actually caused two outages.
**proves it:** an assembled rootfs has every declared account even when built
from a package cache whose `/etc/passwd` is absent.

### lfs [order 3] — `12-make-dbus` (finding 8)
files: none, if orders 1–2 land; otherwise a purge-and-rebuild
change: with order 2 the declaration fixes it. Without it, the account has to
be purged from `overlay/base/etc/{passwd,group,shadow,gshadow}` and the package
rebuilt, which is the manual dance this brief exists to remove.
**proves it:** `12-make-dbus.tar.gz` carries its account, or the assembler
creates it.

### lfs [order 4] — a backgrounded daemon is not a started daemon (finding 9)
files: `lib/services/dhcpcd` in `14-make-dhcpcd.sh`
change: after `/sbin/dhcpcd $1 $DHCP_START` with `-b`, `evaluate_retval` is
testing the fork, not the daemon. Check the pidfile names a live process a
moment later, and report *that*. Smallest of the four and independent of the
rest.
**proves it:** with the `dhcpcd` account removed, the boot reports a failure
rather than `[ OK ]`.

## Not in this change

- **Building every package into a pristine base.** Correct, and costs hours per
  package. The point of the shared base is that it is not paid.
- **Changing the package format** from a diff to a manifest. Much larger, and
  the diff is what makes a package cheap to produce.
- Making `install will not overwrite` an error. It is upstream's behaviour and
  correct on its own terms; the problem is that nobody compares afterwards.

## Rollback

Nothing has been applied. If orders land: they are additive checks and a
declaration, so reverting is deleting them. No package needs rebuilding to go
back, because a package that passes the new check also passed the old absence
of one.

## Evidence

Commands whose output is quoted above, run on 2026-08-31 against
`/home/alekm/Projects/Intelibo/lfs`:

    tar tzf packages/4-make-openssh.tar.gz | grep -E '^\./etc/'
    tar xzf packages/14-make-dhcpcd.tar.gz -O ./etc/passwd | grep dhcpcd
    sudo grep -E '^(sshd|dhcpcd):' overlay/base/etc/passwd
    sudo grep -i 'will not overwrite' overlay/base/tmp/4-make-openssh.log
    grep -ln 'useradd\|groupadd' scripts/packages/*/*.sh
