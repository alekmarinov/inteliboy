# The orchestrator's own verbs. Everything here is something the session runs
# itself rather than asking an agent whether it worked.
.PHONY: help list status test verify lock sync dirty \
        distro-packages distro check image qemu stage push seed-image

PY := python3 tools/components.py

# Building the appliance. lfs is the tool; this is its one client, and it keeps
# its distro and its output in its own tree - lfs holds neither. Every path
# handed over is absolute, because make runs those targets with lfs as the
# working directory.
LFS    := ../lfs
DISTRO := $(CURDIR)/distros/inteliboy
OUT    := $(CURDIR)/build

# Putting one component onto a running appliance, without an image.
#   make push HOST=root@192.168.1.174
# COMPONENT names both the package and the init script, which is the same word
# for everything shipped so far.
comma := ,
COMPONENT ?= avatari
HOST      ?=

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
	@echo "make push HOST=root@..  put one component on a running box, no image"
	@echo "make seed-image SECRETS=name  a copy of the image carrying a secret"

list:
	@$(PY) list

# The enforcement layer. A subagent is told which repo it may touch; nothing
# enforces that, because tool grants are per tool and not per directory. So it
# is detected instead: run this before and after any fan-out, and a component
# that went dirty without being in the brief is the alarm.
#
# The unpushed count distinguishes "no upstream" from zero. It used to report
# both as 0, because 'git log @{u}..' errors without a tracking branch and the
# error was swallowed — so a repository that had never been pushed looked
# exactly like one that was fully up to date. That is the worst confusion
# available to the one command this process uses to know where things stand.
status:
	@$(PY) test >/dev/null 2>&1 || true
	@for p in $$($(PY) paths); do \
	  [ -d "$$p/.git" ] || { printf "  %-40s not a git repo\n" "$$p"; continue; }; \
	  n=$$(basename $$p); \
	  b=$$(git -C $$p rev-parse --abbrev-ref HEAD 2>/dev/null); \
	  d=$$(git -C $$p status --porcelain 2>/dev/null | wc -l); \
	  if git -C $$p rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then \
	    a="$$(git -C $$p log --oneline @{u}.. 2>/dev/null | wc -l) unpushed"; \
	  else \
	    a="$$(git -C $$p rev-list --count HEAD 2>/dev/null || echo 0) unpushed, no upstream"; \
	  fi; \
	  printf "  %-10s %-24s %3s dirty  %s\n" "$$n" "$$b" "$$d" "$$a"; \
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
	@{ echo "# The current set. Written by 'make lock'."; \
	   echo "#"; \
	   echo "# This records what the components are, not that they have been run"; \
	   echo "# together. It earns the word 'proven' only once an image built from"; \
	   echo "# these commits has booted — write that below, with the date, when it"; \
	   echo "# has. A lock that claims more than it knows is worse than none."; \
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

# The fast loop: build the package, put usr/ on the device, restart, verify.
# Minutes rather than an image. It pushes usr/ only and says what it skipped —
# a package also carries /etc, which the distro overlay owns, and pushing that
# would replace a device's configuration with the build default.
push:
	@test -n "$(HOST)" || { echo "HOST= is required, e.g. make push HOST=root@192.168.1.174"; exit 1; }
	@tools/push.sh $(HOST) $(LFS)/packages/$(COMPONENT).tar.gz $(COMPONENT)

# Write secrets into a *copy* of the image, for a device that cannot be reached
# after it boots. Prefer provisioning a booted device: a credential inside an
# image is in every copy of it and revoking means reflashing rather than
# deleting a file. The copy is named -provisioned.img and is gitignored, so it
# cannot be mistaken for the image you would hand to somebody.
#   make seed-image SECRETS=anthropic.api_key
seed-image:
	@test -n "$(SECRETS)" || { echo "SECRETS= is required, e.g. make seed-image SECRETS=anthropic.api_key"; exit 1; }
	@tools/seed-image.sh $(OUT)/image.img $(subst $(comma), ,$(SECRETS))

# ---------------------------------------------------------------- running --
#
# cogiti on this workstation, wired to the adapters this repository provides.
# `config/cogiti.dev.conf` is the whole configuration; these targets only say
# which one to load.

COGITI  ?= ../cogiti
AVATARI ?= ../avatari
CONF    ?= config/cogiti.dev.conf

.PHONY: talk face renderer

## talk: cogiti in a terminal, no face
talk:
	@$(COGITI)/bin/cogiti --conf=$(CONF) \
	  $(if $(SOCK),--presentation-adapter=$(SOCK),) 2>&1

## renderer: start avatari's desktop build in the background
#
# Two things here are deliberate, and the first version had neither.
#
# The liveness test is "does something answer on the socket", not "does a
# process match a string". `pgrep -f 'avatari --socket /tmp/avatari.sock'`
# matches the shell running this very recipe, because make's `sh -c` command
# line contains the pattern — so it always found avatari, never started one,
# and cheerfully printed that it had.
#
# And it waits for the socket rather than sleeping. A fixed sleep is a race
# either way: too short on a cold GL init, wasted every other time. If the
# renderer does not come up, this says so and shows its log, because a target
# that claims success having started nothing is worse than one that fails.
AVATARI_SOCK ?= /tmp/avatari.sock

# AUDIO=1 passes --audio, which opens ALSA. Off by default here because this
# workstation has no sound card at all: `aplay -l` finds none, WSLg offers only
# a PulseAudio bridge, and avatari talks to ALSA directly. On the appliance the
# question does not arise — /etc/avatari.conf sets audio.enabled = true and the
# image carries alsa-lib, alsa-utils and an alsactl that unmutes at boot.
#
# The mouth does not depend on this. Visemes run against audio_start_ns whether
# or not anything plays, which is why the head is demonstrable here at all.

renderer:
	@$(MAKE) -C $(AVATARI) PLATFORM=desktop >/dev/null
	@python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); \
	  sys.exit(0 if not s.connect_ex('$(AVATARI_SOCK)') else 1)" 2>/dev/null \
	  && echo "avatari already up on $(AVATARI_SOCK)" && exit 0 || true; \
	rm -f $(AVATARI_SOCK); \
	( cd $(AVATARI) && exec ./build/desktop/avatari --socket $(AVATARI_SOCK) \
	    $(if $(AUDIO),--audio,) >/tmp/avatari.log 2>&1 & ); \
	for i in $$(seq 1 60); do \
	  python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); \
	    sys.exit(0 if not s.connect_ex('$(AVATARI_SOCK)') else 1)" 2>/dev/null \
	    && echo "avatari on $(AVATARI_SOCK)  (log: /tmp/avatari.log)" && exit 0; \
	  sleep 0.25; \
	done; \
	echo "avatari did not come up within 15s:"; sed "s/^/    /" /tmp/avatari.log; \
	exit 1

## tap: watch what cogiti actually says to avatari
##
##     make tap &          then: make talk SOCK=/tmp/avatari-tap.sock
##
## A socket proxy that forwards both ways and prints every line. Worth
## reaching for early: the wire showed in one screen that cogiti was sending
## `idle` in the same millisecond as `speak`, which no amount of reading the
## two modules had revealed.
.PHONY: tap
tap: renderer
	@python3 tools/tap.py

## audio-check: say which link in the sound chain is broken
.PHONY: audio-check
audio-check:
	@tools/audio-check.sh

## face: the renderer, then cogiti talking to it
face: renderer talk

## say: move the mouth, through cogiti's own speech and presentation path.
## No model, no API key, no cost — for when the question is "does the face
## work" rather than "does the assistant work".
##
##     make say TEXT="Hello, I am InteliBoy."
TEXT ?= Hello. I am InteliBoy, and this is what my mouth does when I talk.

.PHONY: say
say: renderer
	@PYTHONPATH=$(COGITI)/src python3 -c "import asyncio,sys,time; \
	from cogiti import present, speech; \
	from cogiti.adapters import presentation; \
	a=presentation.Presentation('$(AVATARI_SOCK)', on_warn=lambda m: print(m)); \
	p=present.Presenter(a); \
	sp=speech.Speech(['adapters/espeak/speak'], on_warn=lambda m: print(m)); \
	m=asyncio.new_event_loop().run_until_complete(sp.marks(sys.argv[1])); \
	sys.exit('no marks from the speech adapter') if not m else None; \
	p.result({'say': sys.argv[1], 'show': sys.argv[1]}); \
	p.speak(m); \
	print('%d visemes over %.2fs' % (len(m['visemes']), m['visemes'][-1][0])); \
	time.sleep(m['visemes'][-1][0] + 1.5)" "$(TEXT)"
