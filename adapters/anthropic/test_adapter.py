#!/usr/bin/env python3
"""Tests for the Anthropic adapter.

Everything here runs offline against a stub client, and that is the point:
a suite that costs money per run is a suite people stop running. The one test
that talks to the API is opt-in and skipped by default.

    .venv/bin/python test_adapter.py            # offline, free
    LIVE=1 .venv/bin/python test_adapter.py     # + one real call

What is worth testing is not "does the SDK work" but the three translations
this file owns: run -> messages, tool_use -> tool event, and the answer tool ->
a protocol result. Each of those is a place a mistake would be silent.
"""

import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adapter


# --------------------------------------------------------------- stubs --

class Block:
    def __init__(self, type, **kw):
        self.type = type
        self.__dict__.update(kw)


class Response:
    def __init__(self, content, stop_reason="end_turn"):
        self.content, self.stop_reason = content, stop_reason


class StubClient:
    """Hands back scripted responses and records what it was asked."""

    def __init__(self, *responses):
        self._queue = list(responses)
        self.calls = []
        self.messages = self

    def create(self, **kw):
        self.calls.append(kw)
        return self._queue.pop(0)


class StubInbox:
    def __init__(self, answers=None):
        self.answers = answers or {}
        self.cancelled = False

    def wait_ids(self, ids, timeout=None):
        return {i: self.answers.get(i) for i in ids}


def answer_block(**kw):
    return Block("tool_use", id="t0", name="answer", input=kw)


def tool_block(name, args, id):
    return Block("tool_use", id=id, name=name, input=args)


# ------------------------------------------------------------ the tests --

class TestPrompt(unittest.TestCase):

    def test_plain_utterance_is_the_message(self):
        client = StubClient(Response([answer_block(say="hello")]))
        adapter.run_once(client, {"prompt": {"text": "hello there"}}, StubInbox())
        self.assertEqual(client.calls[0]["messages"],
                         [{"role": "user", "content": "hello there"}])

    def test_history_is_rendered_as_dialogue(self):
        """session.context() gives {"recent": [{said, answered}]}. It has to
        arrive as something a model reads as a conversation, not as JSON."""
        client = StubClient(Response([answer_block(say="ok")]))
        run = {"prompt": {"text": "and the second one?", "context": {
            "recent": [{"said": "name a colour", "answered": "blue"}]}}}
        adapter.run_once(client, run, StubInbox())
        content = client.calls[0]["messages"][0]["content"]
        self.assertIn("name a colour", content)
        self.assertIn("blue", content)
        self.assertTrue(content.endswith("Now they say: and the second one?"))

    def test_thinking_is_adaptive_not_a_budget(self):
        """budget_tokens is rejected outright by this model family."""
        client = StubClient(Response([answer_block(say="ok")]))
        adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox())
        self.assertEqual(client.calls[0]["thinking"], {"type": "adaptive"})
        self.assertNotIn("budget_tokens", json.dumps(client.calls[0]["thinking"]))


class TestDump(unittest.TestCase):
    """Everything sent and everything returned, on disk.

    Three faults in one day were all the same shape: a strange sentence out
    loud, and the cause in a payload nobody could see. The trace said which
    tools were called; it never said what the model was given.
    """

    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def only_file(self):
        names = [n for n in os.listdir(self.dir) if n.endswith(".json")]
        self.assertEqual(len(names), 1, names)
        with open(os.path.join(self.dir, names[0])) as f:
            return json.load(f)

    def test_nothing_is_written_unless_asked(self):
        """It holds whole conversations in the clear. A device that keeps
        every word said near it by default is a different product."""
        client = StubClient(Response([answer_block(say="ok")]))
        adapter.run_once(client, {"prompt": {"text": "hi"}}, StubInbox(),
                         adapter.Dump(None))
        self.assertEqual(os.listdir(self.dir), [])

    def test_it_records_the_call_it_actually_made(self):
        """The request verbatim, so a replay is create(**request) rather than
        a reconstruction from prose."""
        client = StubClient(Response([answer_block(say="ok")]))
        run = {"prompt": {"text": "what time is it"},
               "tools": [{"name": "http", "hosts": ["example.com"]}]}
        adapter.run_once(client, run, StubInbox(), adapter.Dump(self.dir))
        doc = self.only_file()
        self.assertEqual(doc["prompt"]["text"], "what time is it")
        self.assertEqual(doc["granted"], run["tools"])
        self.assertIn("voice appliance", doc["system"])
        # The declarations as sent, not the grant that produced them: the
        # host list reaching the model is the thing worth reading back.
        self.assertEqual([t["name"] for t in doc["tools"]],
                         ["answer", "http"])
        self.assertIn("example.com", json.dumps(doc["tools"]))
        step = doc["steps"][0]
        self.assertEqual(step["request"]["model"], adapter.MODEL)
        self.assertEqual(step["request"]["messages"][0]["content"],
                         "what time is it")
        self.assertEqual(doc["outcome"]["say"], "ok")

    def test_a_brokered_call_records_its_result(self):
        """The half that was hardest to see from outside: what the tool was
        asked and what it handed back."""
        client = StubClient(
            Response([tool_block("device", {"command": "get_disk"}, "t1")]),
            Response([answer_block(say="four gigabytes free")]))
        inbox = StubInbox({"t1": {"ok": True, "value": {"free": "4G"}}})
        adapter.run_once(client, {"prompt": {"text": "much room left?"}},
                         inbox, adapter.Dump(self.dir))
        calls = self.only_file()["steps"][0]["tool_calls"]
        self.assertEqual(calls[0]["name"], "device")
        self.assertEqual(calls[0]["args"], {"command": "get_disk"})
        self.assertEqual(calls[0]["result"], {"ok": True,
                                              "value": {"free": "4G"}})

    def test_it_is_readable_before_the_run_ends(self):
        """The two runs that most needed reading today were a kill and a
        hang. A dump flushed only on a clean exit is empty for exactly
        those."""
        seen = {}
        class Watching(StubInbox):
            def wait_ids(self, ids):
                names = [n for n in os.listdir(self.dir_) if n.endswith(".json")]
                with open(os.path.join(self.dir_, names[0])) as f:
                    seen["mid"] = json.load(f)
                return super().wait_ids(ids)
        inbox = Watching({"t1": {"ok": True, "value": 1}})
        inbox.dir_ = self.dir
        client = StubClient(
            Response([tool_block("device", {"command": "get_time"}, "t1")]),
            Response([answer_block(say="ok")]))
        adapter.run_once(client, {"prompt": {"text": "x"}}, inbox,
                         adapter.Dump(self.dir))
        self.assertEqual(len(seen["mid"]["steps"]), 1,
                         "the first exchange was not on disk while the "
                         "second was still being waited on")

    def test_it_keeps_only_the_newest(self):
        """One file per escalation on a device with four gigabytes free.
        The failure mode of filling that is the appliance stopping, which is
        worse than the debugging being harder."""
        for i in range(5):
            open(os.path.join(self.dir, "2026010%dT000000Z-x.json" % i),
                 "w").close()
        client = StubClient(Response([answer_block(say="ok")]))
        adapter.KEEP = 3
        try:
            adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox(),
                             adapter.Dump(self.dir))
        finally:
            adapter.KEEP = 200
        left = sorted(os.listdir(self.dir))
        self.assertEqual(len(left), 3, left)
        self.assertNotIn("20260100T000000Z-x.json", left, "oldest survived")

    def test_an_unwritable_directory_does_not_lose_the_answer(self):
        client = StubClient(Response([answer_block(say="ok")]))
        out = adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox(),
                               adapter.Dump("/proc/nope/nowhere"))
        self.assertEqual(out["say"], "ok")


class TestTools(unittest.TestCase):

    def test_ungranted_tools_are_not_described(self):
        """Offering a tool the broker will refuse only wastes a turn."""
        names = [t["name"] for t in adapter.declared_tools([])]
        self.assertEqual(names, ["answer"])

    def test_http_says_what_it_actually_does(self):
        """Each of these was a thing the model had no way to know and had to
        infer: that it cannot POST, that a 404 is a readable result rather
        than a failure, and that the body is capped."""
        d = [t for t in adapter.declared_tools(
            [{"name": "http", "hosts": ["api.coinbase.com"]}])
            if t["name"] == "http"][0]["description"]
        for fact in ("GET only", "api.coinbase.com", "404", "1 MB",
                     "20 seconds", "redirected_to", "error_kind"):
            self.assertIn(fact, d)

    def test_granted_http_carries_its_host_list(self):
        tools = adapter.declared_tools([{"name": "http", "hosts": ["example.com"]}])
        http = [t for t in tools if t["name"] == "http"][0]
        self.assertIn("example.com", http["description"])
        self.assertTrue(http["strict"])
        self.assertFalse(http["input_schema"]["additionalProperties"])

    def test_answer_schema_is_strict(self):
        """The whole structured-result claim rests on this being enforced by
        the API rather than by the prompt."""
        self.assertTrue(adapter.ANSWER_TOOL["strict"])
        self.assertFalse(adapter.ANSWER_TOOL["input_schema"]["additionalProperties"])
        self.assertEqual(adapter.ANSWER_TOOL["input_schema"]["required"], ["say"])


class TestBrokering(unittest.TestCase):

    def setUp(self):
        self.out = io.StringIO()
        self._stdout, sys.stdout = sys.stdout, self.out

    def tearDown(self):
        sys.stdout = self._stdout

    def events(self):
        return [json.loads(l) for l in self.out.getvalue().splitlines() if l]

    def test_a_tool_call_becomes_a_tool_event_and_its_result_goes_back(self):
        call = Block("tool_use", id="a1", name="http", input={"url": "http://x/"})
        client = StubClient(Response([call], stop_reason="tool_use"),
                            Response([answer_block(say="done")]))
        inbox = StubInbox({"a1": {"id": "a1", "ok": True, "value": {"body": "42"}}})

        result = adapter.run_once(client, {"prompt": {"text": "fetch"}}, inbox)

        asked = [e for e in self.events() if e["type"] == "tool"]
        self.assertEqual(len(asked), 1)
        self.assertEqual(asked[0]["name"], "http")
        self.assertEqual(asked[0]["id"], "a1")          # cogiti correlates by it

        back = client.calls[1]["messages"][-1]["content"][0]
        self.assertEqual(back["tool_use_id"], "a1")
        self.assertIn("42", back["content"])
        self.assertNotIn("is_error", back)
        self.assertEqual(result["say"], "done")

    def test_parallel_calls_go_out_together_and_come_back_in_one_message(self):
        """Splitting the results across messages teaches the model to stop
        asking in parallel, which is the reason parallelism was allowed."""
        calls = [Block("tool_use", id="a1", name="http", input={"url": "http://x/"}),
                 Block("tool_use", id="a2", name="http", input={"url": "http://y/"})]
        client = StubClient(Response(calls, stop_reason="tool_use"),
                            Response([answer_block(say="both")]))
        inbox = StubInbox({"a1": {"id": "a1", "ok": True, "value": 1},
                           "a2": {"id": "a2", "ok": True, "value": 2}})

        adapter.run_once(client, {"prompt": {"text": "fetch two"}}, inbox)

        self.assertEqual(len([e for e in self.events() if e["type"] == "tool"]), 2)
        results = client.calls[1]["messages"][-1]["content"]
        self.assertEqual([r["tool_use_id"] for r in results], ["a1", "a2"])

    def test_a_refused_tool_is_reported_as_an_error_not_dropped(self):
        """A dropped result leaves the model waiting for something that is
        never coming; is_error lets it try something else."""
        call = Block("tool_use", id="a1", name="http", input={"url": "http://evil/"})
        client = StubClient(Response([call], stop_reason="tool_use"),
                            Response([answer_block(say="could not")]))
        inbox = StubInbox({"a1": {"id": "a1", "ok": False, "error": {
            "kind": "egress", "message": "host evil not allowed"}}})

        adapter.run_once(client, {"prompt": {"text": "fetch"}}, inbox)

        back = client.calls[1]["messages"][-1]["content"][0]
        self.assertTrue(back["is_error"])
        self.assertIn("not allowed", back["content"])

    def test_a_tool_cogiti_never_answered_still_returns_an_error(self):
        call = Block("tool_use", id="a1", name="http", input={"url": "http://x/"})
        client = StubClient(Response([call], stop_reason="tool_use"),
                            Response([answer_block(say="gave up")]))
        adapter.run_once(client, {"prompt": {"text": "fetch"}}, StubInbox({}))
        back = client.calls[1]["messages"][-1]["content"][0]
        self.assertTrue(back["is_error"])

    def test_brokered_calls_are_recorded_in_did(self):
        call = Block("tool_use", id="a1", name="http", input={"url": "http://x/"})
        client = StubClient(Response([call], stop_reason="tool_use"),
                            Response([answer_block(say="done")]))
        inbox = StubInbox({"a1": {"id": "a1", "ok": True, "value": {}}})
        result = adapter.run_once(client, {"prompt": {"text": "f"}}, inbox)
        self.assertTrue(any("http://x/" in d for d in result["did"]))


class TestResult(unittest.TestCase):

    def setUp(self):
        self._stdout, sys.stdout = sys.stdout, io.StringIO()

    def tearDown(self):
        sys.stdout = self._stdout

    def test_say_only(self):
        client = StubClient(Response([answer_block(say="just this")]))
        r = adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox())
        self.assertEqual(r, {"type": "result", "say": "just this"})

    def test_show_and_did_are_carried_when_present(self):
        client = StubClient(Response([answer_block(
            say="s", show="S", did=["looked it up"])]))
        r = adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox())
        self.assertEqual(r["show"], "S")
        self.assertEqual(r["did"], ["looked it up"])

    def test_prose_without_an_answer_call_is_a_failure_not_a_result(self):
        """The claim being defended: a model that writes the answer as text
        has not answered. Accepting the prose here is how a deployment ends up
        parsing markdown out of a voice line."""
        client = StubClient(Response([Block("text", text="Paris, obviously.")]))
        r = adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox())
        self.assertEqual(r["type"], "failed")
        self.assertEqual(r["kind"], "no_answer")

    def test_stray_prose_is_surfaced_as_a_thought_not_dropped(self):
        call = Block("tool_use", id="a1", name="http", input={"url": "http://x/"})
        client = StubClient(
            Response([Block("text", text="Let me look."), call], stop_reason="tool_use"),
            Response([answer_block(say="done")]))
        inbox = StubInbox({"a1": {"id": "a1", "ok": True, "value": {}}})
        adapter.run_once(client, {"prompt": {"text": "x"}}, inbox)
        thoughts = [json.loads(l) for l in sys.stdout.getvalue().splitlines()
                    if json.loads(l)["type"] == "thought"]
        self.assertEqual(thoughts[0]["text"], "Let me look.")

    def test_a_refusal_is_a_failed_event_not_an_exception(self):
        """It arrives as an HTTP 200 with a stop_reason, so nothing raises."""
        r = Response([], stop_reason="refusal")
        r.stop_details = Block("refusal", explanation="declined to help")
        out = adapter.run_once(StubClient(r), {"prompt": {"text": "x"}}, StubInbox())
        self.assertEqual(out["type"], "failed")
        self.assertEqual(out["kind"], "refusal")
        self.assertIn("declined", out["message"])

    def test_cancellation_stops_before_spending_a_request(self):
        client = StubClient()          # empty: a call would raise IndexError
        inbox = StubInbox()
        inbox.cancelled = True
        r = adapter.run_once(client, {"prompt": {"text": "x"}}, inbox)
        self.assertEqual(r["kind"], "cancelled")
        self.assertEqual(client.calls, [])


class TestLive(unittest.TestCase):
    """One real call. Opt in with LIVE=1; it spends money."""

    @unittest.skipUnless(os.environ.get("LIVE"), "set LIVE=1 to spend money")
    def test_a_real_model_returns_structure_not_prose(self):
        import anthropic
        key = open(os.path.expanduser(
            "~/.local/state/cogiti/secrets/anthropic.api_key")).read().strip()
        client = anthropic.Anthropic(api_key=key)
        r = adapter.run_once(
            client, {"prompt": {"text": "how many legs does a spider have?"}},
            StubInbox())
        self.assertEqual(r["type"], "result", r)
        self.assertIn("eight", r["say"].lower())
        self.assertNotIn("**", r["say"])          # spoken, not rendered


if __name__ == "__main__":
    unittest.main(verbosity=2)
