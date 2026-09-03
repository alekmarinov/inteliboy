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
        said = say(utterance, 40 if sc.get("escalates") else 14)
        if sc.get("settle"):
            # Wait for the detached answer to be spoken before asking the
            # next thing, which is what a person waiting for an answer does.
            said = said + wait_for_delivery(30)
    out.append({"group": sc["group"], "name": sc["name"],
                "says": sc["says"], "heard": said})

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
        why = check(sc, answer)
        if why:
            bad += 1
            print("  FAIL  %-34s %s" % (sc["name"], why))
            print("        said:  %s" % " | ".join(sc["says"]))
            print("        heard: %s" % (answer[:160] or "(nothing)"))
        else:
            print("  ok    %-34s %s" % (sc["name"], answer[:70]))
    print("\n%d scenario(s), %d failed" % (len(plan), bad))
    return 1 if bad else 0


def check(sc, answer):
    """What was wrong, in one sentence, or None."""
    low = answer.lower()
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
