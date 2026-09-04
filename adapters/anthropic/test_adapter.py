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


class StreamingStubClient(StubClient):
    """Hands back thinking deltas, then a final message — the shape the SDK
    streams, reduced to what this adapter reads."""

    def __init__(self, pieces, *responses):
        super().__init__(*responses)
        self.pieces = pieces

    def stream(self, **kw):
        self.calls.append(kw)
        final = self._queue.pop(0)
        pieces = self.pieces
        outer = self

        class Ctx:
            def __enter__(self):
                return self
            def __exit__(self, *a):
                return False
            def __iter__(self):
                for piece in pieces:
                    yield Block("content_block_delta",
                                delta=Block("thinking_delta", thinking=piece))
            def get_final_message(self):
                return final
        return Ctx()


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

    def test_history_arrives_as_turns_not_as_a_briefing(self):
        """It used to be one user message with the history rendered into
        prose inside it, so the model had never *said* anything: its own
        words came back laundered through a formatter, it could not see its
        own earlier tool calls, and none of the prefix was cacheable."""
        client = StubClient(Response([answer_block(say="ok")]))
        run = {"prompt": {"text": "and the second one?", "context": {
            "recent": [{"said": "name a colour", "answered": "blue"}]}}}
        adapter.run_once(client, run, StubInbox())
        self.assertEqual(client.calls[0]["messages"], [
            {"role": "user", "content": "name a colour"},
            {"role": "assistant", "content": "blue"},
            {"role": "user", "content": "and the second one?"},
        ])

    def test_a_question_and_its_answer_take_the_right_roles(self):
        """The device asked "Are you sure?" and was asked back, out loud,
        "am I sure what?". The question is something *it* said and the reply
        is something *they* said; no rendering into one user message says
        so."""
        client = StubClient(Response([answer_block(say="ok")]))
        run = {"prompt": {"text": "am i sure what?", "context": {"recent": [
            {"said": "pin the clock on the screen"},
            {"asked": "Keep it on the screen from now on?"},
        ]}}}
        adapter.run_once(client, run, StubInbox())
        self.assertEqual(client.calls[0]["messages"], [
            {"role": "user", "content": "pin the clock on the screen"},
            {"role": "assistant",
             "content": "Keep it on the screen from now on?"},
            {"role": "user", "content": "am i sure what?"},
        ])

    def test_consecutive_turns_of_one_role_are_joined(self):
        """Two interrupted utterances in a row are real, and the API wants
        alternating roles. Joining keeps them; dropping would lose the half
        of the conversation that was cut off."""
        client = StubClient(Response([answer_block(say="ok")]))
        run = {"prompt": {"text": "well?", "context": {"recent": [
            {"said": "i want the bitcoin", "interrupted": True},
            {"said": "the price i mean", "interrupted": True},
        ]}}}
        adapter.run_once(client, run, StubInbox())
        msgs = client.calls[0]["messages"]
        # All three are things they said with nothing said back, so they are
        # one message. Nothing is lost and the roles stay alternating.
        self.assertEqual([m["role"] for m in msgs], ["user"])
        for part in ("i want the bitcoin", "the price i mean", "cut short",
                     "well?"):
            self.assertIn(part, msgs[0]["content"])

    def test_it_never_opens_with_the_assistant(self):
        """History can begin with something the device said — an unprompted
        delivery, or a question — and the API wants a user message first."""
        client = StubClient(Response([answer_block(say="ok")]))
        run = {"prompt": {"text": "what?", "context": {"recent": [
            {"answered": "About the timer — it has gone off.",
             "unprompted": True}]}}}
        adapter.run_once(client, run, StubInbox())
        self.assertEqual(client.calls[0]["messages"],
                         [{"role": "user", "content": "what?"}])

    def test_the_situation_is_a_system_block_not_a_user_message(self):
        """What somebody said and what happened to be true when they said it
        are different things, and the model should not have to separate
        them. It is also what lets the first block carry the cache."""
        client = StubClient(Response([answer_block(say="ok")]))
        run = {"prompt": {"text": "is it late?", "context": {"situation": {
            "time": "23:40", "date": "Thursday 03 September 2026",
            "device": "inteliboy", "speaker": "unknown",
            "pinned": ["the bitcoin price"], "since_last_s": 7200}}}}
        adapter.run_once(client, run, StubInbox())
        system = client.calls[0]["system"]
        self.assertEqual(system[0]["cache_control"], {"type": "ephemeral"})
        self.assertNotIn("cache_control", system[1])
        block = system[1]["text"]
        for fact in ("23:40", "inteliboy", "the bitcoin price", "2 hours",
                     "new subject", "do not know who is speaking"):
            self.assertIn(fact, block)
        self.assertEqual(client.calls[0]["messages"],
                         [{"role": "user", "content": "is it late?"}])

    def test_a_named_speaker_is_named(self):
        client = StubClient(Response([answer_block(say="ok")]))
        adapter.run_once(client, {"prompt": {"text": "hi", "context": {
            "situation": {"speaker": "alek"}}}}, StubInbox())
        self.assertIn("talking to alek", client.calls[0]["system"][1]["text"])

    def test_a_paused_search_resumes_instead_of_giving_up(self):
        """The server-side loop hits its own iteration limit mid-search and
        returns `pause_turn`. Without handling it the turn ends with no
        tool_use block, and the loop reports that the model stopped without
        answering — which is what a long search looked like from outside."""
        client = StubClient(
            Response([Block("server_tool_use", id="s1", name="web_search",
                            input={"query": "x"})], stop_reason="pause_turn"),
            Response([answer_block(say="found it")]))
        out = adapter.run_once(client, {"prompt": {"text": "look it up"}},
                               StubInbox())
        self.assertEqual(out["say"], "found it")
        self.assertEqual(len(client.calls), 2, "it did not resume")
        # Resumed with what it had and nothing else: a "continue" message
        # would be answering on the model's behalf.
        self.assertEqual(client.calls[1]["messages"][-1]["role"], "assistant")

    def test_the_model_is_the_deployment_s_to_choose(self):
        """`--model`, because cogiti builds this process's environment rather
        than inheriting one: COGITI_MODEL never arrived from a shell, so the
        model was only ever settable by editing this file."""
        self.assertEqual(adapter.flag(["--model", "claude-sonnet-5"],
                                      "--model"), "claude-sonnet-5")
        self.assertEqual(adapter.flag(["--model=claude-sonnet-5"],
                                      "--model"), "claude-sonnet-5")
        self.assertIsNone(adapter.flag(["--dump", "/tmp/x"], "--model"))

    def test_thinking_is_adaptive_not_a_budget(self):
        """budget_tokens is rejected outright by this model family."""
        client = StubClient(Response([answer_block(say="ok")]))
        adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox())
        self.assertEqual(client.calls[0]["thinking"],
                         {"type": "adaptive", "display": "summarized"})
        self.assertNotIn("budget_tokens", json.dumps(client.calls[0]["thinking"]))

    def test_reasoning_is_asked_for_not_merely_hoped_for(self):
        """`omitted` is the default on this model family and does not mean
        "no thinking" — the blocks arrive with empty text. The face had a
        thought stream, cogiti had the hook, the adapter had the emit, and
        all three worked while forwarding nothing."""
        client = StubClient(Response([answer_block(say="ok")]))
        adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox())
        self.assertEqual(client.calls[0]["thinking"]["display"], "summarized")

    def test_reasoning_is_reported_while_it_happens(self):
        """A thought that arrives with the answer is a footnote, not
        feedback. The device is silent for seconds while it searches, and the
        point of putting reasoning on a screen is that the silence reads as
        work."""
        said = []
        real, adapter.emit = adapter.emit, lambda o: said.append(o)
        try:
            client = StreamingStubClient(
                ["Looking for the price. ", "Two sources disagree, ",
                 "so I will take the newer one."],
                Response([answer_block(say="ok")]))
            adapter.run_once(client, {"prompt": {"text": "x"}}, StubInbox())
        finally:
            adapter.emit = real
        thoughts = [o["text"] for o in said if o["type"] == "thought"]
        self.assertTrue(thoughts, "the reasoning never left the adapter")
        self.assertIn("Looking for the price.", thoughts[0])
        self.assertTrue(len(thoughts) > 1, "it arrived in one lump at the end")


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
        self.assertIn("InteliBoy", json.dumps(doc["system"]))
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

    def test_web_search_is_a_server_tool_with_a_ceiling(self):
        """Anthropic runs it; there is nothing to execute here. The ceiling
        is because this device answers out loud — ten searches is a minute of
        silence."""
        tools = adapter.declared_tools([{"name": "web_search"}])
        search = [t for t in tools if t.get("name") == "web_search"][0]
        self.assertEqual(search["type"], "web_search_20260209")
        self.assertEqual(search["max_uses"], adapter.MAX_SEARCHES)
        self.assertNotIn("input_schema", search)

    def test_fetching_comes_with_searching(self):
        """Five of eight attempts to put a product on screen had no picture,
        and none of them was a failed download: search results do not hand
        over image URLs and the model will not invent one. Opening the page
        it already found is how anybody gets the photograph."""
        tools = adapter.declared_tools([{"name": "web_search"}])
        types = [t.get("type") for t in tools if "type" in t]
        self.assertEqual(types, ["web_search_20260209", "web_fetch_20260209"])
        fetch = [t for t in tools if t.get("name") == "web_fetch"][0]
        self.assertEqual(fetch["max_uses"], adapter.MAX_FETCHES)

    def test_code_execution_is_never_declared_beside_it(self):
        """`_20260209` runs code on their side for dynamic filtering, and a
        second execution environment confuses the model."""
        tools = adapter.declared_tools([{"name": "web_search"},
                                        {"name": "http", "hosts": ["x.com"]}])
        self.assertEqual([t.get("type") for t in tools if "type" in t],
                         ["web_search_20260209", "web_fetch_20260209"])

    def test_an_ungranted_search_is_not_declared(self):
        tools = adapter.declared_tools([{"name": "http", "hosts": []}])
        self.assertNotIn("web_search", [t.get("name") for t in tools])

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
