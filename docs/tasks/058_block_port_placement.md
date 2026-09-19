# 058 — A block port attaches to a free tile inside the grid

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-058`, branch `lane/058`, base = `feat/round-8-blueprints`, tag `port-tile-base` (resolve it with `git rev-parse port-tile-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

A real player sheet fails with `job_step_failed [search]`. The reproducer below fails offline for a second, simpler reason, and both stop a blueprint from reaching the player.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/route.lua`, `tests/test_groups.lua`, `tests/test_pack.lua` and `tests/test_route.lua`. Everything else is frozen; if you need a change elsewhere, stop and report.
- `docs/tasks/058_reproducer.lua` is the player's sheet shape, reduced. Read it, run it, never edit it. Turn what it proves into cases inside your own test files.
- Every existing case stays. Bound every wait at 900 iterations and fail the case naming the phase it stopped in.
- `require` runs only while `control.lua` is parsed. Never call it inside a function.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Reproduced on this base with `lua5.2 docs/tasks/058_reproducer.lua`: five steps, two of them sharing beacons, one fluid input, external item inputs, machine identifiers with no `quality`, `round_up = false`. It ends

```text
REPRO state=failure stage=search codes=BP_FAIL_NO_LAYOUT_GRID_LIMIT
```

An instrumented `logic/bp/route.lua:765` shows why routing refuses, over and over, on every grid the search tries:

```text
BLOCKED flow=item/cable src=(-1,5 owner=__outside__)  sink=(10,5 owner=machine:block:cable+circuit)
BLOCKED flow=item/cable src=(0,14 owner=nil)          sink=(15,0 owner=machine:block:machine)
```

Two separate defects, both about where a block port attaches:

1. **Outside the grid.** `src = (-1, 5)` is not a grid cell, so `logic/bp/route.lua:270` maps it to `"__outside__"` and `endpoint_is_blocked` refuses it. `docs/feature-contracts.md` §5.8 says a block port's attach tile is the tile outside its **block**, which must still be inside the grid. A block packed against the grid edge breaks that, and `logic/bp/pack.lua` may place a block flush with the edge.
2. **Inside a machine.** `sink = (10, 5)` is owned by `machine:block:cable+circuit`, its own block's machine. The attach tile is inside an occupied cell, so no belt can ever stand there.

Two steps that share one block (`block:cable+circuit`) still exchange `item/cable` through ports on that block's outside. That is the contract's rule and it stays; the ports simply have to land on free cells inside the grid.

## What attempt 1 left behind

Attempt 1 ran out of its deadline and committed `WIP: 058_block_port_placement`, which is in your branch. On that
tree `lua5.2 docs/tasks/058_reproducer.lua` **never finishes**: it was still running after 120 seconds and had
printed nothing. A hang is worse than the failure it replaced, so the first thing you do is bound every loop you
touched and make that command finish, pass or fail, well inside its 900-second check.

Its one useful piece is the failure detail: `endpoint_block_detail` now names the blocked cell and its owner in
`BP_R_PORT_BLOCKED`. Keep that.

## What to build

1. A block port's attach tile is always a free cell inside the grid: never outside the grid, never inside a machine, a beacon or an inserter, and never the same cell as another port.
2. Packing leaves whatever margin that rule needs, or the port chooses a different edge of its own block. Say in your report which of the two you chose and why.
3. Routing keeps refusing a port that genuinely has no free attach cell, with `BP_R_PORT_BLOCKED` and a `detail` naming the cell and its owner, so the next failure explains itself.
4. `tests/test_groups.lua`: a block whose member sits at the grid edge still exposes every port on a free in-grid cell; two steps in one block get two distinct attach cells for the same flow.
5. `tests/test_pack.lua`: a placement that leaves no room for a block's ports is rejected or shifted, never returned as a placement.
6. `tests/test_route.lua`: the reproducer's exact shape — a flow between two steps of one block — routes with `state.ok == true`; a port on a genuinely occupied cell still fails with `BP_R_PORT_BLOCKED` carrying its detail.
7. Run `lua5.2 docs/tasks/058_reproducer.lua` as your evidence: paste its `REPRO state=failure` line before your change, and `REPRO state=success` after.

## What done mean

```checks
{"name": "reproducer", "command": "lua5.2 docs/tasks/058_reproducer.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.2 tests/test_pack.lua && lua5.2 tests/test_route.lua && lua5.4 tests/test_groups.lua && lua5.4 tests/test_pack.lua && lua5.4 tests/test_route.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "algorithm-neighbours", "command": "lua5.2 tests/test_search.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_blueprint_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base port-tile-base --manifest docs/tasks/058.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the reproducer failing before and passing after.
- `git diff --stat port-tile-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `logic/bp/groups.lua`
- `logic/bp/pack.lua`
- `logic/bp/route.lua`
- `tests/test_groups.lua`
- `tests/test_pack.lua`
- `tests/test_route.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does every block port stand on a free cell inside the grid, on the player's own sheet shape?
