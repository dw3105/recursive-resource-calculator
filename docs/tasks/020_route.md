# 020 — belts and pipes that carry every demand at once

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-020`, branch `lane/020`, base = `feat/round-8-blueprints`, tag `wave-2-green` (resolve it with `git rev-parse wave-2-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/route.lua` and `tests/test_route.lua` only.
- Pure Lua: plain data in, plain data out.
- You create no inserters: a block already carries the ones serving its machines. You create belts, undergrounds, splitters and pipes.
- Different fluids never share a segment. An underground pair is legal only when the rotated connections face each other within their own distance.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/route.lua` carries the contract and the stubs `Route.begin(input)` and `Route.step(state, budget)`.
- `logic/bp/grid.lua` (wave 1) gives occupancy, rotation and direction helpers. `Grid.RESERVED.corridor` is the owner a router may place through when the caller allows it.
- `logic/bp/plan.lua` (wave 2) gives flows with producer and consumer shares, and ports with their rates and minimum lanes.
- `logic/catalog.lua` (wave 1) gives the belt family with `items_per_second` and `lane_items_per_second`, the underground's own max distance, the pipe family, and each machine's rotated `pipe_connections` with `connection_type` and per-connection `max_underground_distance`.
- Capacity is an allocation, never a comparison of one rate against one capacity: a `Segment` carries who gets how much through it, so one belt cannot promise its whole throughput twice (`docs/feature-contracts.md` §9).
- Failure codes: `BP_R_NO_PATH`, `BP_R_CAPACITY`, `BP_R_EXPANSIONS`, `BP_R_PORT_BLOCKED`, `BP_R_FLUID_MIX`.
- Budget is spent inside route expansion, not only between flows.

## What to build

1. `Route.begin`/`Route.step` connect every block port to its producers, its consumers or a perimeter port, within the budget, keeping a cursor.
2. Each placed entity carries its direction as travel, its flow id, and, for an underground endpoint, its role and its partner's id.
3. Segments carry their allocations, so a shared belt states what each consumer gets. A demand that cannot be met at the same time as the others is `BP_R_CAPACITY`, never a silent shortfall.
4. Extra lanes or parallel runs may be added where capacity needs them; the selected infrastructure is never upgraded to a faster tier.
5. Red-first cases in `tests/test_route.lua`: a single producer to a single consumer routes and the belt direction follows travel; an underground pair is placed only when both rotated connections face each other within the connection's own distance, and a reversed pair is refused; a pair beyond the distance is refused; two fluids never share a segment; a shared belt serving an intermediate consumer and an external output allocates both and refuses when the two cannot both be met; a blocked port is reported rather than routed through an obstacle; the same input routes identically twice; a tiny budget reaches the same routes as an unbounded one; a route never overlaps a machine or a roboport.
6. Planted breach, pasted red then reverted: compare each demand against the segment capacity one at a time instead of summing allocations, and the shared-belt case must go red.

## What done mean

```checks
{"name": "route-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-green --manifest docs/tasks/020.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-2-green -- logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_route.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-2-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/route.lua`
- `tests/test_route.lua`

Touch nothing else.

# bound: 8800s

Reviewer ask: can one belt promise its full throughput to an intermediate consumer and to an external output at the same time?
