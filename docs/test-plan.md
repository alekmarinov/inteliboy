# The end-to-end test plan

What a person should be able to do with this device, in order, with what to
look for and how it is checked. Written after an evening of finding bugs by
watching a live trace, which caught three real ones and is not a plan.

**Three statuses, and they are the point of this document.** A plan that
tests features which do not exist is worse than none: it produces failures
that are not defects and hides the ones that are.

| | |
|---|---|
| **works** | built, and expected to pass today |
| **partial** | works in a way that will disappoint; the gap is named |
| **absent** | not built. The stage it belongs to is named |

Verified three ways, all available now: the **trace**
(`/var/log/cogiti-trace.jsonl` — what was heard, how it resolved, how the turn
ended), a **screenshot** (avatari's `screenshot` op, since 0.3.0), and **ssh**
for state. Driven through the text spine for determinism, and through the
microphone only where the microphone is the thing under test.

---

## 1. Conversation

### 1.1 A question the device cannot answer from itself — **works**
Say: *"why is the sky blue?"*
Expect: transcript on screen while speaking; a spoken answer in 7–25 s; the
answer replaces the transcript; the card leaves after ~10 s.
Check: trace `verdict=escalate outcome=done`; screenshot mid-turn shows the
caption, after shows the answer.

### 1.2 Following up on the same topic — **works**
Say: *"why is the sky blue?"* then *"and at sunset?"*
Expect: the second answer refers to the first. cogiti passes the recent turns
as context.
Check: the answer mentions scattering/sunset without re-explaining.

### 1.3 Changing topic without contamination — **partial**
Say: *"why is the sky blue?"* then *"how tall is Everest?"*
Expect: the second answer is about Everest and does not mention the sky.
**The gap:** there is no topic model. cogiti sends the last N turns verbatim,
so the model is *free* to conflate them and nothing prevents it. This is the
scenario most likely to fail and the one worth measuring before Stage 6, which
is where memory and its provenance rules land.

### 1.4 Interrupting it mid-sentence — **partial**
Say something long, then talk over the answer.
**The gap:** the device is half duplex — deaf while speaking — because echo
cancellation measures 0.9 dB on this hardware against the ~20 dB a detector
needs. Barge-in is implemented and cannot be exercised until that is solved.

### 1.5 Room noise is ignored — **works** (new)
Make a noise: *"mmm"*, *"uh"*.
Expect: the transcript appears; nothing is said; no model call.
Check: trace shows the turn ending without escalation.

---

## 2. Things the device knows about itself

### 2.1 The ones that work — **works**
| say | expect |
|---|---|
| "what's my IP" | spoken address, card with an `ssh` line, stays 45 s |
| "how long have you been running" | uptime, rounded as a person would say it |
| "what is your name" | hostname |
| "how much space is left" | free space |
| "what time is it" / "what's the date" | clock, card |
| "can you hear me" | "Yes, I can hear you." |
Check: trace `verdict=handle`, `ms` under ~10 (resolution is 0–8 ms; the rest
is speech).

### 2.2 CPU and memory — **partial**
`device.memory` and `device.load` exist and are readable **by a service**, so
"keep the memory usage on screen" works. There is **no intent** for asking
aloud: *"how much memory is in use"* reaches the model unless a service has
claimed that phrase.
Fix: two intents and two table entries; small.

### 2.3 MAC address — **absent**
No provider. Same shape as `device.ip`; an afternoon.

### 2.4 Battery — **partial**
`get_battery` resolves and has **no command**, so it escalates and the model
guesses. Either implement it or remove the intent; a device that answers a
question about itself from a language model is the failure `device.py` was
written to end.

---

## 3. Prices and the outside world

### 3.1 Crypto and stock prices — **partial, and the worst item here**
Say: *"what's the bitcoin price?"*
What happens: `get_price` resolves, finds **no command**, escalates, and the
model answers **from training data** — a confident, stale number with nothing
to say it is a guess.
This is worse than an error. Two ways out, both real: a `price` provider with
an allow-listed endpoint, or leaning on the service path, which already works
("keep the bitcoin price on screen" builds a live one).

### 3.2 Weather — **partial**
`get_weather` resolves, has no command, escalates; the model correctly says it
has no weather access. Honest, and useless. `open-meteo` needs no key and is
already proven through the service path.

---

## 4. Services

### 4.1 Birth — **works**
Say: *"keep the bitcoin price on screen"* → "are you sure?" → *"yes"* →
it writes the service, proves it runs, reads out what it does, what it reads,
and every phrase it will answer to → *"yes"*.
Check: `/var/lib/cogiti/services/<name>/` exists, owned by `cogiti-service`,
with an `approved` file that verifies; a screenshot shows the panel.

### 4.2 A local one, offline — **works**
*"keep the clock on screen"* — no network, no key, `allow = []`.

### 4.3 Live updating — **works**
Two screenshots a minute apart show a changed value.

### 4.4 Reaching it by voice — **works**
Say one of its phrases; answered from the service with no model call.

### 4.5 Removal — **works**
*"remove the clock"* → confirm → gone from `services/`, present in `removed/`,
panel disappears.

### 4.6 Surviving a restart — **works, needs care**
`/etc/rc.d/init.d/cogiti restart` — services come back.
**Never reboot this device**: it dual-boots to Windows and needs physical
access to return.

### 4.7 Crash handling — **works**
Break a service's `main.py`; three failures in a minute stop it and mark it
`needs-attention`; *"is anything broken"* reports it.

---

## 5. Jobs

### 5.1 A slow question detaches — **works**
Ask something slow; at 5 s it says so and the turn ends; the answer arrives at
the end of a later turn, named by its question.

### 5.2 Asking what it is doing — **works**
*"what are you doing"* → "nothing at the moment", or what is running.

### 5.3 Streaming logs — **partial**
`job_logs` exists and shows a job's last lines as a `stream` with
`attention: watch`. **The gap:** the only jobs are escalations, which produce
few lines, so there is nothing worth watching. It becomes real when a job does
something long — which is Stage 4's `needs-input` and beyond.

### 5.4 Cancelling — **partial**
*"cancel that job"* confirms and cancels when one is running; with several it
asks which, and cannot yet be told *"the repository one"*.

---

## 6. The screen

### 6.1 The transcript — **works** (new)
Words appear as they are spoken, small, with the face looking away from them.

### 6.2 One answer at a time — **works**
Ask twice; the second replaces the first rather than sitting beside it.

### 6.3 Cards leave — **works**
Default 10 s after speaking ends; 45 s for an address; `linger = 0` stays.

### 6.4 Products, comparisons, images and specs — **absent**
The protocol has an `image` kind and presentation templates accept it, and
**nothing produces one**: there is no fetching, no comparison, no shopping.
This is Stage 7 (credentials and external tools) plus a presentation template,
and it is the largest absent item on this list.

### 6.5 Camera on and off — **absent in cogiti**
avatari has it: a `camera` object opens the device, destroying it closes it,
and an indicator that cannot be disabled says so. cogiti has **no intent and
no control**, so it cannot be asked for. Stage 8.

---

## 7. What holds it together

### 7.1 The device matches a build — **works**
`tools/drift.sh 192.168.1.160` — names every hand-patched file.

### 7.2 The image contains what it claims — **works**
`tools/verify-image.sh build/image.img` — 29 checks.

### 7.3 A booted device works — **works**
`tools/verify-device.sh 192.168.1.160` — 14 checks.

---

## The order worth doing it in

1. **§3.1 and §2.4** — the device answering questions about prices and its own
   battery from a language model is the most damaging thing on this list,
   because the answers are confident and wrong.
2. **§1.3** — topic contamination, measured before Stage 6 rather than after.
3. **§2.2 and §2.3** — cheap intents for what the providers already read.
4. Then the soak runs §1–§7 on a cycle and reports what moved.
