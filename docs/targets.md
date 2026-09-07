# Targets — one brain, several self-contained devices

InteliBoy on Android: a phone and a TV, each running **the whole stack
locally**, nothing remote, no companion, no second screen. The same four
components, built for a different machine.

**Status: analysis. Not a brief, not approved, nothing landed.** No contract
has been changed and no component has been touched. This is the file to pick up
when the work starts.

Written from direct inspection of the five repositories on 2026-09-05, against
`versions.lock` at avatari 0.3.0 / cogiti 0.16.0 / reflexi 0.6.0 / audi 0.2.0.
Every claim about what exists was checked in the tree; estimates say so.

It replaces an earlier draft that read "multiscreen" as a distributed display —
one brain on the appliance, surfaces elsewhere. §12 records that reading and
why it was dropped, because a design whose rejected alternatives are invisible
cannot be revisited.

---

## 1. What this is, in one paragraph

Today there is one product: an LFS image for x86 that boots into a talking
head. This proposes two more, built from the same components, each a complete
device on its own: **an Android phone** and **an Android TV**. Nothing talks
over a network to anything else. A phone that is out of the house is a whole
InteliBoy, not a window onto one. The differences between the three products
are configuration, one platform backend per component, and a single port.

---

## 2. What this idea gets right, which is more than it looks

Three things, and the third is the one worth the work on its own.

**It is what cogiti was built for.** `../cogiti/CLAUDE.md`: *"It is **not tied
to any particular device.** Everything it needs from the outside — a resolver,
a screen, a voice, a camera, a model, a machine to run on — arrives through one
of the six ports."* And this repository's own framing: *"cogiti is general;
InteliBoy is a deployment of it."* There is exactly one deployment today, which
means **cogiti's generality is currently unfalsifiable** — every port could be
quietly avatari-shaped and x86-shaped and nobody could tell. A second and third
deployment is the test that has never been run. If the port design is good, this
is cheap; if it is not, this is how we find out, and finding out is worth
something either way.

**It deletes most of the hard problems, rather than solving them.** Everything
that made a distributed design expensive was a consequence of a machine
boundary, and there is no machine boundary here:

| the problem | why it is gone |
|---|---|
| `src` is a path on the renderer's machine | it *is* the renderer's machine |
| `audio_start_ns` is a per-machine `CLOCK_MONOTONIC` | one kernel, so it means what it says |
| cogiti would have to listen on a TCP port | it listens on nothing, exactly as `architecture.md` §4 says |
| consent must not come from a screen | the microphone is in the room, because the room is wherever the device is |
| the scene protocol acquires a second consumer | it does not — a platform backend is a *port* of avatari, not a second renderer. `CLAUDE.md` §2's one-consumer rule survives |
| pairing, certificates, discovery, revocation | none of it exists |

Four findings from the earlier draft evaporate. That is a strong signal about
which design is right.

**Android TV may be a truer InteliBoy than the LFS box.** The premise is a
device that sits in a room, is always on, boots straight into a face, and is
spoken to. An Android TV is mains-powered, always on, has a big screen and a
remote with a microphone button, sits on a shelf, and costs thirty to fifty
dollars. It has no Doze aggression, no battery manager, and a launcher app is
expected to be resident. The LFS appliance is a better *engineering* artifact
and Android TV is a better *appliance*, and those are different sentences.

And the multi-target premise is already half proven in the component you would
expect to be most welded to the hardware: **avatari already has two platform
backends** — `platform_kms.c` (EGL/GBM/DRM, 640 lines) and
`platform_desktop.c` (GLFW, 205 lines) — behind a `platform.h` that is four
functions and 90 lines. A third is a known shape.

---

## 3. The one thing that genuinely does not port

**Android has no second uid and no way to run code you wrote after install.**

This is the whole difficulty. Everything else in this document is work; this is
a design decision that has to be made by a person.

### 3.1 What cogiti does today

Verified in the tree, not recalled:

| | |
|---|---|
| `jobs.py:64` | `subprocess.Popen(..., start_new_session=True)` |
| `jobs.py:74` | `os.getpgid(proc.pid)`, stored as the job's `pgid` |
| `jobs.py:193` | `os.killpg(pgid, sig)` — `SIGTERM`, grace, `SIGKILL`, then verify no survivors |
| `services.py:183-195` | `os.setgid`, `os.setuid`, `resource.setrlimit` × 4, `os.setsid`, in a `preexec_fn` |
| `services.py:317` | services spawned as `python3 main.py` under that `preexec_fn` |
| `adapters/agent.py:78` | the agent adapter is a subprocess in its own session, cancelled by group |

That is `cogiti/CLAUDE.md` §4's settled decision made real: *"One asyncio
process that is also a supervisor… Everything with a duration is a child in its
own process group, so cancellation is a signal to a group and not a hope."*

### 3.2 What Android permits

- **One app is one uid.** There is no `setuid` to a `cogiti-svc-eth-price`
  account, because there is no such account and no way to make one.
- **W^X, enforced since API 29.** An app may not `exec()` a binary from
  writable storage. Executables come from `nativeLibraryDir`, which is filled
  from the APK at install time and is read-only afterwards.
- Process groups, `killpg` and `setrlimit` are either unavailable or
  meaningless to an app.

So `os.setuid` is out, `setrlimit`-per-service is out, and — the one that
matters — **an agent cannot write a service and have it run as its own confined
process.** That is roadmap Stage 5, described as *"the stage the whole project
is for"*.

### 3.3 Three ways out, and one of them is better than the appliance's

**(a) Interpreted, in-process.** A generated service is Python executed by the
embedded interpreter. W^X does not apply, because the interpreter reads a `.py`
as data — this is not `exec(2)`. It works, and it costs the entire confinement
story: same uid, same process, same address space as cogiti and its secrets.
`services.md`'s review gate rests on *"its own unprivileged uid… its own
directory… `RLIMIT_*` from the manifest"*, and none of that would be true.
Acceptable only if said out loud in the same voice `security.md` §2 uses about
secrets at rest.

**(b) `android:isolatedProcess="true"`.** Android can run a service component
in a separate process with **its own isolated uid, no permissions at all, no
filesystem access and no network**. That is *stronger* than what the appliance
gives a service today, not weaker.

The reason it fits is almost suspicious. An isolated process has no network, so
it must be brokered — and cogiti already has the broker, and the broker is
already the right shape. `broker.py`, in its own words:

> This is deliberately **not a proxy**. It does not forward arbitrary traffic:
> it answers one question — fetch this URL — and returns a body. A service that
> wants a protocol cogiti does not speak does not get one, which is a feature.

A component that cannot open a socket at all is exactly the client that broker
was written for. The manifest's `[network] allow` is already the declaration,
the SDK already owns the connection discipline, and `services.md` §3 already
says *"every capability it does not expose is a capability a generated service
cannot casually acquire"*. On Android the platform enforces that instead of
merely the SDK.

What has to be verified before promising it: that an embedded CPython can be
started inside an `isolatedProcess`, fed a generated `.py`, and talked to over
a pipe or Binder. It is the single most valuable half-day of investigation in
this document.

**(c) Ship Android without service birth at first.** Stages 0–4 and 6–10 do not
need it. Stage 5a (services as data, hand-written, shipped in the APK) works
under (b) with no authoring pipeline. Stage 5b (an agent writing one) waits.
Each stage stays shippable, which is the roadmap's own constraint.

**Recommendation: (c) now, (b) proven in parallel, (a) never.** (a) is the one
that will suggest itself under time pressure and it is the one that quietly
converts a reviewed sandbox into a promise.

### 3.4 What this costs cogiti, and why the cost is worth paying anyway

The platform port already names `supervise` and `confine`. cogiti's code does
not go through it — `jobs.py` and `services.py` call POSIX directly. So the
work is:

> **Make the platform port real: `supervise` and `confine` become an interface
> with a POSIX implementation, rather than `subprocess` and `os.killpg`
> inlined.**

Two things about that are worth noticing. It is a change that makes an existing
settled decision *honest* rather than one that bends cogiti for a device —
which matters, because `cogiti/CLAUDE.md` §9's first non-goal is *"being tied
to one device"* and the fastest way to violate it is a special case. And
`docs/adapters.md` currently calls platform *"the weakest binding, and the one
with a hard gap"*; Android turns it into the port that carries the entire
difference between three products. The weakest binding becomes the load-bearing
one.

The appliance is unaffected: the POSIX implementation is what it already does,
moved behind a name.

---

## 4. Component by component

### 4.1 avatari — the easiest, and one shader decides how easy

**What ports without thinking.** `third_party/` is header-only —
`stb_truetype.h`, `stb_image.h`, `stb_image_write.h`, `cgltf.h`,
`HandmadeMath.h` — plus glad. Base `LDLIBS` is `-lm -lpthread`. The VRM loader,
blendshape animation, viseme crossfade, idle behaviour, gaze, scene layout, IPC
parsing and text rasterising know nothing about a display. That is 9,397 lines
of C11 that needs no attention.

**The platform backend.** `PKGS` today is `libdrm gbm egl alsa` for KMS and
`glfw3 alsa` for desktop. Android replaces all of it: `ANativeWindow` + EGL
(both native), and no ALSA at all — `adapters.md` already says the speaker
moves to audi, so the Android build should simply not have `audio.c`. A
`platform_android.c` is the same job `platform_desktop.c` did in 205 lines.

**The one real problem is a shader.** Every shader is `#version 410 core`, and
`head.vert` accumulates morph deltas out of a **texture buffer**
(`samplerBuffer` / `GL_TEXTURE_BUFFER`), with a comment noting that compute
shaders were unavailable at the GL 4.1 baseline. Texture buffers are **not in
GLES 3.0**; they arrive via `GL_EXT_texture_buffer` on 3.1 and in core at 3.2.

This is not a phone problem. Phones shipped in the last several years are GLES
3.2 almost without exception. **It is an Android TV problem**: cheap TV boxes
and older television SoCs are commonly GLES 3.0 or 3.1, and the ones people
actually own are the cheap ones. So:

> **The morph-target path decides the Android TV device floor.** Solve it once
> — a 2D texture with computed coordinates, or a UBO — and both targets widen
> to everything that runs GLES 3.0.

Do that before writing the backend, not after. It is the difference between "TV
support" and "support for TVs bought after 2022".

**Also worth knowing:** an Android TV app is D-pad only. avatari's
`platform.h` already carries `INPUT_KEY_DOWN`, arrow keycodes and
`INPUT_RESIZE`, so the remote maps onto an interface that already exists.

### 4.2 reflexi — nearly free

C11, no dependencies of consequence, and it **already builds a shared object**:
`Makefile:138` produces `libreflexi.so.$(SOVERSION)` with a soname, installed
alongside the static archive. NDK cross-compile, load by JNI or by ctypes from
the embedded interpreter, and the ~16 µs stays ~16 µs because it is a function
call either way. The Python half is blob compilation at build time and never
runs on a device.

The blob and the registry ship as APK assets. Nothing about the decision
contract changes.

**This is the component where the port is a day, and it is the component that
makes an offline device answer instantly.** Worth doing early for morale as
much as anything.

### 4.3 audi — a rewrite, and it comes out smaller

audi today is Python: `sherpa-onnx` with `whisper-tiny.en`, numpy, its own VAD,
its own AEC, and `subprocess` calls out to a TTS command. It ships ABI-locked
`cp312` wheels. None of that survives contact with Android — Python wheels for
Android are a fight, and the fight is unnecessary, because **Android gives away
most of what audi had to build.**

| audi builds | Android provides |
|---|---|
| acoustic echo cancellation (`aec.py`) | `AcousticEchoCanceler` at the HAL |
| noise suppression | `NoiseSuppressor` |
| VAD and endpointing (`vad.py`) | `SpeechRecognizer` endpoints for you, or keep audi's |
| whisper via sherpa-onnx (`asr.py`) | `SpeechRecognizer`, or sherpa-onnx's own first-class Android AAR |
| a TTS subprocess (`tts.py`) | `TextToSpeech` |
| low-latency capture and playback | AAudio / Oboe |

The 23× echo measurement that forced audi to own the speaker is handled by the
platform, in the platform's own clock domain. **audi is the component where
Android is easier, not harder** — a few hundred lines of Kotlin implementing
the same speech protocol.

And this needs no contract change at all, which is the port design earning its
keep: audi *consumes* the speech protocol, cogiti *owns* it, so a second
implementation is legitimate by construction. `components.toml` already records
this — audi's `owns` is empty.

**One thing does not come free: viseme timings.** `TextToSpeech` reports
utterance progress, not phoneme boundaries. Keep **espeak-ng as the
phonemiser** — it is plain C, builds under the NDK, and avatari's own
documentation already anticipates this split: *"When Piper replaces espeak-ng
at stage 2 the phonemiser is still espeak-ng, so everything below the phoneme
list carries over unchanged."* Phonemes from espeak-ng, voice from the platform
or from Piper, one `speak` message, and the renderer cannot tell.

**Wake word is the honest gap.** Android exposes no free always-on hotword. The
options are a foreground service holding the microphone (which, on Android 12+,
lights the system microphone indicator permanently), a paid engine, or
push-to-talk. On a TV, push-to-talk is not a compromise — it is the remote's
microphone button, which is what people already reach for.

Worth noting in passing: Android's permanent microphone indicator is the same
mechanism avatari built by hand for the camera — *"no id, no region, and no
field that disables it"*. On Android the operating system enforces the
invariant for you.

### 4.4 cogiti — the Python question, and the process question

The process question is §3 and it is the real one. The Python question is
merely large.

cogiti and audi are ~10,589 lines of Python; on Android, cogiti's half must run
somewhere. The realistic options are an embedded CPython (Chaquopy, or built
against the NDK directly) or a rewrite in Kotlin. **A rewrite is the wrong
answer** and should be refused early: it would mean two cogitis, and the whole
premise is that there is one general orchestrator with several deployments. Two
implementations of the orchestrator is two products that will diverge, and
`versions.lock` could not describe either.

So: embedded CPython, asyncio intact, `ctypes` into `libreflexi.so`, SQLite
present, the agent adapter running in-process or in an isolated process rather
than as an `exec`ed subprocess.

The agent port asks for *"a separate process in its own process group, so
cancellation is a signal to a group rather than a hope"*. On Android the
equivalent is a separate Android process killed by `Process.killProcess`, which
satisfies what the requirement is *for* — real cancellation, contained crash,
dependency isolation — without process groups existing. Record that as a
platform-port implementation note rather than as an exception to the agent
port.

Everything else in cogiti is I/O, JSON, TLS and SQLite, and is portable by
construction.

### 4.5 lfs — untouched, and that is the point

`lfs` is a build tool for LFS images. It has no part in an Android build and
should acquire none. `grep -ri inteliboy ../lfs` coming back empty stays an
invariant; so does the reverse — nothing Android goes near it.

The Android build system is Gradle plus the NDK, living in whichever repository
owns each component, exactly as each component owns its own Makefile today.

---

## 5. What the three products differ in

The useful summary. If this table stays this short, the design is working.

| | LFS appliance (x86) | Android phone | Android TV |
|---|---|---|---|
| presentation | avatari, KMS backend | avatari, Android backend | same as phone |
| resolver | reflexi, static-linked | reflexi, `.so` via NDK | same |
| speech | audi (sherpa-onnx, espeak/Piper) | audi-android (platform + espeak-ng) | same, mic on the remote |
| agent | subprocess adapter | in-process or isolated-process driver | same |
| platform: supervise | process groups, `killpg` | Android processes | same |
| platform: confine | uid + `setrlimit` | `isolatedProcess`, or nothing yet (§3.3) | same |
| platform: persist | the data partition (still owed) | app-private storage, free | same |
| platform: egress | the broker | the broker, and now compulsory | same |
| always-on | init, unconditionally | foreground service, Doze, OEM battery managers | foreground service, and none of that trouble |
| wake word | audi's, always listening | push-to-talk, or a permanent mic indicator | the remote's mic button |
| input | voice | voice, touch | voice, D-pad |
| service birth (Stage 5b) | works as designed | §3.3 | §3.3 |
| distribution | flash an image | APK, or Play with a policy conversation | same |

Two observations from the table. **Android TV loses nothing to the phone and
wins on always-on, input and the microphone story** — it is the better of the
two Android targets, and it is the one closer to the original premise. And
**every difference lands in the platform port or in an adapter**, which is the
result the architecture predicted and the reason to believe the rest of it.

---

## 6. What it costs the project's rules

Three, and none is fatal.

**`cogiti/CLAUDE.md` §4's process model becomes conditional.** *"Everything
with a duration is a child in its own process group"* is true on one of three
platforms. The decision does not have to be reversed — it has to be restated as
what it always was, a requirement on the platform port with a POSIX
implementation. That is §3.4.

**`services.md`'s confinement is weaker on Android, or different.** Either
`isolatedProcess` (stronger in some ways, no `RLIMIT_*` in others) or nothing
yet. The manifest's `[limits]` block becomes advisory on a platform that cannot
enforce it, and **a manifest field that is silently ignored is worse than one
that is absent** — so the platform port should report what it can enforce, and
cogiti should refuse to install a service whose manifest asks for a limit the
platform cannot apply. That is `ports.md`'s existing discipline: *"cogiti
asserts what its configuration requires and fails loudly at startup naming the
missing capability."*

**`versions.lock` becomes per-product.** One lock file describes one image. With
three products there are three known-good sets, and pretending otherwise is
exactly the failure the file already exists to prevent — it was wrong once
before by naming an avatari two commits ahead of the one inside the image. The
machinery generalises cleanly (`build/staged.lock` per product), and this makes
`components.toml` and the landing-order rule *more* valuable rather than less.

---

## 7. What Android gives back

Not a consolation list; several of these are ahead of where the appliance is.

- **Persistence, solved.** App-private storage survives an app update by
  construction. The data partition — *"the single most important item in this
  table"*, still owed by `lfs` — is free on Android. The first platform where
  Stage 5 and Stage 11 can actually be exercised may not be the appliance.
- **Audio, solved.** Echo cancellation, noise suppression, low-latency capture,
  and a TTS engine, all at the platform level.
- **The camera, free.** `vidi` does not exist and needs hardware nobody has
  bought. A phone has two cameras and a face-detection API. Stage 8's
  *usefulness* — QR, OCR, "what is this" — arrives without a purchase, though
  its identity half still needs the enrolment conversation.
- **Presence, free-ish.** Screen state, proximity sensor, and on a TV, whether
  it is on. Stage 12 needs *"is anyone there"* and this is a decent proxy.
- **A test device in every pocket.** Development against real hardware stops
  requiring a flashed image and a reboot — and this repository's memory already
  records that the development box must not be rebooted, because it dual-boots
  to Windows.
- **Reach.** Someone who cannot flash an LFS image can install an APK.

---

## 8. What it takes away

- **The security model as designed.** Real uids, real rlimits, real process
  groups, no store policy, no OEM battery manager. The appliance is the only
  target where `security.md` §5 is literally true.
- **Certainty about being alive.** Android decides what runs. A foreground
  service with a persistent notification is the contract, Doze bends it, and
  some OEM battery managers break it outright. "Started at boot, restarted on
  failure" is an init guarantee on the appliance and a best effort on a phone.
- **Distribution freedom, if it goes through Play.** An app that runs
  agent-generated code, holds the microphone continuously, and wants to be a
  launcher is three separate policy conversations. Sideloading has none of
  them. Since "easy exposure" is the goal, this deserves an early answer:
  **exposure via APK is free; exposure via Play is a project of its own.**
- **The single-image story.** `/etc/os-release` says `InteliBoy 0.14.3` and
  `versions.lock` says what built it. An APK version code is a different
  mechanism and the equivalence has to be rebuilt rather than inherited.

---

## 9. Does the LFS appliance survive this?

Yes, and the question deserves a straight answer rather than a diplomatic one.

They are **two products with one brain**, and they are good at different things.
The appliance is the target where the confinement model is real, where nothing
between the code and the hardware has an opinion, and where an image is
reproducible from a lock file. Android is the target with free hardware, free
audio, free persistence, a camera, and reach.

The risk is not that Android kills the appliance. It is **drift**: Android is
easier to demo, so features get built where they are easy, and eighteen months
later the appliance is a build that still compiles and nobody runs. The guard
against that is the one this repository already has — `make verify`, `make
dirty`, one lock per product, and a rule that a stage is not done until it is
done on the products that claim to support it.

There is also a real possibility worth naming rather than discovering: **Android
TV turns out to be the product and the appliance turns out to be the
laboratory.** That would not be a failure. It would be the LFS work having paid
for a design whose portability was proven by moving it.

---

## 10. Sequence — each step shippable

**T0 — make the platform port real.** `supervise` and `confine` behind an
interface in cogiti; the POSIX implementation is what exists today, moved. No
behaviour changes anywhere.
*Proves it:* the appliance's job and service tests pass unchanged, including
the one that asserts no grandchild survives.

**T1 — avatari on Android.** Fix the morph path to run on GLES 3.0 first, then
`platform_android.c`, no `audio.c`. Driven over an adb-forwarded socket from a
laptop, which needs nothing else to exist.
*Proves it:* `tools/feed.sh` and `avatari-say` drive a head on a phone **and on
a TV bought for fifty dollars**. The TV is the acceptance criterion, not the
phone.

**T2 — reflexi on Android.** NDK build of the existing `.so`, blob as an asset.
*Proves it:* the CLI's own eval, on-device, offline, with the resolve time
measured and in the commit message.

**T3 — cogiti embedded, text-driven.** CPython in the APK, asyncio, ctypes into
reflexi, agent driver in-process, no services yet. Type a question, get a spoken
answer from a rendered head.
*Proves it:* **this is the first shippable Android product** — an offline-
capable assistant with a face, driven by a keyboard or a remote.

**T4 — audi-android.** Platform capture and playback, platform or sherpa ASR,
espeak-ng for phonemes, push-to-talk.
*Proves it:* hands-free on the TV using only the remote's microphone button,
with end-of-speech-to-first-word measured against the appliance's numbers.

**T5 — services.** `isolatedProcess` + the broker, proven with a hand-written
service first (Stage 5a's clock and weather), authoring after.
*Proves it:* a service runs with no network permission, reaches its one
declared host through the broker, and is refused every other one.

**T6 — the TV as a product.** Leanback, D-pad throughout, banner, launcher
behaviour, boot-completed, asset delivery for the head and the voices.
*Proves it:* it is the thing that comes up when the TV is switched on.

---

## 11. Effort, honestly

One person who knows these repositories. Ranges, because two items contain a
genuine unknown.

| | |
|---|---|
| T0 platform port | **2–3 weeks**, and it improves cogiti regardless of Android |
| T1 avatari on Android | **4–6 weeks**, of which the morph path is 1–2 and is the risk |
| T2 reflexi | **~1 week** |
| T3 cogiti embedded | **4–6 weeks**, and the CPython-on-Android integration is the unknown |
| T4 audi-android | **3–4 weeks**, less than the appliance's audi because the platform does the hard part |
| T5 services | **4 weeks** if `isolatedProcess` works as expected; the half-day of investigation in §3.3 decides |
| T6 TV product | **2–3 weeks** |

**T0–T3 is roughly three months to a demonstrable Android product**; the whole
list is around five. That is more than a companion app would have cost and it
produces a device rather than a window.

Two half-days of investigation should happen before any of it, because both can
invalidate an estimate:

1. **Does an embedded CPython run inside an `isolatedProcess`**, fed generated
   code, talking over a pipe? Decides T5 and decides whether Stage 5 exists on
   Android at all.
2. **What is the actual GLES level of the cheap Android TV hardware we care
   about?** Decides whether the morph rewrite is required or merely wise.

---

## 12. The reading this replaces

The first draft read "multiscreen" as a distributed display: cogiti on the
appliance, and surfaces — a phone, a browser — attached over the network
through a fan-out gateway. Recorded here rather than deleted, because it was
wrong in an instructive way and because the pieces of it that were right will
be proposed again.

**Why it was dropped:** it required a listening TCP port on the appliance, a
content-addressed asset channel in the scene protocol, a fix for
`audio_start_ns` across machines, pairing with certificates, a second consumer
for the scene protocol, and a deliberate loosening of `security.md`'s rule that
consent never comes from a screen. Six costs, all of them consequences of a
machine boundary, and the machine boundary was not wanted.

**What was right in it and survives:**

- The **texture-buffer finding** (§4.1) is the same finding and matters more
  here, because Android TV makes it a device-floor question rather than a
  nice-to-have.
- **avatari owes a conformance kit and a fake renderer.** Less urgent now — a
  platform backend is not a second implementation — but a fake renderer is
  still how cogiti is tested without a GPU, and it is still owed.
- **The phone's camera and sensors** (§7) are the cheapest route to `vidi`'s
  usefulness, and that is true whether the phone is a surface or a whole
  device.
- **`user-owned-credentials` still needs an answer**, and on Android it is
  easier: a settings screen is native, and the *"person who has never seen a
  terminal, with a box and a phone"* test is trivially passed when the box is
  the phone.

**What is genuinely dead:** the gateway, `ostendi`, pairing, mTLS, signed
consent from a paired device, one conversation following a person between
rooms. If several rooms is ever wanted, it should be several devices that each
work alone — which is this document — plus, at most, a way for them to notice
each other. That is a later question and it is not this one.

---

## 13. What needs a person

1. **Is Android TV a product or a demo?** If it is a product, T6 is not
   optional and the morph rewrite is required rather than advisable. Everything
   else follows from this and it is the first question.
2. **What happens to Stage 5 on Android (§3.3)?** Defer service birth, accept a
   weaker sandbox, or spend the half-day on `isolatedProcess` first. The
   recommendation is the third, then the first.
3. **Embedded CPython, confirmed?** The alternative is a Kotlin cogiti, which
   should be refused, but it should be refused deliberately rather than by
   omission.
4. **Does the appliance stay a first-class target (§9)?** If yes, every stage
   from here needs to be done twice, and that cost belongs in every estimate
   from now on. If it becomes the laboratory, say so, because it changes what
   `versions.lock` is for.
5. **APK or Play (§8)?** "Easy exposure" reads as Play; Play reads as three
   policy conversations. Worth deciding before T6 rather than after.
