#!/usr/bin/env python3
"""Read — and re-issue — exactly what was sent to the model.

    tools/llm-dump.py <host>                 what is on the device
    tools/llm-dump.py <host> latest          fetch the newest and summarise
    tools/llm-dump.py <host> latest --full   with the system prompt and
                                             every message in full
    tools/llm-dump.py <file.json> --replay   send step 0 again, verbatim
    tools/llm-dump.py <file.json> --replay --step 1

The dump is written by the adapter (`--dump <dir>` in `agent_adapter`) and
holds the exact keyword arguments of each API call beside the exact response.
That is the point of it: a replay is `create(**request)` rather than a
reconstruction from prose, so "it answered oddly" becomes a thing that can be
run again with one line changed.

Three faults in one evening were all the same shape — a strange sentence out
loud, and the cause in a payload nobody could see. The trace said which tools
were called. It never said what the model was given.
"""

import json
import os
import subprocess
import sys

SSH = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
       "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=10"]
REMOTE = "/var/log/cogiti-llm"


def as_root(host):
    return host if "@" in host else "root@" + host


def on(host, *cmd):
    r = subprocess.run(["ssh"] + SSH + [as_root(host)] + list(cmd),
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit("ssh failed: %s" % (r.stderr.strip() or r.returncode))
    return r.stdout


def summarise(d, full=False):
    print("model    %s" % d.get("model"))
    print("started  %s" % d.get("started"))
    print("prompt   %s" % json.dumps(d.get("prompt"))[:400])
    # Names alone were not enough and hid the thing worth reading: the whole
    # question of what the model could reach lives inside the `device` tool's
    # enum, and printing "device" said nothing about whether it held twenty
    # commands or thirty-three.
    for t in d.get("tools") or []:
        enum = ((t.get("input_schema") or {}).get("properties") or {}) \
            .get("command", {}).get("enum")
        print("tool     %s%s" % (t.get("name"),
                                 " — %d command(s)" % len(enum) if enum else ""))
        if enum:
            print("         %s" % ", ".join(enum))
        if full and t.get("description"):
            print("         %s" % t["description"])
    if full:
        print("\n--- system ---\n%s" % d.get("system"))
    for i, s in enumerate(d.get("steps") or []):
        msgs = s["request"].get("messages") or []
        r = s.get("response") or {}
        print("\nstep %d   %d message(s), stop=%s" % (i, len(msgs),
                                                      r.get("stop_reason")))
        u = r.get("usage") or {}
        if u:
            print("         in=%s out=%s" % (u.get("input_tokens"),
                                             u.get("output_tokens")))
        if full:
            for m in msgs:
                print("  [%s] %s" % (m.get("role"),
                                     json.dumps(m.get("content"))[:2000]))
        for c in s.get("tool_calls") or []:
            print("  -> %s %s" % (c.get("name"), json.dumps(c.get("args"))))
            print("     = %s" % json.dumps(c.get("result"))[:600])
    print("\noutcome  %s" % json.dumps(d.get("outcome"))[:600])


def replay(path, step):
    """Send one recorded request again. Costs a real call, so it says so."""
    try:
        import anthropic
    except ImportError:
        sys.exit("no anthropic package here; run this from "
                 "adapters/anthropic/.venv, or copy the dump somewhere that "
                 "has it")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("ANTHROPIC_API_KEY is not set; cogiti grants it on the "
                 "device and this runs here")
    d = json.load(open(path))
    steps = d.get("steps") or []
    if step >= len(steps):
        sys.exit("this dump has %d step(s)" % len(steps))
    request = steps[step]["request"]
    print("replaying step %d of %s (a real, billed call)" % (step, path),
          file=sys.stderr)
    out = anthropic.Anthropic().messages.create(**request)
    print(json.dumps(out.model_dump(), indent=1, default=str))


def main(argv):
    if not argv:
        sys.exit(__doc__)
    target, rest = argv[0], argv[1:]
    full = "--full" in rest
    if "--replay" in rest:
        step = 0
        if "--step" in rest:
            step = int(rest[rest.index("--step") + 1])
        return replay(target, step)
    if os.path.exists(target):
        return summarise(json.load(open(target)), full)

    listing = on(target, "ls -1 %s 2>/dev/null" % REMOTE).split()
    if not listing:
        sys.exit("no dumps in %s — is `--dump %s` on the agent_adapter line "
                 "of /etc/cogiti.conf?" % (REMOTE, REMOTE))
    if not rest or rest[0].startswith("--"):
        print("\n".join(listing))
        print("\n%d dump(s). `latest` to read the newest." % len(listing))
        return
    name = listing[-1] if rest[0] == "latest" else rest[0]
    summarise(json.loads(on(target, "cat %s/%s" % (REMOTE, name))), full)


if __name__ == "__main__":
    main(sys.argv[1:])
