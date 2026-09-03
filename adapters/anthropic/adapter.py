#!/usr/bin/env python3
"""An agent adapter for the Anthropic Messages API.

Speaks `cogiti/docs/agent-protocol.md` on stdin and stdout, and the Messages
API outbound. It belongs to this repository rather than to cogiti: cogiti names
no implementation of any port, and choosing a model is a deployment's decision.

Three things about it are decided by the protocol rather than by taste.

**It does not execute tools.** The SDK's tool runner would, and that is exactly
what the port forbids: cogiti runs the tools and the adapter asks. So this is
a manual agentic loop — a `tool_use` block becomes a `tool` event, cogiti
brokers it, and the answer comes back as a `tool_result` on stdin and goes into
the conversation. Every request to the network passes through cogiti's egress
broker, which it could not do if the SDK were calling functions here.

**The result is structured because a tool makes it so.** The model finishes by
calling `answer`, whose schema has `say`, `show` and `did`. Asking for prose
and parsing it afterwards is the thing `ports.md` refuses — "the presentation
layer, not the model, decides what a result looks like" — and a strict tool
schema is the mechanism that makes it true rather than hoped for.

**The key comes from the environment and nothing else.** cogiti reads it from
its store and injects it at spawn. This process never learns where it is kept,
which is what lets the store move without the adapter changing.
"""

import datetime
import json
import os
import sys
import threading
import uuid

import anthropic

V = 1
MODEL = os.environ.get("COGITI_MODEL", "claude-opus-5")
MAX_TOKENS = 8000

# Adaptive thinking, on by default. It costs latency, which an appliance that
# answers out loud can least afford — but the protocol has a `thought` event and
# avatari has a face to put it on, and a head that shows it is working is worth
# more than a head that is silent for four seconds. COGITI_THINKING=off for a
# deployment that would rather have the seconds back.
THINKING = os.environ.get("COGITI_THINKING", "adaptive") != "off"

ANSWER_TOOL = {
    "name": "answer",
    "description": (
        "Give the final answer. Call this exactly once, when you are done. "
        "Do not write the answer as ordinary text — it is only delivered "
        "through this tool."
    ),
    "strict": True,
    "input_schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["say"],
        "properties": {
            "say": {
                "type": "string",
                "description": "One or two sentences to be spoken aloud. No "
                               "lists, no markdown, no headings — this is read "
                               "out by a speech engine.",
            },
            "show": {
                "type": "string",
                "description": "Optional. A short line to display alongside, "
                               "if a screen is present.",
            },
            "did": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Optional. What was actually done, one short "
                               "phrase each, for the record.",
            },
        },
    },
}

SYSTEM = (
    "You are the reasoning behind a voice appliance. You are not talking to a "
    "terminal: what you say is spoken aloud by a speech engine and, sometimes, "
    "shown on a small screen.\n\n"
    "Finish by calling the `answer` tool. Never write the answer as ordinary "
    "text — text you write outside a tool call is discarded, so an answer "
    "written that way is an answer nobody hears.\n\n"
    "`say` is heard, not read: no bullet points, no markdown, no headings, no "
    "URLs read out character by character. Short sentences. If a number is "
    "long, round it the way a person would say it.\n\n"
    "**When the `device` tool can do the thing, do it — do not describe it.** "
    "The person is talking to the appliance, not about it: \"turn it up a "
    "bit\" wants the volume changed, not a sentence about changing it, and "
    "\"what time is it here\" wants this device's clock rather than your "
    "guess. Say what happened afterwards, in the past tense, briefly. If a "
    "command comes back refused, say so plainly rather than claiming it "
    "worked."
)


# ------------------------------------------------------------------ dump --

#: Dumps to keep. An appliance with four gigabytes free and one file per
#: escalation fills its own disk in a week of being talked to, and the failure
#: mode of that is the device stopping rather than the debugging getting
#: harder. Oldest go first: a fault being chased is a fault that just
#: happened.
KEEP = int(os.environ.get("COGITI_DUMP_KEEP", "200"))


def prune(directory, keep):
    try:
        names = sorted(n for n in os.listdir(directory) if n.endswith(".json"))
        for n in names[:max(0, len(names) - keep)]:
            os.remove(os.path.join(directory, n))
    except OSError:
        pass


class Dump:
    """Everything sent to the model and everything it sent back.

    Debugging this from the outside was guesswork. The trace says a turn
    escalated and which tools were called; it does not say what the model was
    *given* — and today three separate faults were all of that shape. A
    confirm the model had no record of. A command it did not know existed. An
    answer it produced because the history handed it half an exchange. In
    each case the visible symptom was a strange sentence and the cause was in
    a payload nobody could see.

    So each step records the exact keyword arguments of the API call and the
    exact response, which together are enough to replay it: the system
    prompt, every tool declaration including the device enum, the whole
    message array as it grew, and each brokered call with the result that
    went back.

    **Written after every step, not at the end.** The two runs that most
    needed reading today were a kill and a hang, and a dump that is only
    flushed on a clean exit is empty for exactly those.

    Off unless `--dump <dir>` is passed, because it is a debugging
    instrument: it holds whole conversations in the clear, and a device that
    keeps every word said near it by default is a different product.
    """

    def __init__(self, directory):
        self.path, self.doc = None, None
        if not directory:
            return
        try:
            os.makedirs(directory, exist_ok=True)
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime(
                "%Y%m%dT%H%M%SZ")
            self.path = os.path.join(
                directory, "%s-%s.json" % (stamp, uuid.uuid4().hex[:8]))
            self.doc = {"v": V, "model": MODEL, "started": stamp, "steps": []}
            # KEEP - 1: this run's file does not exist yet, and a cap that
            # leaves `keep` behind *plus* the new one is a cap that is wrong
            # by one every time anybody reads it.
            prune(directory, KEEP - 1)
        except OSError as e:                                  # noqa: BLE001
            # A dump that cannot be written must not take the answer with it.
            emit({"type": "thought", "text": "no dump: %s" % e})
            self.path = None

    def opening(self, run, kwargs):
        if self.doc is None:
            return
        # The prompt as cogiti handed it over, beside the content built from
        # it: when a reply makes no sense, the question is which of those two
        # was already wrong.
        self.doc["prompt"] = run.get("prompt")
        self.doc["granted"] = run.get("tools")
        self.doc["system"] = kwargs.get("system")
        self.doc["tools"] = jsonable(kwargs.get("tools"))
        self.write()

    def step(self, kwargs, response):
        if self.doc is None:
            return None
        step = {"request": jsonable(kwargs), "response": jsonable(response),
                "tool_calls": []}
        self.doc["steps"].append(step)
        self.write()
        return step

    def called(self, step, call, answer):
        if self.doc is None or step is None:
            return
        step["tool_calls"].append({"id": call.id, "name": call.name,
                                   "args": jsonable(call.input),
                                   "result": jsonable(answer)})
        self.write()

    def ended(self, outcome):
        if self.doc is None:
            return
        self.doc["outcome"] = jsonable(outcome)
        self.write()

    def write(self):
        if not self.path:
            return
        try:
            tmp = self.path + ".part"
            with open(tmp, "w") as f:
                json.dump(self.doc, f, indent=1, default=str)
            os.replace(tmp, self.path)
        except OSError:
            self.path = None


def jsonable(obj):
    """Whatever it is, as something json.dump will take.

    The SDK hands back pydantic models and the message array ends up holding
    them, so a dump that assumed dicts would fail on the first tool call —
    which is the step worth reading.
    """
    for attr in ("model_dump", "dict"):
        fn = getattr(obj, attr, None)
        if callable(fn):
            try:
                return jsonable(fn())
            except Exception:                                 # noqa: BLE001
                break
    if isinstance(obj, dict):
        return {k: jsonable(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [jsonable(v) for v in obj]
    if isinstance(obj, (str, int, float, bool)) or obj is None:
        return obj
    return str(obj)


# --------------------------------------------------------------------- io --

def emit(obj):
    obj.setdefault("v", V)
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


class Inbox:
    """cogiti's answers, read on a thread and keyed by id.

    Keyed rather than ordered because several tool calls may be outstanding
    and the answers come back in whatever order the work finished.
    """

    def __init__(self):
        self.run = None
        self.answers = {}
        self.cancelled = False
        self._cv = threading.Condition()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            with self._cv:
                if msg.get("type") == "run":
                    self.run = msg
                elif msg.get("type") == "cancel":
                    self.cancelled = True
                elif "id" in msg:
                    self.answers[msg["id"]] = msg
                self._cv.notify_all()

    def wait_run(self, timeout=30.0):
        with self._cv:
            if not self._cv.wait_for(lambda: self.run is not None, timeout):
                return None
            return self.run

    def wait_ids(self, ids, timeout=300.0):
        with self._cv:
            self._cv.wait_for(
                lambda: all(i in self.answers for i in ids) or self.cancelled,
                timeout)
        return {i: self.answers.get(i) for i in ids}


# ------------------------------------------------------------------ tools --

def declared_tools(granted):
    """What the model may ask for: whatever cogiti granted, plus `answer`.

    A tool cogiti did not grant is not described to the model at all. There is
    no point offering something the broker will refuse, and an unadvertised
    tool is one it will not spend a turn discovering it cannot use.
    """
    tools = [ANSWER_TOOL]
    for t in granted:
        # A grant that brings its own schema is declared as it stands. This is
        # how cogiti adds a tool without this file learning its name: it was
        # previously a chain of `if name == ...`, which meant every new tool
        # was a change in two repositories and a version bump between them.
        if t.get("input_schema"):
            tools.append({
                "name": t["name"],
                "description": t.get("description", ""),
                "strict": True,
                "input_schema": t["input_schema"],
            })
            continue
        if t["name"] == "http":
            tools.append({
                "name": "http",
                "description": "Fetch a URL. Only these hosts are reachable: "
                               + (", ".join(t.get("hosts", [])) or "none")
                               + ". Redirects are not followed; if you get a "
                               "3xx, ask for the new URL explicitly.",
                "strict": True,
                "input_schema": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["url"],
                    "properties": {"url": {"type": "string"}},
                },
            })
    return tools


def result_from(answer_input, did_extra):
    out = {"type": "result", "say": answer_input.get("say", "")}
    if answer_input.get("show"):
        out["show"] = answer_input["show"]
    did = list(answer_input.get("did") or []) + did_extra
    if did:
        out["did"] = did
    return out


def transcript(t):
    """One earlier exchange, in a shape that says who did what.

    Five kinds reach a person and all five are rendered, because the gap
    between what they witnessed and what this reads is exactly where a reply
    stops making sense. A question the device put and the answer to it are
    two of them: without those, "am i sure what?" arrives with nothing to be
    unsure about, which is a real sentence a real person said to it.
    """
    if t.get("asked"):
        return "  you asked:  %s" % t["asked"]
    if t.get("unprompted"):
        return "  you said, unprompted: %s" % t.get("answered", "")
    said = t.get("said", "")
    if t.get("answering"):
        return "  they answered: %s" % said
    if t.get("interrupted"):
        return "  they said: %s   (cut short — you never replied)" % said
    line = "  they said: %s" % said
    if t.get("answered"):
        line += "\n  you said:  %s" % t["answered"]
    return line


# ------------------------------------------------------------------- main --

def run_once(client, run, inbox, dump=None):
    dump = dump or Dump(None)
    granted = run.get("tools") or []
    tools = declared_tools(granted)
    prompt = run.get("prompt") or {}

    content = prompt.get("text", "")
    context = prompt.get("context") or {}
    if context.get("recent"):
        content = "\n".join(["Earlier in this conversation:"]
                            + [transcript(t) for t in context["recent"]]
                            ) + "\n\nNow they say: " + content

    messages = [{"role": "user", "content": content}]
    did = []

    def done(result):
        dump.ended(result)
        return result

    while True:
        if inbox.cancelled:
            return done({"type": "failed", "kind": "cancelled",
                         "message": "cancelled"})

        kwargs = {}
        if THINKING:
            # `adaptive`, not a token budget: budget_tokens is rejected
            # outright by this model family.
            kwargs["thinking"] = {"type": "adaptive"}

        # Built once and both sent and recorded, so the dump is the call
        # rather than a description of it — a replay is create(**request).
        request = dict(model=MODEL, max_tokens=MAX_TOKENS, system=SYSTEM,
                       tools=tools, messages=messages, **kwargs)
        if not dump.doc or not dump.doc.get("system"):
            dump.opening(run, request)

        response = client.messages.create(**request)
        step = dump.step(request, response)

        # A refusal is an HTTP 200 with a stop_reason, not an exception.
        if response.stop_reason == "refusal":
            detail = getattr(response, "stop_details", None)
            return done({"type": "failed", "kind": "refusal",
                         "message": getattr(detail, "explanation", "declined")})

        for block in response.content:
            if block.type == "thinking" and getattr(block, "thinking", ""):
                emit({"type": "thought", "text": block.thinking[:400]})
            elif block.type == "text" and block.text.strip():
                # Not the answer — the answer only arrives through the tool.
                # Surfaced as a thought so it is visible in the trace rather
                # than silently dropped.
                emit({"type": "thought", "text": block.text.strip()[:400]})

        calls = [b for b in response.content if b.type == "tool_use"]
        if not calls:
            return done({"type": "failed", "kind": "no_answer",
                         "message": "the model stopped without calling answer"})

        for call in calls:
            if call.name == "answer":
                dump.called(step, call, {"ok": True, "value": "(the answer)"})
                return done(result_from(call.input, did))

        # Everything else is brokered. All of them are asked for at once, and
        # all of the results go back in one user message: splitting them
        # teaches the model to stop asking in parallel.
        ids = []
        for call in calls:
            emit({"type": "tool", "id": call.id, "name": call.name,
                  "args": call.input})
            ids.append(call.id)
            did.append("%s %s" % (call.name, list(call.input.values())[0]
                                  if call.input else ""))

        answers = inbox.wait_ids(ids)
        for call in calls:
            dump.called(step, call, answers.get(call.id))
        messages.append({"role": "assistant", "content": response.content})

        results = []
        for call in calls:
            a = answers.get(call.id) or {}
            if a.get("ok"):
                body = json.dumps(a.get("value"))[:20000]
                results.append({"type": "tool_result", "tool_use_id": call.id,
                                "content": body})
            else:
                err = (a.get("error") or {}).get("message", "no answer")
                # is_error, not a dropped result: the model has to be told the
                # call failed, or it waits for something that never comes.
                results.append({"type": "tool_result", "tool_use_id": call.id,
                                "content": err, "is_error": True})
        messages.append({"role": "user", "content": results})


def flag(argv, name):
    """--dump DIR or --dump=DIR, and nothing if it is absent."""
    for i, a in enumerate(argv):
        if a == name and i + 1 < len(argv):
            return argv[i + 1]
        if a.startswith(name + "="):
            return a[len(name) + 1:]
    return None


def main(argv):
    if "--capabilities" in argv:
        emit({"type": "capabilities", "tools": True, "questions": False,
              "streaming": False, "model": MODEL,
              "thinking": THINKING})
        return 0

    if not os.environ.get("ANTHROPIC_API_KEY"):
        emit({"type": "failed", "kind": "config",
              "message": "ANTHROPIC_API_KEY is not in this adapter's "
                         "environment; cogiti grants it from its secret store"})
        return 1

    dump = Dump(flag(argv, "--dump"))

    inbox = Inbox()
    run = inbox.wait_run()
    if run is None:
        emit({"type": "failed", "kind": "protocol", "message": "no run message"})
        return 1

    client = anthropic.Anthropic()
    try:
        emit(run_once(client, run, inbox, dump))
    except anthropic.APIStatusError as e:
        failed = {"type": "failed", "kind": "upstream",
                  "message": "%s %s" % (e.status_code, e.message)}
        dump.ended(failed)
        emit(failed)
        return 1
    except anthropic.APIConnectionError as e:
        failed = {"type": "failed", "kind": "unreachable", "message": str(e)}
        dump.ended(failed)
        emit(failed)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
