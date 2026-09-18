# 019 — machines with their beacons, before any placing

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-019`, branch `lane/019`, base = `feat/round-8-blueprints`, tag `wave-2-green` (resolve it with `git rev-parse wave-2-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/groups.lua` and `tests/test_groups.lua` only.
- Pure Lua: plain data in, plain data out.
- A machine holding a quality module must never sit inside a speed beacon's influence. That is a rule here, not a score.
- Every machine the plan asks for appears, and every configured beacon group's minimum coverage is met.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/groups.lua` carries the block and port shapes and the stubs `Groups.begin`, `Groups.step` and `Groups.materialize(block, placement)`.
- `logic/bp/plan.lua` (wave 2) supplies steps with `machine_count`, `modules`, `beacon_groups` (each with `signature`, `count_per_machine`, `has_speed_module`) and `forbids_speed_beacon`.
- `logic/bp/grid.lua` (wave 1) owns rotation and `beacon_area`; `Grid.place_member` and `Grid.place_port` are the only way a member or port is rotated.
- A port attaches to the tile **outside** the envelope, with both coordinates bounded, and carries `normal_dir` pointing in and `travel_dir` for transport (`docs/feature-contracts.md` §10).
- Beacon sharing is the first objective the search minimises, so grouping decides it: machines that can share a beacon strip should be offered as one candidate, and grouping may span different recipes when their beacon setup and interfaces allow.
- `count_per_machine` is a minimum, never an exact count; extra coverage is allowed and is recomputed later by the validator.

## What to build

1. `Groups.begin`/`Groups.step` produce grouping candidates, each a set of blocks, sorted by physical beacon count then by id, within the budget.
2. A block lays out its machines, its beacons and the inserters that serve them relative to its own corner, and exposes one port per external connection.
3. A beacon carries which members it is required to cover; a machine that forbids speed beacons is never placed where a speed beacon covers it.
4. `Groups.materialize(block, placement)` returns the placed entities with ids prefixed `m:`, rotated only through the grid helpers.
5. Red-first cases in `tests/test_groups.lua`: two machines sharing one beacon produce fewer physical beacons than two separate arrangements; every machine of every step appears exactly once; a machine's configured minimum coverage is met; a quality-module machine is never covered by a speed beacon, in any orientation; ports sit outside the envelope with both coordinates bounded, and their normal points inward while an output's travel points outward; members never overlap inside a block; materialize places every member inside the placed envelope and rotates ports with it; the same plan grouped twice gives identical candidates.
6. Planted breach, pasted red then reverted: allow a speed beacon to cover a quality machine when it saves a beacon, and the isolation case must go red.

## What done mean

```checks
{"name": "groups-tests", "command": "lua5.2 tests/test_groups.lua && lua5.4 tests/test_groups.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-green --manifest docs/tasks/019.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-2-green -- logic/bp/groups.lua; out=$(cd \"$S\" && lua5.2 tests/test_groups.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-2-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/groups.lua`
- `tests/test_groups.lua`

Touch nothing else.

# bound: 8000s

Reviewer ask: can any arrangement put a quality-module machine inside a speed beacon's influence, in any of the four orientations?
