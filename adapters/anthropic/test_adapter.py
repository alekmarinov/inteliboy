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


class TestTools(unittest.TestCase):

    def test_ungranted_tools_are_not_described(self):
        """Offering a tool the broker will refuse only wastes a turn."""
        names = [t["name"] for t in adapter.declared_tools([])]
        self.assertEqual(names, ["answer"])

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
