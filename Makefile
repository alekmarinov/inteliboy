# The orchestrator's own verbs. Everything here is something the session runs
# itself rather than asking an agent whether it worked.
.PHONY: help list status test verify lock sync dirty \
        distro-packages distro check image qemu stage

PY := python3 tools/components.py

# Building the appliance. lfs is the tool; this is its one client, and it keeps
# its distro and its output in its own tree - lfs holds neither. Every path
# handed over is absolute, because make runs those targets with lfs as the
# working directory.
LFS    := ../lfs
DISTRO := $(CURDIR)/distros/inteliboy
OUT    := $(CURDIR)/build

help:
	@echo "make list      what components exist and where"
	@echo "make status    branch, dirty files and unpushed commits, per component"
	@echo "make dirty     JUST the components with uncommitted changes (the guard)"
	@echo "make test      run each component's own test command"
	@echo "make verify    status + test. What 'verified at the end' means"
	@echo "make lock      write the current HEADs into versions.lock"
	@echo "make sync      check every component out at versions.lock"
	@echo
	@echo "  and the appliance itself, built by lfs from distros/inteliboy:"
	@echo "make stage             build every component and stage its tarballs"
	@echo "make distro-packages   build the recipes this distro brings (needs root)"
	@echo "make distro            assemble build/rootfs"
	@echo "make check             resolve every binary in it against its libraries"
	@echo "make image             turn it into build/image.img"
	@echo "make qemu              boot that image"

list:
	@$(PY) list

# The enforcement layer. A subagent is told which repo it may touch; nothing
# enforces that, because tool grants are per tool and not per directory. So it
# is detected instead: run this before and after any fan-out, and a component
# that went dirty without being in the brief is the alarm.
status:
	@$(PY) test >/dev/null 2>&1 || true
	@for p in $$($(PY) paths); do \
	  [ -d "$$p/.git" ] || { printf "  %-40s not a git repo\n" "$$p"; continue; }; \
	  n=$$(basename $$p); \
	  b=$$(git -C $$p rev-parse --abbrev-ref HEAD 2>/dev/null); \
	  d=$$(git -C $$p status --porcelain 2>/dev/null | wc -l); \
	  a=$$(git -C $$p log --oneline @{u}.. 2>/dev/null | wc -l); \
	  printf "  %-10s %-24s %3s dirty  %3s unpushed\n" "$$n" "$$b" "$$d" "$$a"; \
	done

dirty:
	@for p in $$($(PY) paths); do \
	  [ -d "$$p/.git" ] || continue; \
	  d=$$(git -C $$p status --porcelain 2>/dev/null | wc -l); \
	  [ "$$d" -gt 0 ] && printf "%s\t%s dirty\n" "$$(basename $$p)" "$$d" || true; \
	done

test:
	@fail=0; \
	$(PY) test | while IFS="$$(printf '\t')" read -r name path cmd; do \
	  printf "\n=== %s: %s\n" "$$name" "$$cmd"; \
	  ( cd "$$path" && eval "$$cmd" ) || { echo "!!! $$name FAILED"; fail=1; }; \
	done; \
	exit $$fail

verify: status test

# Both, deliberately. The version is what we talk about and what ships in
# tarball names and /etc/os-release; the commit is the only thing that
# reproduces a build, because a tag can be moved and a dirty tree has no
# version at all. A repository with no commits yet reports 0.0.0 and an empty
# commit rather than being left out - being absent from the lock and being
# unreleased look the same otherwise.
lock:
	@{ echo "# The last set proven to work together. Written by 'make lock'."; \
	   echo "# Generated $$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	   for p in $$($(PY) paths); do \
	     [ -d "$$p/.git" ] || continue; \
	     n=$$(basename $$p); \
	     if ! c=$$(git -C $$p rev-parse HEAD 2>/dev/null); then \
	       printf '%-10s = { version = "0.0.0", commit = "" }  # no commits yet\n' "$$n"; \
	       continue; \
	     fi; \
	     v=$$(git -C $$p describe --tags --dirty 2>/dev/null \
	          || echo "0.0.0-g$$(git -C $$p describe --always --dirty)"); \
	     printf '%-10s = { version = "%s", commit = "%s" }\n' "$$n" "$$v" "$$c"; \
	   done; } > versions.lock
	@cat versions.lock

sync:
	@echo "not implemented until versions.lock has been reviewed once by hand"

# --- the appliance ------------------------------------------------------
#
# Thin wrappers. Every one of them passes the same DISTRO and the same OUT, so
# there is one distro directory and one output directory and no argument to get
# wrong. The tool is untouched by any of this: it is pointed at a path.

# Builds every component and puts its tarballs where the recipes look for them.
# This is the hand-off that used to be a manual 'make dist', a manual copy and
# a hand-edited checksum file.
stage:
	@tools/stage.sh $(DISTRO)

# Root, because a package builds in a chroot.
distro-packages:
	sudo $(MAKE) -C $(LFS) distro-packages DISTRO=$(DISTRO)

distro:
	$(MAKE) -C $(LFS) distro DISTRO=$(DISTRO) OUT=$(OUT)

check:
	$(MAKE) -C $(LFS) check DISTRO=$(DISTRO) OUT=$(OUT)

# Root, because it attaches a loop device and mounts the partitions.
image:
	sudo $(MAKE) -C $(LFS) image DISTRO=$(DISTRO) OUT=$(OUT)

qemu:
	$(MAKE) -C $(LFS) qemu DISTRO=$(DISTRO) OUT=$(OUT)
