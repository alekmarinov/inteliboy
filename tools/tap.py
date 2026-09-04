#!/usr/bin/env python3
"""Watch what cogiti actually says to avatari.

    tools/tap.py &                       listens on /tmp/avatari-tap.sock
    make talk SOCK=/tmp/avatari-tap.sock

A Unix socket proxy: it listens on one path, connects to the renderer's real
one, forwards both directions and prints every line. The renderer sees a normal
client and cogiti sees a normal renderer, so nothing has to be instrumented to
watch it — which matters, because the interesting failures are the messages
that were never sent.

Long fields are shortened: a `speak` carries every viseme, and 65 of them
scrolls the one thing you wanted to see off the screen.
"""

import json
import os
import socket
import sys
import threading
import time

LISTEN = os.environ.get("TAP_SOCKET", "/tmp/avatari-tap.sock")
UPSTREAM = os.environ.get("AVATARI_SOCKET", "/tmp/avatari.sock")

#: With no renderer to forward to, print and stop there. Set by --sink, and
#: also whenever the upstream socket is simply not there — which is the
#: common case on a workstation and produced "cannot reach /tmp/avatari.sock"
#: once per connection and nothing else useful.
SINK = "--sink" in sys.argv or not os.path.exists(UPSTREAM)
T0 = time.monotonic()


def brief(raw):
    try:
        m = json.loads(raw)
    except ValueError:
        return raw[:160]
    v = m.get("visemes")
    if isinstance(v, list) and len(v) > 3:
        m["visemes"] = "[%d marks, %.2fs]" % (len(v), v[-1][0])
    for k in ("text", "append", "fallback"):
        if isinstance(m.get(k), str) and len(m[k]) > 60:
            m[k] = m[k][:57] + "..."
    return json.dumps(m, separators=(",", ":"))


def pump(src, dst, arrow, stop):
    buf = b""
    try:
        while not stop.is_set():
            data = src.recv(65536)
            if not data:
                return
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if line.strip():
                    print("%7.3f %s %s" % (time.monotonic() - T0, arrow,
                                           brief(line.decode("utf-8", "replace"))),
                          flush=True)
            dst.sendall(data)
    except OSError:
        return
    finally:
        stop.set()
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def sink(client):
    """Print what was sent and answer nothing else.

    A renderer is not always the point. Asking "what would the face be told"
    while reading a conversation in a terminal does not need a face, and
    building one to find out is a poor trade — `make chat SHOW=1` runs this
    instead.

    The hello is answered because the real one answers it: cogiti reads the
    renderer's capabilities from that reply, and an adapter that stays silent
    is treated as one that can do nothing. Left unanswered it also costs a
    socket timeout on every connect, which is a second of nothing before the
    first op appears.
    """
    print("%7.3f -- connection opened (sink)" % (time.monotonic() - T0),
          flush=True)
    buf = b""
    try:
        while True:
            data = client.recv(65536)
            if not data:
                return
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip():
                    continue
                text = line.decode("utf-8", "replace")
                print("%7.3f cogiti -> %s" % (time.monotonic() - T0,
                                              brief(text)), flush=True)
                if '"hello"' in text:
                    client.sendall(b'{"v":1,"event":"hello","kinds":'
                                   b'["text","image","group","stream"]}\n')
    except OSError:
        return
    finally:
        print("%7.3f -- connection closed" % (time.monotonic() - T0),
              flush=True)
        try:
            client.close()
        except OSError:
            pass


def serve(client):
    if SINK:
        return sink(client)
    try:
        up = socket.socket(socket.AF_UNIX)
        up.connect(UPSTREAM)
    except OSError as e:
        print("tap: cannot reach %s: %s" % (UPSTREAM, e), file=sys.stderr)
        client.close()
        return
    print("%7.3f -- connection opened" % (time.monotonic() - T0), flush=True)
    stop = threading.Event()
    threading.Thread(target=pump, args=(client, up, "cogiti ->", stop),
                     daemon=True).start()
    pump(up, client, "      <- avatari", stop)
    print("%7.3f -- connection closed" % (time.monotonic() - T0), flush=True)


def main():
    if os.path.exists(LISTEN):
        os.unlink(LISTEN)
    srv = socket.socket(socket.AF_UNIX)
    srv.bind(LISTEN)
    srv.listen(4)
    print("tap: %s %s" % (LISTEN, "(sink: nothing downstream)" if SINK
                          else "-> " + UPSTREAM), file=sys.stderr)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=serve, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()
