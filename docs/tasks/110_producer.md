# 110 producer: put the recipe on the machine and build a chain that moves items

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-110`, branch `lane/110`, base tag `round-13-base` (resolve with `git rev-parse round-13-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 25, rules 25.1, 25.2, 25.3.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`. Baseline: `docs/round-13-baseline.md`.

The player pasted the round-12 blueprint and every machine was **blank**. Measured on this host 2026-09-21:

- `logic/bp/plan.lua` carries every recipe. All seven steps of the captured sheet have `recipe` and
  `recipe_quality`.
- `logic/bp/groups.lua:481-486` builds the machine member with prototype, quality, step identity and modules,
  and never copies `step.recipe` or `step.recipe_quality`.
- `logic/bp/serialize.lua:393` copies `recipe` and `recipe_quality` **only when present**. They are never
  present, so all seven serialized machines carry no recipe.

Catalog `etype` already distinguishes the two cases: `assembling-machine-3`, `foundry` and
`electromagnetic-plant` are `assembling-machine`; `electric-furnace` is `furnace`. A furnace takes no recipe
field; its product follows its input item.

`groups.lua:250` `append_inserters` emits one inserter per port, including fluid flows, and pushes each next
inserter another row away from the machine. The screenshot shows inserters standing alone in empty ground. No
pickup or drop cell is constructed.

`groups.lua:693-698` strips `covered_members` from a speed beacon that reaches a quality machine. The beacon
still stands there. That fixes the bookkeeping and not the factory, and `validate.lua:635-638` then rejects
the candidate on real geometry.

PRESERVE: `logic/bp/validate.lua`, `logic/bp/plan.lua`, `logic/bp/route.lua`, `logic/bp/pack.lua`,
`logic/bp/search.lua`, `logic/bp/geometry.lua`, `tests/harness.lua`,
`tests/test_blueprint_physical_contract.lua`, `docs/feature-contracts.md`, `tools/**`, `info.json`,
`mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `tests/test_groups.lua`,
`tests/test_serialize.lua`, `tests/test_beacon_coverage.lua`, `tests/test_beacons.lua`.

## What to build

**Identity travels.** Every machine member and every serialized machine carries its step's prototype, quality,
recipe and recipe quality, and its exact module multiset and inventory placement, through grouping, all four
rotations and serialization. `recipe` is written ONLY where catalog `etype` is `assembling-machine`. A furnace
receives none.

**Trap.** Key the rule on `etype`, never on entity name. A modded assembler is not called
`assembling-machine-3`, and a modded furnace is not called `electric-furnace`.

**Chains, both directions.** Every required input transfer gets an inserter whose pickup cell touches a real
source structure and whose drop cell touches the target machine. Every required output transfer gets an
inserter whose pickup cell touches the machine and whose drop cell touches an output structure. A step needing
two machines gives BOTH machines an input chain and an output chain.

**Fluid.** A fluid connection emits a pipe reaching a real oriented fluid-box connection, and NEVER an item
inserter. Incompatible fluids never share a network.

**Split, never strip.** No quality machine is reached by a speed beacon after sharing, packing and rotation,
including from a neighbouring block. Split blocks until that holds. When no split succeeds, return a named
failure. Never strip `covered_members` while the beacon still stands.

**Extra beacons stay legal.** Influence above the configured count is accepted and recorded, never rejected
and never raised. Configured counts are unchanged: casting-iron 3, copper-plate 3, casting-steel 1,
copper-cable 1, electronic-circuit 1.

**Trap.** `tests/test_beacon_coverage.lua` `B1` and `B2` currently assert 1 physical beacon for a 1-beacon
requirement. That is correct and was re-derived in round 12. Do not widen them back.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-13-base -- logic/bp/groups.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/test_blueprint_physical_contract.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -qE '^FAIL [0-9.]+ SR1 ' || { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '\\[error\\]' && { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 900}
{"name": "recipe-rows", "command": "for L in lua5.2 lua5.4; do out=$($L tests/test_blueprint_physical_contract.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE \"^FAIL [0-9.]+ SR1 \" && { echo \"$L still red: SR1\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE \"^FAIL [0-9.]+ SR2 \" && { echo \"$L broke SR2: a furnace gained a recipe field\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE \"^FAIL [0-9.]+ SR3 \" && { echo \"$L broke SR3\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE \"^FAIL [0-9.]+ PC1 \" && { echo \"$L broke the positive control\"; exit 1; }; done; echo recipe-rows-closed", "expect_exit": 0, "expect_regex": "recipe-rows-closed", "timeout_s": 1800}
{"name": "etype-keyed", "command": "grep -qE 'etype' logic/bp/groups.lua || { echo 'the recipe rule is not keyed on catalog etype'; exit 1; }; grep -qE '\"electric-furnace\"' logic/bp/groups.lua && { echo 'the rule is keyed on an entity name'; exit 1; }; echo etype-keyed", "expect_exit": 0, "expect_regex": "etype-keyed", "timeout_s": 60}
{"name": "counts-unreduced", "command": "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.tools.test_incident_capture 2>&1 | tail -3 | grep -qE 'OK' || { echo 'the captured beacon counts changed'; exit 1; }; echo counts-unreduced", "expect_exit": 0, "expect_regex": "counts-unreduced", "timeout_s": 600}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 110_producer", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-13-base --manifest docs/tasks/110.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

# bound: 3600s
