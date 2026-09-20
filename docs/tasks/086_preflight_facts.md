# 086 — Preflight asks the shared quality rule and refuses thin facts

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-086`, branch `lane/086`, base tag `round-9-base` (resolve with `git rev-parse round-9-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/preflight.lua` and new `tests/test_preflight_quality_facts.lua`.
- `logic/bp/quality_policy.lua` is a frozen contract and already works. Call it; never copy its arithmetic.
- `logic/catalog.lua`, `logic/bp/generation.lua` and `logic/bp/plan.lua` are frozen. Other lanes own them.
- `tests/test_bp_preflight.lua` is frozen: its inputs were migrated in the spine and every assertion in it must keep passing.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- Never add a "skip if the dependency is missing" branch to any test.

**Declared dependency, do not try to satisfy it here:** `tests/test_blueprint_pipeline.lua:237-273` drives a real
calculation through `Generation.start` and demands success. On this base the catalog carries no recipe facts and
no receiver facts, so a correct missing-facts rule makes that case fail. Lane 085 is its producer. Your verifier
is `sh tools/verify_round9_lane.sh "$PWD" 086_preflight_facts`, which runs your own checks, and the whole suite
runs again at slice integration. Never write a stub producer, a skip branch or a permissive fallback to make the
whole suite green here.

**Write the test file first, before changing the module.**

Two defects, both measured on this base:

- `logic/bp/preflight.lua:380` asks `effect_of(catalog, module, "quality") ~= 0`. A speed module's quality effect is `-0.25`, so the player's ordinary sheet is refused as `BP_REJ_QUALITY_CHANGING`.
- `logic/bp/preflight.lua:220` returns silently when a column has no recipe, and `preflight.lua:209-211` turns an absent product list into `{}`. So an empty or missing recipe passes every product check.

## What to build

1. `entity_reasons` asks `QualityPolicy.effective_quality`, `QualityPolicy.has_active_quality_module` and `QualityPolicy.speed_beacon_contribution` instead of its own tests. `BP_REJ_QUALITY_CHANGING` when the value is `> 0`. `BP_REJ_BEACON_SPEED_ON_QUALITY` when a positive quality module is present **and** the beacon speed contribution is `> 0`.
2. `supported = false` from the policy becomes `BP_REJ_PROTOTYPE_FACTS_MISSING` when the receiver status is `missing`, and `BP_REJ_UNSUPPORTED_INTERFACE` when it is `unsupported`. Both name the machine and the reason.
3. `product_reasons` applies the structural completeness rule of `docs/feature-contracts.md` §22.3 for **active** columns: an absent recipe, a recipe that is not a table, an absent product list, an empty product list on a producing column, or a product with no name, type or amount is `BP_REJ_PROTOTYPE_FACTS_MISSING`, naming the recipe and the fields. An explicitly empty ingredient list stays valid. An absent optional field such as `probability` stays valid.
4. Inactive columns keep their current treatment (`preflight.lua:149-154`).

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-9-base -- logic/bp/preflight.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/test_preflight_quality_facts.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL 2\\.0 PQ1 .* \\[assert\\]' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_preflight_quality_facts.lua && lua5.4 tests/test_preflight_quality_facts.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "existing-preflight-cases-hold", "command": "lua5.2 tests/test_bp_preflight.lua && lua5.4 tests/test_bp_preflight.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "suite", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 086_preflight_facts", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-9-base --manifest docs/tasks/086.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Your own tests must include, by these exact case names. Build each missing-facts case by **removing one required
field from an otherwise complete prepared input**, and state the fixture's provenance in a comment:

- `PQ1` a machine holding four `-0.25` speed modules is not rejected.
- `PQ2` the same machine with speed beacons beside it is not rejected.
- `PQ3` a `+0.25` quality module is still `BP_REJ_QUALITY_CHANGING`.
- `PQ4` a positive quality module plus a speed beacon is still `BP_REJ_BEACON_SPEED_ON_QUALITY`.
- `PQ5` an active column with `recipe = {}` is `BP_REJ_PROTOTYPE_FACTS_MISSING`.
- `PQ6` an active column whose products were removed is `BP_REJ_PROTOTYPE_FACTS_MISSING`.
- `PQ7` an explicitly empty ingredient list is accepted.
- `PQ8` an inactive column with the same thin recipe is ignored.
- `PQ9` a machine whose receiver status is `missing` is `BP_REJ_PROTOTYPE_FACTS_MISSING`, with no modules installed.
- `PQ10` a verified receiver whose `base_effect.quality` is positive is `BP_REJ_QUALITY_CHANGING`, with no modules installed.
- `PQ11` a probabilistic product is still `BP_REJ_PROBABILISTIC` when the facts are complete.

## Files this lane owns

`logic/bp/preflight.lua`, `tests/test_preflight_quality_facts.lua`

# bound: 2400s
