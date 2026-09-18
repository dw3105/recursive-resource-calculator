# 018 — MaxRects that yields inside its own scan

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-018`, branch `lane/018`, base = `feat/round-8-blueprints`, tag `wave-2-green` (resolve it with `git rev-parse wave-2-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/pack.lua` and `tests/test_pack.lua` only.
- Pure Lua: no `prototypes`, no `storage`, no `game`, no GUI.
- Rotation and rect algebra live in `logic/bp/grid.lua`. Call them; never re-derive a rotation here.
- A block is opaque: its width, its height and the orientations it allows. What is inside it is never this module's business.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/pack.lua` carries the contract and the stubs `Pack.begin(input)`, `Pack.step(state, budget)` and `Pack.bssf_score(free, w, h)`.
- `logic/bp/grid.lua` (wave 1) gives `subtract`, `prune`, `free_regions`, `intersects`, `contains`, `rotate_size` and `RESERVED`. Free regions may overlap; their areas never sum to available space.
- Insertion order is decided by the caller. This module inserts in the order it is handed and never reorders.
- Best Short Side Fit: the smaller leftover side decides, the larger breaks the tie, then coordinates, so one input always gives one output.
- Budget is `{ops = int}` and must be spent **inside** the scan over free regions, not only between blocks (`docs/feature-contracts.md` §6).
- `limits.max_free_regions` caps the region list. Reaching it is reported as `BP_P_REGION_LIMIT`; geometry is never dropped silently to stay under it.

## What to build

1. `Pack.begin` takes the area, the fixed obstacles, the blocks in insertion order and the limits, and returns a plain-data state with a cursor over blocks and regions.
2. `Pack.step` places one block at a time: score every fitting region in every allowed orientation, take the best by BSSF with deterministic ties, subtract the placement from every intersected region, prune, and continue. It returns as soon as the budget is spent, mid-scan if that is where it ran out.
3. A block that fits nowhere is `BP_P_NO_FIT` naming the block; the region list growing past its cap is `BP_P_REGION_LIMIT`.
4. Red-first cases in `tests/test_pack.lua`: the 10 by 10 area with a 2 by 2 obstacle at (4, 4) still takes a 3 by 8 block beside it; blocks never overlap each other or an obstacle; a block that cannot fit is reported and nothing else is disturbed; the same input packed twice gives identical placements; a budget of one operation per step reaches the same placements as an unbounded budget, only over more steps; the cursor is plain data and can be copied and resumed; the peak region count is reported and the cap turns into `BP_P_REGION_LIMIT` rather than a lost block; a rotation-forbidden block is never rotated; BSSF prefers the tighter short side.
5. Planted breach, pasted red then reverted: yield only between blocks rather than inside the scan, and the one-operation budget case must go red.

## What done mean

```checks
{"name": "pack-tests", "command": "lua5.2 tests/test_pack.lua && lua5.4 tests/test_pack.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-green --manifest docs/tasks/018.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-2-green -- logic/bp/pack.lua; out=$(cd \"$S\" && lua5.2 tests/test_pack.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-2-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/pack.lua`
- `tests/test_pack.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: does a one-operation budget reach the same placements as an unbounded one, and does a region cap ever lose a block?
