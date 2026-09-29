# 284_module_cache_rows: module facts read once per prototype, report rows spread over ticks

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-284`, branch `lane/284`,
base tag `round-50-base`, merge target `int/r50`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet or headless run of any
kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No
game item or entity name in `logic/`.** Every new test must FAIL on the base code where this task says "red on
base" (say so in its header comment); commit it red first.

## Explain very simply

Player save (legalcopilot-dev 2026-09-29, Factorio 2.0.77, 55 mods, 38 module prototypes): a sheet report of 23
rows took 91-112 ms in ONE tick. `ModuleGUI.new` = 106 ms of it:
- `ModuleSetup.allowed_module_names` (`logic/module_setup.lua` ~:100): 42 calls = 78 ms. For each of 38 modules
  `ModuleSetup.fits` re-reads engine prototype properties (`module.category`, `module.module_effects`,
  `entity.allowed_module_categories`, `entity.allowed_effects`, `recipe.allowed_module_categories`,
  `recipe.allowed_effects`, `module.hidden`, `module.parameter`). Each engine read builds a fresh table.
- `Utils.setup_effects` (`logic/utils.lua:48`): 135 calls = 20 ms (`get_module_effects(quality)` per module).
- `ReportSteps` (`logic/report_steps.lua`) takes 1 op per row of a 2000-op tick budget, so the whole report is
  built in one tick.

Prototype data never changes while the game runs (only between loads). Measured in engine with a patched copy
(`docs/tasks/r50_probes/fix_append.lua`, same save): report 91 -> 23.6 ms for 23 rows, ~1 ms per row.

## What to build

1. `logic/module_setup.lua`:
   - Module-local cache of prototype facts: per module name `{category, positive_effects = <array of effect
     names with value > 0>, offered = not hidden and not parameter}`; per entity name and per recipe name
     `{categories = allowed_module_categories, effects = allowed_effects}` (nil stays nil: "absent" has meaning,
     keep `allows(...)` semantics exactly). Store "absent" distinctly from "not cached yet".
   - Reset rule: the whole cache is dropped when the global `prototypes` object is not the one the cache was
     filled from (`cached_root ~= prototypes`). Also `ModuleSetup.forget_cache()` for tests.
   - `ModuleSetup.fits` and `ModuleSetup.allowed_module_names` use the cache; same answers as today for every input
     (`storage.module_names` stays read live every call; `is_offered` from cache).
   - Pattern: `docs/tasks/r50_probes/fix_append.lua` (`r50_fits`, `r50_module`, `r50_limits`); copy the logic,
     drop the `r50_` names.
2. `logic/utils.lua`: `Utils.setup_effects` reads module effects through a cache keyed by module name + quality
   (same reset rule; `Utils.forget_cache()`); totals identical to today (pattern: `r50_effects` in the probe).
   Beacon prototype reads stay as they are.
3. `logic/report_steps.lua`: `ReportSteps.ROW_OPS = 200`. Every consume that follows rendering one report row
   (solved column, skipped column, quality tier, assist, pool, unsolved product) takes `ROW_OPS` from
   `budget.ops` instead of 1 (budget may go below 0; the step loop stops). Other consumes stay 1. A call with
   `budget.ops > 0` still renders at least one row.
4. New `tests/test_module_cache.lua` (header: MC1 MC3 red on round-50-base):
   - MC1: harness world (pattern `tests/test_modules.lua`), >= 3 modules. Wrap each `prototypes.item[<module>]`
     and the machine / recipe prototypes in a counting proxy (`setmetatable({}, {__index = function(_, k) reads =
     reads + 1; return real[k] end})`). Call `allowed_module_names({machine}, recipe)` twice: second call makes 0
     prototype property reads.
   - MC2: answers equal to a reference copy of the base functions (paste base `fits` / `allows` /
     `allowed_module_names` into the test) for every module x {machine only, machine + beacon} x recipes with and
     without `allowed_effects` / `allowed_module_categories` (include a recipe whose `allowed_effects` is nil and
     an entity whose `allowed_effects` is nil).
   - MC3: `Utils.setup_effects` on a setup with 3 modules + 1 beacon group, called twice: second call makes 0
     `get_module_effects` calls; totals equal to base values computed in the test.
   - MC4: replacing the global `prototypes` table with a new one (module category changed) changes the answer
     (cache reset).
5. `tests/test_report_steps.lua`: add RW1 (red on base): a result with 30 renderable solved columns, one
   `ReportSteps.step(state, {ops = 2000})` renders exactly 10 rows. RW2: `{ops = 1}` renders exactly 1 row. Keep
   every existing test green (a test that relied on "all rows in one call" gets its budget raised, never its
   assertion loosened; say so in a comment).
6. Keep green (one at a time, `timeout 90`): `test_modules`, `test_report_steps`, `test_module_picker`,
   `test_calc_pipeline`, `test_utils`, `test_quality_loops`, `test_no_item_names`, `test_no_runtime_require`,
   `test_locale_keys` (skip a name that does not exist in `tests/`, and say which in the commit message).

## Files this lane owns

logic/module_setup.lua, logic/utils.lua, logic/report_steps.lua, tests/test_module_cache.lua,
tests/test_report_steps.lua, docs/tasks/284_module_cache_rows.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/284`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane284-tests", "command": "git diff --name-only round-50-base HEAD | grep -Ev '^(logic/module_setup\\.lua|logic/utils\\.lua|logic/report_steps\\.lua|tests/test_module_cache\\.lua|tests/test_report_steps\\.lua|docs/tasks/284_module_cache_rows\\.md)$' | ( ! grep . ) && for t in test_module_cache test_modules test_report_steps test_calc_pipeline test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane284-tests-ok", "expect_exit": 0, "expect_regex": "lane284-tests-ok", "timeout_s": 2400}
{"name": "lane284-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_module_cache.lua; timeout 120 lua5.2 tests/test_report_steps.lua) 2>&1); for c in MC1 MC2 MC3 MC4 RW1 RW2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -c ' 0 failed' | grep -q '^2$' && echo lane284-ok", "expect_exit": 0, "expect_regex": "lane284-ok", "timeout_s": 300}
```

# bound: 3600s
