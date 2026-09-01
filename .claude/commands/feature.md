Run a cross-component change end to end. The request is: $ARGUMENTS

Follow the five phases in `CLAUDE.md`. Do not skip phase 2's stop.

**1. Survey.** Decide which components are plausibly affected. Spawn one
`surveyor` per component, all in a single message so they run in parallel, each
with one specific question about *that* component. Keep their conclusions; do
not read the codebases yourself. If `lfs` looks involved, use the `lfs` agent —
it cannot write, which is the point.

**2. Design, then stop.** Write `changes/<id>/brief.md` from
`changes/TEMPLATE.md`: the seam and its owner, whether it is additive or a
bump, the shared vocabulary, each surveyor's position in its own words
including what it said it would refuse, the per-repo sections in landing order,
and for each the command that proves it.

Then **stop and show me the brief.** Ask any question you have now — this is
the only phase where you can, because subagents cannot. Do not write code until
I have approved it.

**3. Implement.** Run `make status` first and record it. Then:
- small or design-bearing → do it yourself, repo by repo, in landing order;
- large and mechanical → one component agent per repo, in parallel *across*
  repos, never two in one repo.
Owner of the contract lands first, always.

**4. Verify yourself.** `make verify` from this directory. Read the output. An
agent's claim that its tests passed is not evidence; the test run is. Then
`make dirty` — any component dirty that the brief does not name is an alarm,
and you stop and tell me rather than tidying it away.

**5. Integrate.** `make lock`, commit the brief and the lock here, and report:
what changed per repo, what the tests said, what is still unproven, and what I
now need to decide.
