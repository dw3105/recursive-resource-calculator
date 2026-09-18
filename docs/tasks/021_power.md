# 021 — poles that cover everything and wires that are legal

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-021`, branch `lane/021`, base = `feat/round-8-blueprints`, tag `wave-2-green` (resolve it with `git rev-parse wave-2-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/power.lua` and `tests/test_power.lua` only.
- Pure Lua: an opaque list of rects to cover comes in, poles and wire edges go out.
- Roboports are excluded from required coverage by design.
- Power runs on copper. A wire edge between circuit connectors is never an electric connection.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/power.lua` carries the contract and the stubs `Power.begin(input)` and `Power.step(state, budget)`.
- `logic/catalog.lua` (wave 1) gives the pole's supply area and wire reach at its own quality, through the prototype's accessors.
- Connector ids come from `defines.wire_connector_id`: `pole_copper` carries power, `power_switch_left_copper` and `power_switch_right_copper` belong to a power switch, and every `circuit_*` connector never carries power.
- A wire edge is `{a_id, a_connector, b_id, b_connector}` and is legal only when both endpoints exist, both connectors are copper, and the centre distance is within the smaller of the two poles' reach at their own quality (`docs/feature-contracts.md` §9).
- `logic/bp/grid.lua` (wave 1) gives occupancy and rect helpers.
- Codes: `BP_PW_UNCOVERED` names the ids left uncovered, `BP_PW_DISCONNECTED` reports how many components the network fell into.

## What to build

1. `Power.begin`/`Power.step` place poles until every consumer rect is inside some pole's supply area, spending the budget across candidate positions and keeping a cursor.
2. Fewer poles is better, subject to coverage and connectivity; the search is bounded and deterministic, and its result is the best found rather than a claimed minimum.
3. The chosen wire edges are returned with the poles, each legal by the rule above, and the graph they form is one component.
4. An accessible connection point for external power is provided.
5. Red-first cases in `tests/test_power.lua`: every consumer is covered and the count of poles is reported; a roboport left uncovered is not a failure; two clusters further apart than the reach cannot be joined and are reported as disconnected rather than wired anyway; every returned edge is within the smaller of the two poles' reach; a higher quality pole reaches further and needs fewer poles for the same row; no edge uses a circuit connector; the same input gives the same poles and the same edges; a consumer that no pole position can cover is named in `BP_PW_UNCOVERED`.
6. Planted breach, pasted red then reverted: use the first pole's reach for both ends of an edge, and the reach case must go red with a mixed-quality fixture.

## What done mean

```checks
{"name": "power-tests", "command": "lua5.2 tests/test_power.lua && lua5.4 tests/test_power.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-green --manifest docs/tasks/021.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-2-green -- logic/bp/power.lua; out=$(cd \"$S\" && lua5.2 tests/test_power.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-2-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/power.lua`
- `tests/test_power.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: is every returned wire edge within the smaller of its two poles' reach at their own quality, and is a circuit connector ever used?
