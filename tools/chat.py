#!/usr/bin/env python3
"""Hold a scripted conversation with cogiti, here, and print both sides.

    tools/chat.py                        the default script
    tools/chat.py "hello" "what time is it"
    tools/chat.py --file talk.txt        one utterance per line

The device is a bad place to iterate on how a conversation *reads*. It needs
a person in the room, it answers out loud, and every change is a deploy. This
runs the same brain against the same resolver and the same model, on this
machine, and prints the transcript — so a wording change is a rerun rather
than a trip.

What it deliberately does not test: the microphone, the recogniser, the face,
and anything about being heard. Those only exist on the box. Everything about
what is *said* is here.
"""

import os
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CONF = os.path.join(ROOT, "config", "cogiti.dev.conf")
COGITI = os.path.join(os.path.dirname(ROOT), "cogiti", "bin", "cogiti")

DEFAULT = [
    "hello",
    "my name is Alek and I have a son called Peter",
    "what did I just tell you about him",
    "is it late?",
    "what's your name",
]

#: An escalation detaches at five seconds and is delivered later, so a script
#: that races on is a script that reads the next answer as this one's.
WAIT_S = float(os.environ.get("CHAT_WAIT", "22"))


def main(argv):
    if argv and argv[0] == "--file":
        lines = [l.strip() for l in open(argv[1]) if l.strip()]
    else:
        lines = argv or DEFAULT

    # No renderer and no voice: neither is built here, and both write pages
    # of "falling back to espeak-ng" into the one thing this exists to show.
    #
    # **--attention-s=0, and forgetting it cost an hour.** The dev config sets
    # 60 because the appliance hears a room; typed input is addressed by
    # construction, so the gate has nothing to protect here. Without it this
    # script asked a question, the device correctly decided it had not been
    # spoken to, and printed nothing — which is indistinguishable from the
    # thing under test being broken, and was read that way twice.
    #
    # PYTHONUNBUFFERED is not what fixed that, and is kept because it is
    # right anyway: Python block-buffers stdout when it is not a terminal.
    env = dict(os.environ, PYTHONUNBUFFERED="1")
    p = subprocess.Popen([COGITI, "--conf=" + CONF, "--output=text",
                          "--attention-s=0",
                          "--presentation-adapter=", "--speech-adapter="],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, bufsize=1,
                         env=env, cwd=os.path.join(ROOT, "config"))
    # Printed as it arrives, by the reader thread. Collecting into a list
    # and slicing it after each wait was the first shape and it showed
    # nothing at all for an escalation — a bookkeeping bug in a tool whose
    # entire job is to show you what happened, which is the worst place for
    # one. Streaming has no bookkeeping to get wrong.
    quiet = ("Task was destroyed", "task: <Task", "Exception ignored",
             "Traceback (most", "  File \"", "RuntimeError:", "    self.",
             "    proto.", "    return ", "  ^^^")

    def pump():
        for line in p.stdout:
            line = line.rstrip()
            if line.strip() and not line.startswith(quiet):
                print("  " + line, flush=True)
    threading.Thread(target=pump, daemon=True).start()
    time.sleep(6)

    for said in lines:
        print("\n\033[1m> %s\033[0m" % said, flush=True)
        p.stdin.write(said + "\n")
        p.stdin.flush()
        time.sleep(WAIT_S)

    p.stdin.close()
    p.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
