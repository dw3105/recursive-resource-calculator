# 168 search: stop when the incumbent stops improving; groups.begin resumable

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-168`, branch
`lane/168`, base tag `round-23-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-23-base`.

## You have about 35 minutes — do NOT stop early

**Do not end your turn until every item under "What to build" exists, is committed, and both checks have
run.** Stopping with uncommitted work is a failed lane. If one item is truly blocked, commit everything
else, then say which item and why.

## Explain very simply

The player clicked "generate" in Factorio 2.0.77 on 2026-09-23. After 10 minutes it was still
calculating and the game ran at 3 UPS the whole time. The game advances a blueprint search once per tick
with a budget of 2000 ops (`Jobs.OPS_PER_TICK`, `logic/jobs.lua`). A tick must stay short (a frame is
16.7 ms). Some steps do seconds of work inside ONE call and never give the tick back.

`tools/speed_probe.sh` replays the player's sheet exactly as the game does (2000 ops per `Search.step`) and
times every `begin`/`step` of each `logic/bp` module. `tools/speed_gate.sh` turns its output into a
pass/fail line. Measured at `round-23-base` on legalcopilot-dev 2026-09-23, `CAP=40`:

```
pack.step     worst 8.157 s   (4 calls, 18.3 s)
route.begin   worst 1.340 s   (4 calls, 4.2 s)
route.step    worst 0.783 s   (25 calls, 6.6 s)
groups.begin  worst 0.611 s
power.step    416 calls per power.begin (about 830k ops per candidate), worst 0.016 s
```

The rule for every module: **one op costs a few microseconds**, so 2000 ops fit in about 20 ms. A long
loop checks the budget and returns; the next call resumes from a cursor stored on the state.

The result must not change. `tests/fixtures/blueprints/round22_v5.txt` is the player's accepted blueprint
(v5, 242 entities, placed in game 2026-09-23).

## Where the code is

- `logic/bp/search.lua`: the search walks grids (`ordered_grid_specs`, at most `grid_trial_limit` =
  `CANDIDATE_ALLOWANCE` 4 grids) and, per grid, every candidate from `Groups` in every block ordering
  (`candidate_orders`), each through pack → route → power → validate. It only stops at the grid limit
  (`BP_FAIL_GRID_LIMIT`) or the op allowance (`declare_allowance`, `begin_improvement_budget`). The last
  full run on the player's sheet validated 13 layouts (1 chosen, 12 discarded) and cost about 200 s of CPU.
- `logic/bp/groups.lua`: `Groups.begin` does 0.611 s of work in one call.

## What to build

1. **Measure first.** Instrument (temporarily, not committed) which attempt produced the final incumbent
   on the player's sheet: its grid index, candidate index and ordering index, and how many attempts came
   after it without improving. Put these numbers in your commit message.
2. **Stop rule.** Once an incumbent exists, stop the search after `K` further validated attempts that do
   not improve it (`K` named constant, default chosen from your measurement so the player's sheet keeps its
   chosen layout), and never spend more than a declared op cap after the first incumbent. Record the stop in
   the result's `search` block (`stop = "no_improvement"`). Deterministic.
3. **`Groups.begin` cheap.** Move the expensive part of `Groups.begin` into `Groups.step` phases that spend
   ops and resume from a cursor; identical `candidates`.
4. `tests/test_search_stop.lua` (new), each row **red at `round-23-base`**:
   - **SS1** a search whose later attempts cannot beat the first incumbent stops after `K` of them with
     `stop = "no_improvement"` and returns the first incumbent.
   - **SS2** `Groups` run with `{ops = 1}` per call and with `{ops = 10^9}` give identical candidates, and
     `Groups.begin` alone does no candidate enumeration (counter on state).
5. Baseline, full run to the end at `round-23-base`, 2026-09-23 on legalcopilot-dev:
   `SPEED END ticks=10490 cpu=208.63 worst_tick=18.849 done=true ok=true entities=242` over 12 candidates
   (pack.step 103.49 s, power.step 47.46 s, route 48.32 s). Your gate: finish with cpu <= 105 (half) and
   entities <= 242 -- by stopping earlier, not by making any module faster.
6. Report `CAP=900 sh tools/speed_probe.sh` (the SPEED END line: ticks, cpu, entities) before and after.

## Traps

- **Determinism.** Same input, same layout: `tests/test_route_budget.lua`, `coord_key`. A cursor that
  resumes must visit exactly the same things in exactly the same order as the one-shot loop did.
- **Every budget size gives the same answer.** Run your module's tests with a budget of 1 op and of a huge
  budget; results must be identical.
- **Measure with the probe, not the full product.** `CAP=40 sh tools/speed_probe.sh` takes about 40 s;
  `sh tools/round21_product.sh` takes about 200 s — run it once, at the end, alone. Never run two long
  commands at the same time (the host wedged 2026-09-23 when two ran together).
- **Never touch** `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except
  this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/search.lua`, `logic/bp/groups.lua`, `tests/test_search_stop.lua`

## Commit, THEN check

Commit on `lane/168` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "search-regress", "command": "git diff --name-only round-23-base HEAD | grep -v '^docs/tasks/168' | grep -Ev '^(logic/bp/search\\.lua|logic/bp/groups\\.lua|tests/test_search_stop\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_search_stop.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo search-regress-ok", "expect_exit": 0, "expect_regex": "search-regress-ok", "timeout_s": 1800}
{"name": "search-speed", "command": "CAP=900 sh tools/speed_probe.sh > /tmp/rrc168-speed.txt; cat /tmp/rrc168-speed.txt; sh tools/speed_gate.sh worst groups.begin 0.03 < /tmp/rrc168-speed.txt && sh tools/speed_gate.sh end 105 242 < /tmp/rrc168-speed.txt && echo search-speed-ok", "expect_exit": 0, "expect_regex": "search-speed-ok", "timeout_s": 1500}
```

# bound: 2400s
