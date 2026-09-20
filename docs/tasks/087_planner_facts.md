# 087 — The planner asks the same quality rule, and never trusts a thin projection

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-087`, branch `lane/087`, base tag `round-9-base` (resolve with `git rev-parse round-9-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/plan.lua` and new `tests/test_plan_quality_facts.lua`.
- `logic/bp/quality_policy.lua` is a frozen contract and already works. Call it; never copy its arithmetic.
- `logic/catalog.lua`, `logic/bp/generation.lua` and `logic/bp/preflight.lua` are frozen. Other lanes own them.
- `tests/test_bp_plan.lua` is frozen: its inputs were migrated in the spine and every assertion in it must keep passing.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- Never add a "skip if the dependency is missing" branch to any test.

**Declared dependency, do not try to satisfy it here:** `tests/test_blueprint_pipeline.lua:237-273` demands a
successful generation that today succeeds only while facts are absent. Lane 085 is its producer, lane 086 its
sibling. Your verifier is `sh tools/verify_round9_lane.sh "$PWD" 087_planner_facts`. The whole suite runs at
slice integration. Never write a stub producer or a skip branch.

**Write the test file first, before changing the module.**

Two defects, both measured on this base:

- `logic/bp/plan.lua:303-309` marks a quality module active from its positive effect alone, with no receiver decision. A probe on this base supplies a machine with `uses_module_effects=false` and a positive quality module, and the planner still reports `has_quality_module=true`, `forbids_speed_beacon=true`.
- `logic/bp/plan.lua:182-188` returns a catalog recipe before consulting `prototypes.recipe`, so an incomplete projection shadows a complete runtime object.

## What to build

1. `has_quality_module` and `forbids_speed_beacon` come from `QualityPolicy.has_active_quality_module` and `QualityPolicy.speed_beacon_contribution`.
2. `recipe_data` applies the shadowing rule of `docs/feature-contracts.md` §22.3: a projected recipe is used only when it is structurally complete for the fields this reader needs — `energy`, `ingredients`, `products` — and declares nothing missing; otherwise it falls back to the runtime prototype and records the gap on the step.
3. The step the planner publishes carries the receiver status it used, so a later stage never has to guess again.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-9-base -- logic/bp/plan.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/test_plan_quality_facts.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL 2\\.0 PL1 .* \\[assert\\]' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_plan_quality_facts.lua && lua5.4 tests/test_plan_quality_facts.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "existing-plan-cases-hold", "command": "lua5.2 tests/test_bp_plan.lua && lua5.4 tests/test_bp_plan.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "suite", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 087_planner_facts", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-9-base --manifest docs/tasks/087.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Your own tests must include, by these exact case names. Compare the planner against `QualityPolicy`, never
against `Preflight`, which on this base still holds the old rule:

- `PL1` a machine whose receiver ignores modules reports no active quality module, whatever the module's effect.
- `PL2` a `-0.25` speed module never makes `forbids_speed_beacon` true.
- `PL3` a `+0.25` quality module still makes it true.
- `PL4` a positive quality module cancelled to zero still makes it true.
- `PL5` a beacon of productivity modules is no speed beacon.
- `PL6` an incomplete catalog recipe never shadows a complete runtime recipe.
- `PL7` a complete catalog recipe is used, and the runtime prototype is not consulted.
- `PL8` the published step carries the receiver status the planner used.

## Files this lane owns

`logic/bp/plan.lua`, `tests/test_plan_quality_facts.lua`

# bound: 2400s
