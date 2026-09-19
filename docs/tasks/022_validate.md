# 022 — the second opinion, from the exact geometry

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-022`, branch `lane/022`, base = `feat/round-8-blueprints`, tag `wave-3-repair-base` (resolve it with `git rev-parse wave-3-repair-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game, never tables. Never write `type(prototypes) == "table"`; ask `rawget(_G, "prototypes")` instead (`docs/feature-contracts.md` §2c). `tests/test_guards_userdata.lua` refuses the pattern in any shipped file.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/validate.lua` and `tests/test_validate.lua` only.
- You may not call the packer, the router, the grouper or the power module. You check what they produced, from the catalog's exact geometry.
- You never use the integer occupancy grid: collisions come from collision boxes and masks, beacon reception from the engine's rule. A checker sharing the builder's model cannot catch the builder's mistake.
- Work from hand-written candidate fixtures. Do not wait for the search to exist.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/validate.lua` carries the contract and the stubs `Validate.begin`, `Validate.step` and `Validate.compare(a_score, b_score)`.
- A candidate carries its grid, its placed entities, its placements and blocks for provenance, and its port bindings (`docs/feature-contracts.md` §7 to §10).
- `logic/catalog.lua` (wave 1) gives `collision_box` and `collision_mask`, the beacon supply area at quality, machine footprints, and the belt, pipe and inserter numbers.
- Wire checking is ordered: every edge is checked for legality first (`BP_V_WIRE_ILLEGAL`), and only edges that passed build the graph whose connectivity is judged (`BP_V_WIRE_DISCONNECTED`).
- Flow checking is by allocation: per flow, produced plus supplied equals consumed plus removed within `EPS(x) = max(1e-9, |x| * 1e-9)` (`BP_V_FLOW_IMBALANCE`); per segment, allocations fit capacity; every consumer's share must be reachable at the same time as every other's (`BP_V_TARGET_SHORTFALL`).
- `Step.machine_count` is authority: count what was placed and compare (`BP_V_MACHINE_COUNT_MISMATCH`). Never recompute the requirement.
- The score is beacon count, then footprint area, then pole count, then deterministic tie-breakers, and `Validate.compare` is the only place that order lives.

## What to build

1. `Validate.begin`/`Validate.step` check a finished candidate within the budget and return a score and metrics, or a list of violations.
2. Checks: collisions from the exact boxes; containment in the grid; roboport connectivity; beacon reception recomputed from the final set of influencing beacons, including effects and counter rules; quality isolation as a hard failure; pole coverage and wire legality then connectivity; every flow routed; fluids unmixed; flow conservation and simultaneity; capacities for belts, pipes and inserters; underground pairing and range; port edges and reachability; machine counts and module loadouts.
3. `Validate.compare` implements the objective order and nothing else scores.
4. Red-first cases in `tests/test_validate.lua`: a candidate whose entities touch but do not overlap passes, while one overlapping by a fraction of a tile fails, which the integer grid would have accepted; a machine one tile outside the grid fails; a beacon that covers a quality machine and holds a speed module fails; a beacon short of a configured group fails while extra coverage passes; an over-range wire fails as illegal; a circuit-connector bridge fails; poles connected only through an illegal edge fail as disconnected; a belt carrying two consumers beyond its capacity fails as a shortfall while the same belt inside capacity passes; a flow whose shares do not balance fails; an underground pair beyond range fails; a placed machine count differing from the plan fails; `compare` orders two scores by beacons first, then footprint, then poles.
5. Planted breach, pasted red then reverted: check collisions with tile footprints instead of collision boxes, and the fractional overlap case must go red.

## What done mean

```checks
{"name": "validate-tests", "command": "lua5.2 tests/test_validate.lua && lua5.4 tests/test_validate.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-3-repair-base --manifest docs/tasks/022.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-3-repair-base -- logic/bp/validate.lua; out=$(cd \"$S\" && lua5.2 tests/test_validate.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-3-repair-base HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/validate.lua`
- `tests/test_validate.lua`

Touch nothing else.

# bound: 8800s

Reviewer ask: does the validator catch a fractional overlap the integer packer would accept, and is an over-range wire refused before connectivity is judged?
