#!/usr/bin/env python3
"""Walk the test plan against a real device, and say what did not hold.

    tools/soak.py 192.168.1.160            everything
    tools/soak.py 192.168.1.160 prices     one group

Runs ON the device, driven from here. It stops the cogiti service, starts one
in the foreground with the text spine — same brain, same resolver, same
providers, same renderer, one input port fewer — puts the scenarios to it, and
puts the service back.

**Text rather than the microphone, and on the device rather than here.** The
mic is a poor instrument for a plan: it is deaf while speaking, so a confirm
cannot be answered in time, and a synthesised voice transcribes far cleaner
than a person, which flatters the recogniser. What the mic uniquely tests —
levels, the recogniser, echo — is a separate list. Everything else wants
determinism *in the real environment*, which is what this is.

Each scenario is what to say and what must be true afterwards. A scenario that
asserts nothing is a scenario that cannot fail.
"""

import json
import subprocess
import sys
import time

REMOTE = "/tmp/soak_run.py"


# --------------------------------------------------------------- the plan --

def S(group, name, says, **checks):
    return dict(group=group, name=name, says=says, **checks)


#: A probe runs on the device after the utterances and its output is asserted.
#: Some things are not sayable — what is on screen, who owns a directory, what
#: a process runs as — and a plan that only listens can only test half of it.
SCENE = (
    "python3 -c \"import socket,json;"
    "s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);"
    "s.connect('/run/avatari.sock');f=s.makefile('rwb',buffering=0);"
    "f.write(b'{\\\"v\\\":1,\\\"op\\\":\\\"hello\\\",\\\"name\\\":\\\"soak\\\"}\\n');"
    "f.readline();"
    "f.write(b'{\\\"v\\\":1,\\\"op\\\":\\\"query\\\"}\\n');"
    "d=json.loads(f.readline());"
    "print(' '.join(o['id']+'@'+o['region'] for o in d.get('objects',[])) or 'EMPTY')\""
)

PLAN = [
    # --- what it knows about itself -------------------------------------
    S("self", "the time", ["what time is it"], intent="get_time"),
    S("self", "the date", ["what is the date"], intent="get_date"),
    S("self", "its address", ["what's my ip"], intent="get_ip",
      answer_has="."),
    S("self", "its uptime", ["how long have you been running"],
      intent="get_uptime"),
    S("self", "its name", ["what is your name"], intent="get_hostname"),
    S("self", "free space", ["how much space is left"], intent="get_disk"),
    S("self", "whether it hears", ["can you hear me"], intent="hearing_check",
      answer_has="hear"),
    S("self", "its battery", ["what is the battery level"],
      intent="get_battery"),

    # --- the outside world ----------------------------------------------
    S("prices", "bitcoin", ["what is the bitcoin price"], intent="get_price",
      answer_has="dollars", not_answer_has="I couldn't"),
    S("prices", "ethereum", ["what is ethereum trading at"],
      intent="get_price", answer_has="dollars"),
    S("prices", "a share is refused honestly", ["how is apple stock doing"],
      intent="get_price", answer_has="couldn't find"),
    S("weather", "here", ["what is the weather"], intent="get_weather",
      answer_has="degrees"),
    S("weather", "somewhere else", ["what is the weather in London"],
      intent="get_weather", answer_has="London"),

    # --- commands that do something -------------------------------------
    S("control", "louder", ["turn the volume up"], intent="volume_up"),
    S("control", "quieter", ["turn the volume down"], intent="volume_down"),
    S("control", "greeting", ["hello"], intent="greeting"),
    S("control", "thanks", ["thank you"], intent="thanks"),
    S("control", "repeat", ["what time is it", "what did you say"],
      intent="repeat"),
    S("control", "stop with nothing running", ["stop"], intent="stop",
      answer_has="Nothing to stop"),

    # --- conversation ----------------------------------------------------
    S("talk", "an open question", ["why is the sky blue"], escalates=True),
    # Escalations detach at five seconds and the answer is delivered later,
    # so a scenario that asks twice in a row measures the *first* answer
    # landing during the second question. `settle` waits for the delivery
    # before moving on, which is what a person does.
    S("talk", "a follow up keeps the topic",
      ["why is the sky blue", "and at sunset"], escalates=True, settle=True,
      answer_has_any=["sunset", "red", "orange", "longer", "scatter"]),
    S("talk", "a new topic is not contaminated",
      ["why is the sky blue", "how tall is Everest"], escalates=True,
      settle=True, answer_has_any=["Everest", "metres", "meters", "feet",
                                   "8,8", "29,0"]),
    S("talk", "one word noise is ignored", ["mmm"], silent=True),

    # --- services ---------------------------------------------------------
    S("services", "nothing pinned yet", ["what is pinned"],
      intent="list_services"),
    S("services", "what are you doing", ["what are you doing"],
      intent="what_are_you_doing"),
    S("services", "is anything broken", ["is anything broken"],
      intent="service_status"),

    # --- jobs --------------------------------------------------------------
    S("jobs", "nothing running", ["what jobs are running"],
      intent="list_jobs", answer_has="Nothing"),

    # --- the screen, asserted rather than eyeballed -------------------------
    # A presentation template draws a *group* with children, so the id
    # follows the template — brain/clock, brain/ip — and is not a fixed
    # brain/answer. Counting "brain/" counts the children too, which is why
    # the top-level count is its own check.
    S("screen", "an answer is drawn", ["what time is it"],
      after=SCENE, probe_has="brain/clock@stage"),
    S("screen", "one answer at a time",
      ["what time is it", "what is the date"],
      after=SCENE, probe_top_once="brain/"),
    S("screen", "a clock card leaves after its twelve seconds",
      ["what time is it"], settle_s=16,
      after=SCENE, probe_not_has="brain/clock"),
    S("screen", "an ip card is still there when the clock would have gone",
      ["what's my ip"], settle_s=16,
      after=SCENE, probe_has="brain/ip@stage"),
    # A slow question, because a local command answers in a second and the
    # answer replaces the caption before anything could look at it.
    S("screen", "the transcript is drawn while it thinks",
      ["why is the sky blue"], escalates=True, probe_during=SCENE,
      during_has="brain/heard@stage"),

    # --- a service, born and removed ---------------------------------------
    S("life", "a service is born",
      ["keep the clock on screen", "yes", "yes"], escalates=True,
      after="ls /var/lib/cogiti/services", probe_has="clock"),
    S("life", "it runs as its own account", [],
      after="ps -eo user,args= | grep 'main[.]py' | head -1",
      probe_has="cogiti-"),
    # The name is the model's choice — it produced "clock-display" once and
    # "clock" another time — so the probes find the directory rather than
    # assuming what it is called.
    S("life", "its approval verifies", [],
      after=("python3 -c \"import sys,glob;sys.path.insert(0,'/usr/lib/cogiti');"
             "from cogiti import approval;"
             "print([approval.verify(d) for d in "
             "glob.glob('/var/lib/cogiti/services/*')])\""),
      probe_has="(true"),
    S("life", "it owns its own directory", [],
      after="ls -ld /var/lib/cogiti/services/*",
      probe_has="cogiti-service"),
    S("life", "it is pinned to the periphery", [],
      after=SCENE, probe_has="clock/main@periphery"),
    S("life", "it is removed on request",
      ["remove the clock", "yes"],
      after="ls /var/lib/cogiti/services; echo ---; ls /var/lib/cogiti/removed",
      probe_not_has="services: clock", probe_has="clock-"),
]


# ------------------------------------------------------------- the runner --

DRIVER = r'''
import json, subprocess, sys, threading, time

scenarios = json.loads(sys.stdin.readline())
subprocess.run(["/etc/rc.d/init.d/cogiti", "stop"], capture_output=True)
time.sleep(2)

p = subprocess.Popen(
    ["/usr/bin/cogiti", "--conf=/etc/cogiti.conf", "--output=text",
     "--speech-in-adapter="],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    text=True, bufsize=1)

lines, lock = [], threading.Lock()
def pump():
    for line in p.stdout:
        with lock:
            lines.append(line.rstrip())
threading.Thread(target=pump, daemon=True).start()
time.sleep(8)                      # startup: resolver, table, services

def say(text, wait):
    with lock:
        start = len(lines)
    p.stdin.write(text + "\n"); p.stdin.flush()
    deadline = time.time() + wait
    while time.time() < deadline:
        time.sleep(0.3)
        with lock:
            got = [l for l in lines[start:] if l.strip()]
        # An answer has landed once something non-empty appeared and the
        # stream has been quiet for a moment.
        if got and time.time() > deadline - wait + 2.5:
            break
    with lock:
        return [l for l in lines[start:] if l.strip()]

def wait_for_delivery(seconds):
    with lock:
        start = len(lines)
    deadline = time.time() + seconds
    while time.time() < deadline:
        time.sleep(0.5)
        with lock:
            got = [l for l in lines[start:] if l.strip()]
        if any(l.startswith("About ") or "delivering" in l for l in got):
            time.sleep(2.0)          # let the whole sentence land
            with lock:
                return [l for l in lines[start:] if l.strip()]
    with lock:
        return [l for l in lines[start:] if l.strip()]


out = []
for sc in scenarios:
    said = []
    for utterance in sc["says"]:
        if sc.get("probe_during"):
            with lock:
                start = len(lines)
            p.stdin.write(utterance + "\n"); p.stdin.flush()
            time.sleep(1.2)              # mid-turn: the caption is up
            r = subprocess.run(["sh", "-c", sc["probe_during"]],
                               capture_output=True, text=True, timeout=20)
            sc["_during"] = (r.stdout + r.stderr).strip()
            time.sleep(12)
            with lock:
                said = [l for l in lines[start:] if l.strip()]
            continue
        said = say(utterance, 40 if sc.get("escalates") else 14)
        if sc.get("settle"):
            # Wait for the detached answer to be spoken before asking the
            # next thing, which is what a person waiting for an answer does.
            said = said + wait_for_delivery(30)
    if sc.get("settle_s"):
        time.sleep(sc["settle_s"])
    probe = ""
    if sc.get("after"):
        r = subprocess.run(["sh", "-c", sc["after"]], capture_output=True,
                           text=True, timeout=30)
        probe = (r.stdout + r.stderr).strip()
    out.append({"group": sc["group"], "name": sc["name"],
                "says": sc["says"], "heard": said, "probe": probe,
                "during": sc.get("_during", "")})

p.stdin.close()
time.sleep(1)
p.terminate()
subprocess.run(["/etc/rc.d/init.d/cogiti", "start"], capture_output=True)
print("=SOAK=" + json.dumps(out))
'''


def as_root(host):
    """Accept "1.2.3.4" or "root@1.2.3.4", like every other tool here.

    drift.sh took one form and verify-device.sh the other, which cost two
    mistakes in five minutes. This one accepts both because a runner that is
    fussy about its address is a runner nobody starts.
    """
    return host if "@" in host else "root@" + host


def ssh(host, *args):
    return ["ssh", "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null", as_root(host)] + list(args)


def run(host, group=None):
    plan = [s for s in PLAN if not group or s["group"] == group]
    if not plan:
        print("no scenarios in group %r" % group)
        return 1

    # Written to a real file first: scp from /dev/stdin is not portable and
    # fails with "Connection closed", which reads like a network problem and
    # is not one.
    import tempfile, os
    fd, local = tempfile.mkstemp(suffix=".py")
    with os.fdopen(fd, "w") as f:
        f.write(DRIVER)
    try:
        subprocess.run(["scp", "-q", "-o", "StrictHostKeyChecking=no",
                        "-o", "UserKnownHostsFile=/dev/null", local,
                        "%s:%s" % (as_root(host), REMOTE)], check=True)
    finally:
        os.unlink(local)

    proc = subprocess.run(ssh(host, "python3", REMOTE),
                          input=json.dumps(plan) + "\n",
                          capture_output=True, text=True,
                          timeout=60 + 45 * len(plan))
    marker = [l for l in proc.stdout.splitlines() if l.startswith("=SOAK=")]
    if not marker:
        print("the device produced no result:")
        print(proc.stdout[-2000:] or proc.stderr[-2000:])
        return 2
    results = json.loads(marker[0][len("=SOAK="):])
    return report(plan, results)


def report(plan, results):
    bad = 0
    group = None
    for sc, got in zip(plan, results):
        if sc["group"] != group:
            group = sc["group"]
            print("\n%s" % group)
        answer = " ".join(got["heard"])
        sc["_during"] = got.get("during", "")
        why = check(sc, answer, got.get("probe", ""))
        if why:
            bad += 1
            print("  FAIL  %-34s %s" % (sc["name"], why))
            print("        said:  %s" % " | ".join(sc["says"]))
            print("        heard: %s" % (answer[:160] or "(nothing)"))
        else:
            print("  ok    %-34s %s" % (sc["name"], answer[:70]))
    print("\n%d scenario(s), %d failed" % (len(plan), bad))
    return 1 if bad else 0


def check(sc, answer, probe=""):
    """What was wrong, in one sentence, or None."""
    low = answer.lower()
    plow = probe.lower()
    if sc.get("probe_has") and sc["probe_has"].lower() not in plow:
        return "expected %r on the device, saw %r" % (sc["probe_has"],
                                                      probe[:90])
    if sc.get("probe_not_has") and sc["probe_not_has"].lower() in plow:
        return "did not expect %r on the device" % sc["probe_not_has"]
    if sc.get("probe_top_once"):
        # Top level only: a template draws a group and its children share the
        # prefix, so counting every id counts one answer several times.
        tops = [w for w in probe.split()
                if w.lower().startswith(sc["probe_top_once"].lower())
                and "#" not in w]
        if len(tops) != 1:
            return "expected one answer on screen, found %d: %s" % (
                len(tops), " ".join(tops) or "none")
    if sc.get("during_has") and sc["during_has"].lower() not in (
            sc.get("_during") or "").lower():
        return "expected %r while listening, saw %r" % (
            sc["during_has"], (sc.get("_during") or "")[:90])
    if sc.get("says") == [] :
        return None                      # a probe-only scenario
    if sc.get("silent") and answer.strip():
        return "expected silence, got an answer"
    if sc.get("answer_has") and sc["answer_has"].lower() not in low:
        return "expected %r in the answer" % sc["answer_has"]
    if sc.get("not_answer_has") and sc["not_answer_has"].lower() in low:
        return "did not expect %r in the answer" % sc["not_answer_has"]
    if sc.get("answer_has_any") and not any(
            w.lower() in low for w in sc["answer_has_any"]):
        return "expected one of %s" % ", ".join(sc["answer_has_any"])
    if not sc.get("silent") and not answer.strip():
        return "said nothing"
    return None


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(run(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None))
