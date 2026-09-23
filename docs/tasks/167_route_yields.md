# 167 route: route.begin and the re-route pass split across ticks

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-167`, branch
`lane/167`, base tag `round-23-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

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

`logic/bp/route.lua`.
- `Route.begin` calls `normalize_input` — `map_blocks`, `normalize_endpoint` per port,
  `add_input_obstacles`, `build_demands` (with `pairing_route_cost` per source/sink pair),
  `reserve_port_cells` — all in one call: worst 1.340 s. Profile it first (wrap the helpers with
  `os.clock`) and name the expensive part in your commit.
- `Route.step`: when the last demand is done it runs `improve_routes(work)` (every binding: lift, search
  up to 200000 steps, append; plus one search per hand-slide option), then `unbury_empty_pairs`, then
  `result_for`, all inside ONE call: worst 0.783 s. The per-demand search already spends ops; the
  improve pass ignores the budget.

## What to build

1. **`Route.begin` cheap, rest resumable.** `Route.begin` does only O(ports) setup; the expensive part
   moves into `Route.step` as early phases that spend ops and resume from a cursor.
2. **Improve pass across calls.** `improve_routes` becomes a cursor over bindings and options: each
   re-search spends ops like the demand searches do (one op per `search_step`), and a call returns when
   the budget is spent, resuming mid-search next call. Snapshots/undo stay exactly as today; the kept
   results must be identical.
3. `unbury_empty_pairs` and `result_for` may stay one-shot if each is under 20 ms on the player's sheet
   (measure and report).
4. `tests/test_route_ticks.lua` (new), each row **red at `round-23-base`**:
   - **RT1** `Route.begin` on the player's first candidate input does bounded work: capture a route input
     (or build one from `tests/test_route_hand_slide.lua`'s shape scaled up) and assert that `Route.begin`
     does not run `build_demands` pairing work (counter on work) — it happens in `Route.step`.
   - **RT2** a route run with `{ops = 1}` per call and one with `{ops = 10^9}` give identical `result`
     entities (name, position, direction) and identical `port_slides`.
   - **RT3** with the improve pass reached, one `Route.step({ops = 100})` call spends at most 100
     `search_step`s.
5. Report `CAP=40 sh tools/speed_probe.sh` before and after, and the final product line.

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

`logic/bp/route.lua`, `tests/test_route_ticks.lua`

## Commit, THEN check

Commit on `lane/167` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "route-regress", "command": "git diff --name-only round-23-base HEAD | grep -v '^docs/tasks/167' | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_ticks\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_route_ticks.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_route_hand_slide.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo route-regress-ok", "expect_exit": 0, "expect_regex": "route-regress-ok", "timeout_s": 1800}
{"name": "route-speed", "command": "CAP=60 sh tools/speed_probe.sh > /tmp/rrc167-speed.txt; cat /tmp/rrc167-speed.txt; sh tools/speed_gate.sh worst route.begin 0.03 < /tmp/rrc167-speed.txt && sh tools/speed_gate.sh worst route.step 0.03 < /tmp/rrc167-speed.txt && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1 && python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && cmp $d/bp.txt tests/fixtures/blueprints/round22_v5.txt && echo route-speed-ok", "expect_exit": 0, "expect_regex": "route-speed-ok", "timeout_s": 1500}
```

# bound: 2400s
