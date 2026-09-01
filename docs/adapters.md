# Adapters

cogiti defines six ports (`../../cogiti/docs/ports.md`). This is what InteliBoy
puts in each one. It is the whole of the binding between a general orchestrator
and this particular appliance.

| port | InteliBoy's implementation | required |
|---|---|---|
| resolver | **reflexi** — C11, linked in-process, ~16 µs, no network | supplied |
| presentation | **avatari** — a 3D talking head over a retained scene protocol on a Unix socket | supplied |
| speech | **audi** — whisper.cpp in, Piper/espeak-ng out, viseme timings | planned |
| perception | **vidi** — camera, QR, OCR, face and speaker identity | planned |
| agent | **agenti** — a subprocess per job, first driver a coding-agent SDK | planned, required |
| platform | **the LFS appliance** — sysvinit, no container runtime, a writable data partition | partial |

## What each binding costs

**reflexi → resolver.** A near-perfect fit: reflexi returns a decision and
never acts, which is exactly what the port asks. Two things it owes: a shared
library so cogiti can bind it, and eventually a runtime-loadable pattern
overlay so a service born at 3pm can be reached by voice without recompiling a
blob. Patterns are matched deterministically, so an overlay needs no model on
the device — which is why this is the cheap answer rather than the expensive
one.

**avatari → presentation.** Also close, because the port was written from it.
It already gives caller-chosen ids, upsert, per-connection ownership, two
regions, last-write-wins and graceful degradation of unknown kinds — the six
things the port requires. What it still owes InteliBoy specifically: a `chart`
kind and a `list` kind, both designed and unbuilt, and a fake renderer so
cogiti is testable without a GPU.

**audi → speech.** Does not exist. Longest lead time of anything planned, and
entirely independent of cogiti — it can be developed against a microphone. The
prior art is already in avatari's `tools/say.c`, `say-piper.sh` and
`speak.sh`, which do the espeak/Piper/Azure tiering and the viseme mapping;
audi is that work made into a daemon, plus VAD, plus a wake word.

**vidi → perception.** Does not exist. Needs only a camera. Its least
glamorous event — `presence` — is the one proactivity depends on, because a
device that talks to an empty room is a device people unplug.

**agenti → agent.** Does not exist and is required. The one port with a model
behind it. A subprocess per job so cancellation is a signal to a process group
rather than a hope.

**The LFS appliance → platform.** The weakest binding, and the one with a hard
gap: cogiti requires *a writable path that survives a system update*, and the
appliance is a single read-only root image today. Services an agent wrote and
everything the device remembers are exactly what a new image would destroy.
**A separate data partition is required before services ship**, and it belongs
to the lfs repository.

Confinement is the other half: there is no container runtime in the image and
adding one costs more than it buys. cogiti asks for a uid and resource limits,
not a runtime, which the appliance can give.

## The rule this file exists to hold

**Anything device-specific goes here or in a component, never into cogiti.**
If a change to cogiti names avatari, DRM, an LFS package or InteliBoy, it is in
the wrong repository — unless it is adding or amending a port.

The reverse test is just as useful: if something in this file could be true of
a different appliance, it probably belongs in cogiti as a port requirement
instead.
