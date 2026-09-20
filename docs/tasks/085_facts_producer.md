# 085 — The catalog carries the recipe and receiver facts the checkers read

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-085`, branch `lane/085`, base tag `round-9-base` (resolve with `git rev-parse round-9-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/generation.lua`, `logic/catalog.lua`, and new `tests/test_catalog_recipe_facts.lua` and `tests/test_generation_recipe_facts.lua`.
- `logic/bp/preflight.lua` and `logic/bp/plan.lua` are frozen. Two other lanes own them. Your change adds facts and changes no verdict.
- `logic/bp/quality_policy.lua` and `docs/feature-contracts.md` §22 are frozen contracts. Read §22 first.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- Never add a "skip if the dependency is missing" branch to any test.

**Write both test files first, before changing either module.**

Measured on this base, host `legalcopilot-dev`, 2026-09-20: a real generation run reaches `Preflight.check` with
no recipe facts and no receiver facts at all.

```text
RUNTIME BOUNDARY: catalog.recipe=nil; reasons=0
OBSERVE 2.0 recipe=gear recipe_facts=false receiver_facts=false
```

The chain is short and every link is in this lane:

- `logic/bp/generation.lua:219-232` — `references_for` collects entities, items, fluids, modules and qualities. No recipes.
- `logic/bp/generation.lua:278-299` — `catalog_options` forwards exactly those five sets.
- `logic/catalog.lua:534-541` — `catalog_template` has no recipe key, and nothing in `Catalog.build` adds one.
- `logic/catalog.lua:255-280` — `project_entity` never projects `effect_receiver`.

So `logic/bp/preflight.lua:220` returns with no recipe and the probabilistic, random-amount and spoilage checks
never run, and `logic/bp/quality_policy.lua` sees every machine as `missing`.

## What to build

1. `references_for` collects the active recipe names, and `catalog_options` forwards them as `recipes`.
2. `Catalog.build` projects `catalog.recipe[name]` and `catalog.recipe_coverage` exactly as `docs/feature-contracts.md` §22.3 states, including `energy`, `category`, ingredient and product fields for both branch shapes, and `facts.missing` per recipe.
3. Item projection carries spoilage: `spoil_result` from the prototype, and the ingredient-side `spoils` flag the contract names. The tick count is the method `get_spoil_ticks(quality)`, never an attribute.
4. `project_entity` projects `effect_receiver` per §22.2: `status`, `source`, `branch`, `base_effect`, the three `uses_*` flags, and on 2.1 also `uses_local_effects` and `quality_limits`.
5. `status` follows the branch table in §22.2. A 2.0 machine is **never** `unsupported` merely because the branch has no `quality_limits`. A prototype that was read is `verified_default` or `verified_supported`; a record nobody captured stays `missing`; behaviour outside the model is `unsupported` with a reason.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-9-base -- logic/catalog.lua logic/bp/generation.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/test_catalog_recipe_facts.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL 2\\.0 FP1 .* \\[assert\\]' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_catalog_recipe_facts.lua && lua5.4 tests/test_catalog_recipe_facts.lua && lua5.2 tests/test_generation_recipe_facts.lua && lua5.4 tests/test_generation_recipe_facts.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "boundary-carries-facts", "command": "lua5.2 tests/test_generation_recipe_facts.lua 2>&1 | grep -E 'cases,'", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "suite", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 085_facts_producer", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-9-base --manifest docs/tasks/085.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Your own tests must include, by these exact case names:

- `FP1` the catalog projects every active recipe with its energy, ingredients and products.
- `FP2` a product's `probability` survives on 2.0 and `independent_probability` on 2.1.
- `FP3` `facts.missing` names a field the prototype could not supply, and is empty when nothing is missing.
- `FP4` `recipe_coverage.state` is `partial` when an active recipe is absent, `complete` only when every active name is present.
- `FP5` a machine's receiver record carries a status, a source and its branch.
- `FP6` a 2.0 machine is never `unsupported` for lacking `quality_limits`.
- `FP7` a receiver nobody captured is `missing`, never `verified_default`.
- `FP8` a spoiling item projects `spoil_result`.
- `GF1` a real `Generation.start` run reaches `Preflight.check` with the active recipes and every machine's receiver status.
- `GF2` a prepared input replays with `prototypes` set to nil.

## Files this lane owns

`logic/bp/generation.lua`, `logic/catalog.lua`, `tests/test_catalog_recipe_facts.lua`, `tests/test_generation_recipe_facts.lua`

# bound: 2400s
