# 011 — sheet numbers into whole machines and flows

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-011`, branch `lane/011`, base = `feat/round-8-blueprints`, tag `wave-1-green` (resolve it with `git rev-parse wave-1-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/plan.lua` and `tests/test_bp_plan.lua` only.
- This is the only blueprint module allowed to read `prototypes`, `storage`, `game` or `Utils.IS_2_1`. Everything after it takes plain data.
- `Step.machine_count` is computed here once and is read-only afterwards. Nothing downstream may call `Utils.machine_amount`.
- The round-up display checkbox never reaches a physical count. Counts come from the full-precision rate.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/plan.lua` carries the shapes at the top and the stubs `Plan.begin`, `Plan.step` and `Plan.machine_count`.
- `logic/catalog.lua` (wave 1) supplies the prototype projection; call `Catalog.build`. `logic/snapshot.lua` supplies the sheet.
- Machine counts are computed today in the GUI: `Utils.machine_amount(recipe, rate, machine, quality, setup)` (`logic/utils.lua:81`), used at `gui/report.lua:225` for ordinary rows and at `:472`, `:567`, `:580`, `:627` for the quality-loop stages. Use the same arithmetic, then take the ceiling with the calculator's tolerance `max(1e-9, |x| * 1e-9)`.
- `logic/compute_power_and_pollution.lua:6` shows the beacon estimate the sheet uses: `group.count * machine_amount / group.sharing`. That is an estimate for power, not a placement rule: `count_per_machine` in a `BeaconGroup` is the minimum coverage each machine must physically get, and `sharing` is carried for information only.
- A solver result's columns and rates are documented at `logic/solver.lua:832-840`. A column key is a recipe name, or a burner prefix, or a quality-loop prefix.
- Beacon groups live in a machine's module setup: `{name, quality, count, sharing, modules}` (`logic/module_setup.lua`). A module's effects tell you whether it is a quality module or a speed module; identify by effect, never by name, because a mod can name a module anything.
- `docs/feature-contracts.md` §9 fixes the flow and allocation shapes, §3 the identities and tolerance.

## What to build

1. `Plan.begin`/`Plan.step` turn one successful snapshot plus its solver result into the documented `PlanIR`: steps, flows, ports and totals, each sorted by its own key.
2. `Plan.machine_count` returns the whole number of machines a step needs: the ceiling of the full-precision requirement within tolerance, and at least one for any step with work to do. A zero-rate step needs none.
3. Per step: the chosen recipe and its quality, the machine and its quality, the ordered modules per machine, the beacon groups with their minimum coverage, whether the machine holds a quality module, and the per-machine power and pollution.
4. Flows carry producers and consumers with their shares, with `$external` on either side for what the world supplies or takes away. Ports carry the external interface with a rate and a minimum lane count.
5. Red-first cases in `tests/test_bp_plan.lua`: a step needing 6.2 machines plans 7, and the round-up checkbox changes nothing in either position; a zero-rate step plans none; a step with a positive requirement below one machine plans one; module slots and their order survive; a beacon group's minimum coverage survives and its sharing does not become a placement number; a shared intermediate appears once as a flow with two consumers whose shares sum to what is produced; a byproduct appears as a flow with an external consumer; a fluid flow is marked as one; totals count machines and steps the way the size limits count them; nothing in a `PlanIR` is a LuaObject.
6. Planted breach, pasted red then reverted: use the rounded display count instead of the full-precision requirement, and the 6.2-machine case must go red.

## What done mean

```checks
{"name": "bp_plan-tests", "command": "lua5.2 tests/test_bp_plan.lua && lua5.4 tests/test_bp_plan.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-green --manifest docs/tasks/011.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-1-green -- logic/bp/plan.lua; out=$(cd \"$S\" && lua5.2 tests/test_bp_plan.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-1-green HEAD` pasted.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/plan.lua`
- `tests/test_bp_plan.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: does the round-up checkbox change any physical machine count, and do a flow's consumer shares add up to what its producers make?
