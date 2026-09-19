# 053 — Two perimeter ports never stand on one cell

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-053`, branch `lane/053`, base = `feat/round-8-blueprints`, tag `collision-base` (resolve it with `git rev-parse collision-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Fourth defect found by a real sheet, and the only thing left between a player's Generate click and a blueprint.

## What is true

**PRESERVE:**
- You own `logic/bp/search.lua` and `tests/test_search.lua`. Everything else is frozen; if you need a change elsewhere, stop and report.
- `tests/test_blueprint_pipeline.lua` is **not** yours. Its case `mandatory real-sheet case: a calculated nonzero chain reaches delivered blueprint` fails today and is your target: make it pass by fixing the defect, never by editing that file.
- Every existing case stays. Bound every wait at 600 iterations and fail the case naming the phase it stopped in.
- `require` runs only while `control.lua` is parsed. Never call it inside a function.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts, reproduced on this base with a probe over the real `raw -> gear` sheet at rate 1:

```text
PROBE flows:
  flow item/gear producers=[gear] consumers=[$external]
  flow item/raw producers=[$external] consumers=[gear]
PROBE blocks:
  block block:gear
    port in:item/raw role=in flow=item/raw step=gear
    port out:item/gear role=out flow=item/gear step=gear
PROBE perimeter:
  perimeter in:item/raw role=in flow=nil x=0 y=0
  perimeter out:item/gear role=out flow=nil x=0 y=0
```

- Both perimeter ports stand on cell `(0, 0)`. One cell carries one belt, so the second port is unreachable, routing reports `BP_R_PORT_BLOCKED`, and the search ends `BP_FAIL_NO_LAYOUT_GRID_LIMIT` (`logic/bp/search.lua:519`).
- Why they collide: `logic/bp/search.lua:307-330` builds each edge's slots from that edge's own origin, and `logic/bp/search.lua:343-354` takes slot number 1 for the first input and slot number 1 for the first output. `logic/bp/settings.lua:14-15` makes the default edges `left` and `top`, whose first slots are both `(0, 0)` — the shared corner. So every default sheet hits this.
- `logic/bp/settings.lua:273` already refuses input edge equal to output edge, so the two edges always differ and only their shared corner can collide.
- `docs/feature-contracts.md` §18 fixes where a perimeter port sits: on the grid's own edge cell, `travel_dir` out for an output and in for an input. That rule stays.
- Lane 044 added the in-grid slot rule and lane 047 the block port binding; both are merged in this base. This defect is neither.

## What attempt 1 left behind

Attempt 1 reached the goal and ran out of its deadline mid-cleanup. Its commit `d4c7d89` is in your branch as
`WIP: 053_perimeter_collision`. On that tree `tests/test_search.lua` is 36/36, `tests/test_route.lua` 28/28 and
`tests/test_blueprint_pipeline.lua` 22/22, so the real-sheet gate already passes. Finish it; never restart it.

What must change before it can merge:

- `logic/bp/search.lua` carries a skip that applies to an output port only: after choosing a slot it advances one
  further when the previous slot is blocked. Attempt 1 called it a probe workaround and said it was being removed.
  Remove it. The rule is one rule for both roles: take the next slot on your own edge that no other perimeter port
  holds and that nothing blocks.
- The same commit also changes `occupied_rects` to derive a rectangle from `entity.position`, adds
  `perimeter_roboport_clearance`, and adds `can_stop_implicit_perimeter_search`. Each one either earns a case in
  `tests/test_search.lua` that fails without it, or it goes. Say in your report which you kept and why.
- Every case that passes today keeps passing, including the real-sheet gate you must never edit.

## What to build

1. A cell carries at most one perimeter port. When the chosen edges share a corner, the port that would repeat it takes the next slot along its own edge instead.
2. Edges, pitch and travel directions stay as §18 says: an output leaves the grid, an input enters it.
3. When an edge genuinely runs out of slots, say so with the existing search failure code rather than stacking two ports on one cell.
4. `tests/test_search.lua` gains cases: the default `left` input with `top` output places two ports on two different cells; every pair of differing edges that shares a corner does the same; a grid too small for the ports fails with a reason code and never with two ports on one cell; the existing in-grid and travel-direction cases still hold.
5. Plant the defect yourself — put both first slots back — and paste the red run showing two ports on `(0, 0)`, then the green run.

## What done mean

```checks
{"name": "search-and-route", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_route.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "real-sheet-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base collision-base --manifest docs/tasks/053.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the red run with both ports on `(0, 0)`, then the green run, then the real-sheet case reaching `success`.
- `git diff --stat collision-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `logic/bp/search.lua`
- `tests/test_search.lua`

Touch nothing else.

# bound: 1800s

Reviewer ask: does one Generate click on a real calculated sheet end with a blueprint in the player's hand?
