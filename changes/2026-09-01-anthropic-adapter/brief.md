# 2026-09-01-anthropic-adapter — a real agent adapter, and what it found

Status: landed
Approved by: alek, 2026-09-01 ("go ahead")

## The ask

Slice 3. Everything cogiti does behind the agent port has so far been proven
against a fake that does what the scenario file tells it. That fake was written
by the same hand as the port, which makes agreement between them worth very
little. Put a real model behind it and find out whether the port's central
claim survives contact: **that a result can be structured rather than prose** —
`say`, `show`, `did` — because `ports.md` says the presentation layer, not the
model, decides what a result looks like.

## The seam

    contract: agent protocol (docs/agent-protocol.md)
    owner:    cogiti
    consumers: this adapter, tests/fakes/agent.py
    additive: yes — no protocol change was needed, which is the result

The protocol needed no change to carry a real model. That is the finding worth
recording: the shape drawn against a fake turned out to fit.

## Where it lives, and why not in cogiti

`adapters/anthropic/`, here. `ports.md` says an adapter is configuration, and
cogiti names no implementation of any port — a vendor client and a model name
are a deployment's choice, and InteliBoy is a deployment of cogiti.

It follows that **cogiti stays stdlib-only and an adapter brings its own
dependencies.** The adapter has its own venv; `.venv/` is gitignored. PEP 668
blocking a system-wide `pip install` was the accident that made this concrete,
but the rule would hold without it.

## Three decisions the protocol made, not taste

**No SDK tool runner.** It executes tool functions in-process, which is exactly
what the brokering decision forbids — cogiti runs the tools so that every
request passes the egress broker. So the adapter runs a manual agentic loop:
`tool_use` becomes a `tool` event, cogiti brokers it, the answer returns as
`tool_result` and goes back into `messages`.

**The result is structured because a tool makes it so.** The model finishes by
calling an `answer` tool whose schema is `strict` with
`additionalProperties: false`. Structured outputs on the final turn was the
alternative; the tool composes with the agentic loop instead of being a
separate mode for the last request.

**Adaptive thinking, on by default.** `budget_tokens` is rejected outright by
this model family. It costs latency, which an appliance that answers out loud
can least afford — but the protocol has a `thought` event and avatari has a
face to put it on. `COGITI_THINKING=off` buys the seconds back.

## What it found

Both of these were invisible to 27 passing tests and to the fake, and both were
found by a real model complaining.

**1. A tool that could not run was reported to the agent as a success.**
`_run_tool_job` read `json.loads(out or "{}")`, so a tool that crashed — or was
never found — became `ok: true` with an empty value. The model was told the
page was blank rather than that nothing had been fetched, and answered
confidently from memory about a page it had never seen. Empty stdout is now an
error carrying the tool's stderr. A non-zero exit *with* json is still a
result: the http tool exits 1 for a 404, and that json is the answer.

**2. `cogiti/tools/http.py` shadowed the standard library.** Spawning a tool by
absolute path puts its directory first on `sys.path`, so `import http.client`
inside `urllib` found our module and urllib failed to import itself. Renamed to
`http_fetch.py`; the tool is still called `http` on the wire, where the name is
free.

The second bug was created while fixing the first — tools were spawned as
`-m cogiti.tools.http`, which needed a `PYTHONPATH` that `secrets.env_for`
deliberately does not provide. Spawning by path is the fix; the file name was
the landmine underneath it.

## Per repo

### cogiti     [order 1]
files:  src/cogiti/adapters/agent.py, src/cogiti/secrets.py,
        src/cogiti/tools/http.py -> http_fetch.py,
        tests/fakes/agent.py, tests/test_slice2.py,
        tests/scenarios/report-one-fetch.json
change: tools spawned by absolute path; a tool that writes no result is an
        error, not an empty success; no PYTHONPATH in a child's environment;
        the fake gained a `report` step so a test can assert on *what* came
        back rather than only that something did.
proves it: `make test` — 31, was 27.

### inteliboy  [order 2]
files:  adapters/anthropic/{adapter.py,test_adapter.py}, .gitignore
change: the adapter, and 17 offline tests plus one opt-in live one.
proves it: `.venv/bin/python test_adapter.py` — 17 offline, free.
           `LIVE=1 …` adds one real call.

## Proven on the live API

- a structured result, `say` + `show`, from a real model — 18.5s cold
- one brokered fetch, page actually read, correct title — 7.1s
- a host off the allowlist: refused, the model told, and it said plainly that
  it could not confirm what it then offered from memory. The denial path
  behaved better than the success path did before the fix.

## Not in this change

- **Streaming.** The adapter declares `streaming: false` and emits `thought`
  events per turn, not per token. A face that moves while the model thinks
  wants the token stream; that is avatari's slice, not this one.
- **Grants narrower than the deployment's allowlist.** `escalate.grants()`
  still hands every job the whole of `egress_hosts`. It says so itself.
- **A budget that is enforced.** `budget.wall_ms` is passed and ignored.
- **cogiti in the image.** It still ships only avatari, assets and a kernel,
  so none of the above runs on the box yet.

## Rollback

`git revert` in each repo; no lock entry changed, no contract version moved.
