# 059 — A block port stands on a free cell, whatever the block's rotation

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-059`, branch `lane/059`, base = `feat/round-8-blueprints`, tag `port-cells-base` (resolve it with `git rev-parse port-cells-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This is the last thing between a player's Generate click and a blueprint on their real sheet.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/route.lua`, `tests/test_groups.lua`, `tests/test_pack.lua` and `tests/test_route.lua`. Everything else is frozen; if you need a change elsewhere, stop and report.
- `docs/tasks/058_reproducer.lua` is the player's sheet shape, reduced: five steps, two sharing beacons, one fluid input, external item inputs, machine identifiers with no `quality`, `round_up = false`. Read it, run it, never edit it.
- Every existing case stays. Bound every wait and make every run finish.
- `require` runs only while `control.lua` is parsed. Never call it inside a function.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Measured on this base, host `legalcopilot-dev`, 2026-09-19:

```text
REPRO state=failure stage=search codes=BP_FAIL_NO_LAYOUT_GRID_LIMIT      (2.7 seconds)
BLOCKED flow=item/cable src=(-1,5 owner=__outside__)  sink=(10,5 owner=machine:block:cable+circuit)
BLOCKED flow=item/cable src=(0,14 owner=nil)          sink=(15,0 owner=machine:block:machine)
```

`item/cable` is produced by step `cable` and consumed by step `circuit`, and beacon sharing puts both steps in one
block, `block:cable+circuit`. Its out-port and the in-port of the same flow therefore attach to the same block.
Two cells are wrong at once: one lands outside the grid, the other lands inside a machine of that very block.

What is already fixed on this base, so do not redo it:

- A port list wider than its block widens the block; every attach tile is on the row above (`attach_dy = -1`) or
  below (`attach_dy = block.h`). `tests/test_groups.lua` case `G12` holds that.
- A port whose tile falls outside the grid mirrors to the block's other side, computed in the block's own frame.
- A path search is bounded by its grid, sixteen visits per cell. `tests/test_route.lua` case `R15` holds that.

What has already been tried and must not be repeated:

- Reserving a one-tile ring around every block in `logic/bp/pack.lua` (lane 058 attempt 2). It made small grids
  unusable, the search grew the grid again and again, and the fixture ran **past 300 seconds** against 2.7
  seconds today. Reserving only the port rows broke the small real-sheet case in `tests/test_blueprint_pipeline.lua`.

## What attempt 1 left behind, and the measurement that names the defect

Attempt 1 committed `WIP: 059_port_cells_free` and hit the same wall as lane 058: on its tree
`lua5.2 docs/tasks/058_reproducer.lua` runs past 90 seconds. Adding constraints to the packer is what makes the
search grow grids forever; the checks below already refuse that.

The measurement that matters, taken on this base (host `legalcopilot-dev`, 2026-09-19):

```text
BLK block:cable+circuit env=(0,5,10x11) dir=4 used=10x11
BLOCKED flow=item/cable src=(-1,5 owner=__outside__) sink=(10,5 owner=machine:block:cable+circuit)
```

The block's envelope starts at `x = 0` and is **10 wide**, so it owns columns 0 to 9. Cell `(10, 5)` is the first
column outside it — exactly where a rotated block's top-row port attaches, and exactly where a belt belongs. Yet
the occupancy index answers `machine:block:cable+circuit` for that cell. The envelope and the occupancy disagree,
and the disagreement is what refuses the port.

So the defect is not where a port attaches. It is that a rotated block writes its machines into cells outside its
own envelope. Find it in `Groups.materialize` or in how `logic/bp/route.lua` indexes those entities, prove it with
a case that places one rotated block and asks which cells it owns, and only then look at ports again.

## What to build

1. A block port attaches to a cell that is inside the grid and free of machines, beacons and inserters, for every
   rotation the packer may choose. Free means routing can put a belt or a pipe there.
2. When no such cell exists for a port, routing fails with `BP_R_PORT_BLOCKED` and a detail naming the cell and
   its owner, which it already does.
3. `tests/test_blueprint_pipeline.lua` stays at 24 of 24; the small real-sheet case is never traded away.
4. `tests/test_groups.lua`: a block holding two steps of one flow exposes the producer's port and the consumer's
   port on two different free cells, in every rotation.
5. `tests/test_route.lua`: the fixture's own shape — a flow between two steps of one block, on a rotated block at
   the grid edge — routes with `state.ok == true`.
6. `lua5.2 docs/tasks/058_reproducer.lua` prints `REPRO state=success` and finishes inside 60 seconds. Paste the
   failing line before your change, the passing line after, and the wall-clock time of the passing run.

## What done mean

```checks
{"name": "reproducer", "command": "timeout 60 lua5.2 docs/tasks/058_reproducer.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 120}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.2 tests/test_pack.lua && lua5.2 tests/test_route.lua && lua5.4 tests/test_groups.lua && lua5.4 tests/test_pack.lua && lua5.4 tests/test_route.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "real-sheet-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_search.lua && lua5.2 tests/test_validate.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base port-cells-base --manifest docs/tasks/059.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

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

Reviewer ask: does the player's own sheet shape reach a blueprint inside 60 seconds?
