# 044 — a perimeter port stands on the grid, not outside the world

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-044`, branch `lane/044`, base = `feat/round-8-blueprints`, tag `perimeter-base` (resolve it with `git rev-parse perimeter-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Second defect found by a real sheet, and the last known thing between a player's Generate click and a blueprint.

## What is true

**PRESERVE:**
- You own `logic/bp/search.lua`, `logic/bp/route.lua`, `tests/test_search.lua` and `tests/test_route.lua`. Everything else is frozen; if you need a change elsewhere, stop and report. `logic/bp/grid.lua` is **not** yours: `Grid.edge_slots` is correct for a block envelope, which is what it was written for.
- Lane 039 owns `gui/blueprint_dialog.lua`, `logic/bp/generation.lua` and `logic/engine_test_api.lua` and is working in parallel. Never touch them.
- Every existing case stays. Bound every wait at 600 iterations and fail the case naming the phase it stopped in.
- `require` runs only while `control.lua` is parsed. Never call it inside a function.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts, reproduced from a real calculated sheet by lane 039 and confirmed here:
- `logic/bp/search.lua:314-315` builds the factory's own ports with `Grid.edge_slots({x = 0, y = 0, w = grid.w, h = grid.h}, edge, pitch)`. `Grid.edge_slots` follows §5.8 and returns the tile **outside** the envelope, so a left-edge slot is `x = -1` and a top-edge slot is `y = -1`.
- `logic/bp/route.lua:258-261` maps any cell with `x < 0`, `y < 0`, `x >= grid.w` or `y >= grid.h` to `"__outside__"`, and routing treats that as blocked.
- The observed result on a real sheet: `perimeter=(-1,2) ok=false code=BP_R_PORT_BLOCKED`, `perimeter=(0,2) ok=true code=nil`, ending in `failure/search BP_FAIL_NO_LAYOUT_GRID_LIMIT` with nothing delivered.
- `docs/feature-contracts.md` §18 now decides it: a perimeter port sits on the grid's own edge cell, **inside** the grid, with `travel_dir` pointing out for an output and in for an input. Block ports keep §5.8 unchanged. Nothing outside the grid is ever a routing endpoint.

## What to build

1. Make the factory's own input and output ports land on the grid's edge cells, per §18, keeping the chosen edges and the pitch.
2. Keep the travel directions right: an output leaves the grid, an input enters it.
3. Leave block ports alone: their attach tile is still outside their block and inside the grid, and `tests/test_route.lua` proves that today.
4. Add a case in `tests/test_search.lua`: a real small plan on a grid reaches `state.ok == true` with a serialized result, and every perimeter port is inside the grid.
5. Add a case in `tests/test_route.lua`: a perimeter port on each of the four edges is routable, and a cell genuinely outside the grid stays blocked.
6. Add a case that an output port's travel direction leaves the grid and an input port's enters it.
7. Plant the defect yourself — put the outside-the-grid slots back — and paste the red run showing `BP_R_PORT_BLOCKED`, then the green run.

## What done mean

```checks
{"name": "route-and-search", "command": "lua5.2 tests/test_route.lua && lua5.2 tests/test_search.lua && lua5.4 tests/test_route.lua && lua5.4 tests/test_search.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "algorithm-neighbours", "command": "lua5.2 tests/test_pack.lua && lua5.2 tests/test_power.lua && lua5.2 tests/test_groups.lua && lua5.2 tests/test_validate.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base perimeter-base --manifest docs/tasks/044.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the red run with `BP_R_PORT_BLOCKED`, then the green run reaching `state.ok == true`.
- `git diff --stat perimeter-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `logic/bp/search.lua`
- `logic/bp/route.lua`
- `tests/test_search.lua`
- `tests/test_route.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does a small real plan now reach a serialized layout, with every perimeter port on a grid cell?
