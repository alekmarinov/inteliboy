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

import json
import os
import sys
import threading

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
    "long, round it the way a person would say it."
)


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


# ------------------------------------------------------------------- main --

def run_once(client, run, inbox):
    granted = run.get("tools") or []
    tools = declared_tools(granted)
    prompt = run.get("prompt") or {}

    content = prompt.get("text", "")
    context = prompt.get("context") or {}
    if context.get("recent"):
        lines = ["Earlier in this conversation:"]
        for t in context["recent"]:
            lines.append("  they said: %s" % t.get("said", ""))
            if t.get("answered"):
                lines.append("  you said:  %s" % t["answered"])
        content = "\n".join(lines) + "\n\nNow they say: " + content

    messages = [{"role": "user", "content": content}]
    did = []

    while True:
        if inbox.cancelled:
            return {"type": "failed", "kind": "cancelled", "message": "cancelled"}

        kwargs = {}
        if THINKING:
            # `adaptive`, not a token budget: budget_tokens is rejected
            # outright by this model family.
            kwargs["thinking"] = {"type": "adaptive"}

        response = client.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            system=SYSTEM,
            tools=tools,
            messages=messages,
            **kwargs,
        )

        # A refusal is an HTTP 200 with a stop_reason, not an exception.
        if response.stop_reason == "refusal":
            detail = getattr(response, "stop_details", None)
            return {"type": "failed", "kind": "refusal",
                    "message": getattr(detail, "explanation", "declined")}

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
            return {"type": "failed", "kind": "no_answer",
                    "message": "the model stopped without calling answer"}

        for call in calls:
            if call.name == "answer":
                return result_from(call.input, did)

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

    inbox = Inbox()
    run = inbox.wait_run()
    if run is None:
        emit({"type": "failed", "kind": "protocol", "message": "no run message"})
        return 1

    client = anthropic.Anthropic()
    try:
        emit(run_once(client, run, inbox))
    except anthropic.APIStatusError as e:
        emit({"type": "failed", "kind": "upstream",
              "message": "%s %s" % (e.status_code, e.message)})
        return 1
    except anthropic.APIConnectionError as e:
        emit({"type": "failed", "kind": "unreachable", "message": str(e)})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
