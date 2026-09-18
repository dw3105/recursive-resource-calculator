# 004 — tile algebra, and the only rotation in the mod

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-004`, branch `lane/004`, base = `feat/round-8-blueprints` `4569c48ca39995d321f26ec11403fb273e7a194a` (tag `wave-0-spine`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/grid.lua` and `tests/test_grid.lua` only.
- Pure Lua: no `prototypes`, no `storage`, no `game`, no GUI. Everything in, everything out, is plain data.
- Rotation exists here and nowhere else. Four lanes depend on getting one answer from one place.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/grid.lua` carries the conventions and the stubs: rect and occupancy helpers, `subtract`, `prune`, `free_regions`, the four rotation operations, direction helpers, `centre`, `place_member`, `place_port`, `beacon_area`, `robo_grid`, `edge_slots`, and `Grid.RESERVED`.
- A `TileRect {x, y, w, h}` covers tiles `x .. x+w-1`. A centre is derived: `x + w/2`. A 3-wide machine sits on a `.5` centre, a 4-wide roboport on a whole number, which is what the game's own blueprints show.
- Directions are `0, 4, 8, 12` only (north, east, south, west on the 16-step scale). `defines.direction` is available.
- The east formulas, fixed by the contract: cell `(dx, dy) -> (h - 1 - dy, dx)`; rect `(dx, dy, a, b) -> (h - dy - b, dx, b, a)`; point `(px, py) -> (h - py, px)`; vector `(vx, vy) -> (-vy, vx)`. South and west follow by composing east.
- Free regions may overlap each other; that is the point of MaxRects. Their areas can never be summed to mean available space.
- A beacon's area here is a bound for the packer. It is never written into the occupancy cells: beacon influence overlaps and crosses block boundaries, unlike the entities themselves. Whether a machine truly receives a beacon is the validator's question, from collision boxes.

## What to build

1. Occupancy: `Grid.new`, `index`, `get` (nil outside the grid), `can_place(grid, rect, allow)` returning false plus the blocking owner, `fill`, `clear`. `allow` is a set of owners a placement may overlap, so the router may use a reserved corridor while a machine may not.
2. Rect algebra: `intersects`, `contains`, `subtract` (up to four pieces, in a fixed order, overlapping allowed), `prune` (drop contained rects, stable, and report how many were dropped so a caller can enforce a cap without losing geometry silently), `free_regions`.
3. The four rotation operations, plus `rotate_size`, `rotate_dir`, `dir_vector`, `dir_opposite`, `dir_from_vector`, and the two placement helpers `place_member` and `place_port` that every other module must go through.
4. `beacon_area(rect, supply_w, supply_h)`.
5. `robo_grid{cols, rows, tile_w, tile_h, max_connection_distance}`: ports at the widest spacing that still connects, at every intersection, with the envelope around their footprints. Spacing comes from the argument, never from a vanilla constant.
6. `edge_slots(envelope, edge, pitch)`: attachment slots along one edge, ordered from the origin corner, facing outward.
7. Red-first cases in `tests/test_grid.lua`, each named `G<n> ...`: the 10 by 10 area with a 2 by 2 obstacle at (4, 4) still offers a free region tall enough for a 3 by 8 block, which is the case a disjoint split would hide; subtract returns overlapping alternatives and their areas do not sum to the free area; prune drops a contained rect and reports the count; an 8 by 6 block whose member is `x=1, y=1, w=3, h=2` rotates east to `x=3, y=1, w=2, h=3` (independently enumerate the occupied cells to check it, do not reuse the formula); four rotations return every member and every port to where it started; a port adjacent to its block stays adjacent after each rotation; a vector gains no one-tile shift; odd and even sized entities produce `.5` and whole centres; `can_place` refuses an overlap and allows an explicitly allowed owner; a beacon area is never written into the cells.
8. Planted breach, pasted red then reverted: rotate a rect with the cell formula, and the 8 by 6 case must go red.

## What done mean

```checks
{"name": "grid-tests", "command": "lua5.2 tests/test_grid.lua && lua5.4 tests/test_grid.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base 4569c48ca39995d321f26ec11403fb273e7a194a --manifest docs/tasks/004.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout 4569c48ca39995d321f26ec11403fb273e7a194a -- logic/bp/grid.lua; out=$(cd \"$S\" && lua5.2 tests/test_grid.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat 4569c48ca39995d321f26ec11403fb273e7a194a HEAD` pasted.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/grid.lua`
- `tests/test_grid.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: does a multi-tile member rotate to independently enumerated cells in all four directions, and do four rotations restore the original exactly?
