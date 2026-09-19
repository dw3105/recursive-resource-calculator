# 047 — A block port names its step, and an external port stays on the perimeter

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-047`, branch `lane/047`, base = `feat/round-8-blueprints`, tag `binding-base` (resolve it with `git rev-parse binding-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Third defect found by a real sheet, and the last known thing between a player's Generate click and a blueprint.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/route.lua`, `tests/test_groups.lua` and `tests/test_route.lua`. Everything else is frozen; if you need a change elsewhere, stop and report. `logic/bp/plan.lua` and `logic/bp/search.lua` are **not** yours.
- Lane 039 holds uncommitted work in `/home/dev_zaigraev_gmail_com/wt-rrc-039` on `gui/blueprint_dialog.lua`, `logic/bp/generation.lua` and `logic/engine_test_api.lua`. Never touch them.
- Every existing case stays. Bound every wait at 600 iterations and fail the case naming the phase it stopped in.
- `require` runs only while `control.lua` is parsed. Never call it inside a function.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts, reproduced from a real calculated sheet by lane 039 attempt 3 and confirmed here on this base:

- `logic/bp/plan.lua:554-564` builds a plan port for each flow with an `$external` producer or consumer. That port carries `port_id`, `role`, `full_name`, `rate_per_second`, `kind` and `min_lanes`, and carries **no `step_id` and no `flow_id`**. It is the factory's own supply or removal point, and `logic/bp/search.lua:342-353` already turns exactly these ports into perimeter endpoints.
- `logic/bp/groups.lua:581-597` also hands those same plan ports to a block. `relevant_ports` includes a port when the flow it names has a producer or consumer among the block's steps (`logic/bp/groups.lua:590-594`), which is true for every external port of a one-block factory. So one plan port becomes both a perimeter endpoint and a block port.
- `logic/bp/route.lua:316` reads `step_id = port.step_id or block.step_id or block.block_id or block.id`. A plan port has no `step_id`, so its block endpoint gets `step_id = "block:gear"`, while the plan flow's producer entry names `step_id = "gear"`.
- `logic/bp/route.lua:386-395` binds a demand by `(flow_id, role, step_id)`. The step ids never match, so `logic/bp/route.lua:431` raises `BP_R_PORT_BLOCKED` with `detail = "producer port is not bound"`, and the search ends `BP_FAIL_NO_LAYOUT_GRID_LIMIT` (`logic/bp/search.lua:519`).
- Observed on a one-recipe `raw -> gear` sheet at 0.1 per second: `Route sees internal ports on block:gear, while plan flow entries reference gear`, terminal `failure/search BP_FAIL_NO_LAYOUT_GRID_LIMIT`, cursor unchanged.
- `docs/feature-contracts.md:206` defines `BlockPort` with `member_id` and attach coordinates; `logic/bp/plan.lua:13` defines `PlanPort` with neither. They are different types and one is never the other.
- `logic/bp/groups.lua:603-625` already materializes a block's own ports from each step's `inputs` and `outputs`, and those carry `step_id = step.step_id`. Today that path runs only when the caller supplies no ports at all.

## What to build

1. A block port is built from the block's own steps and always carries the `step_id` of the step it serves. An external plan port is never turned into a block port.
2. A plan port with no `step_id` keeps serving as a perimeter endpoint exactly as it does today. `logic/bp/search.lua` stays unchanged.
3. Route binds a producer endpoint and a consumer endpoint for every flow of a real one-step plan. Where route must still fall back for a port with no `step_id`, the fallback resolves to a step of that block, never to the block id.
4. `tests/test_groups.lua`: a real plan's external port list plus one step produces block ports whose `step_id` names the step, and no block port whose `step_id` starts with `block:`.
5. `tests/test_route.lua`: a plan-shaped input — flows whose producers and consumers name step ids, external ports with no `step_id`, one block from `Groups` — routes with `state.ok == true`, and both endpoints of each flow are bound. A port that genuinely belongs to no step still fails with `BP_R_PORT_BLOCKED`.
6. Plant the defect yourself — put the external plan port back into the block — and paste the red run showing `BP_R_PORT_BLOCKED` with `producer port is not bound`, then the green run.
7. If binding needs a field that neither `PlanPort` nor `BlockPort` carries, stop and report which field and which contract line, rather than inventing one.

## What done mean

```checks
{"name": "groups-and-route", "command": "lua5.2 tests/test_groups.lua && lua5.2 tests/test_route.lua && lua5.4 tests/test_groups.lua && lua5.4 tests/test_route.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "algorithm-neighbours", "command": "lua5.2 tests/test_search.lua && lua5.2 tests/test_pack.lua && lua5.2 tests/test_power.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_bp_plan.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base binding-base --manifest docs/tasks/047.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the red run with `BP_R_PORT_BLOCKED` and `producer port is not bound`, then the green run with both endpoints bound.
- `git diff --stat binding-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `logic/bp/groups.lua`
- `logic/bp/route.lua`
- `tests/test_groups.lua`
- `tests/test_route.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: on a one-recipe real plan, does every flow bind a producer and a consumer endpoint?
