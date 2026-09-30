# 294_material_cost: Material cost: raw resources per entity from game recipes, catalog.material, fixtures, material_score.py

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-294`, branch `lane/294`,
base tag `round-53-base` (`9719cddfd95a00be2a432f1c01e9127d869d77e0`), merge target `int/r53`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, `tests/test_drawn_e2e.lua`, or
any full suite, whole sheet or headless run of any kind. No command may take more than 60 s.** Run only single test
files, one at a time, with `timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4) or
`timeout 90 python3 tests/<file>.py`; headless test files only offline: `timeout 90 lua5.2 tests/game/offline.lua
tests/game/<file>.lua`. Never use `coroutine` or `math.random`. `require` only at file top level. **No game item or
entity name in `logic/`.** Deterministic: fixed scan order, ties broken by id string. Every new test must FAIL on the
base code where this task says "red on base" (say so in its header comment, with date 2026-09-30); commit it red
first, then the code.

Read `CONTEXT.md` first: terms **Block**, **Flow graph**, **Source**, **Output**, **Layer**, **Turn**, **Flip**,
**Crossing**, **Port side**, **Material cost**, **Drawn pack**, **Layered pack**, **Fallback**.

## Explain very simply

Player ruling 2026-09-30 (round 53 grill Q2-Q4): layouts are judged valid -> fast -> frugal, and frugal is now
**Material cost**: the raw resources inside what a blueprint needs, from the game's own recipes. Follow each recipe
down to items that have no recipe (ores, stone, coal, crude oil, water...) and add every unit, fluids included, one
each. No item names in code. The drawing (another module) reads `catalog.material` to weigh belts vs undergrounds;
verdict tools read a fixture to score delivered blueprints.

Facts (read 2026-09-30):
- `logic/catalog.lua` is the only module (with `logic/bp/plan.lua`) that touches `prototypes` (header `:4-5`).
  `Catalog.build` (`:938-1013`) holds recipes only for the sheet (`options.recipes`), families `catalog.belt =
  {belt, underground, splitter, ...}` and `catalog.pipe = {pipe, underground, ...}` (`:714-778`).
- Golden offline catalogs lack underground-belt, splitter, pipe, pipe-to-ground recipes (all cases) -> offline needs a
  fixture.
- `logic/indexer.lua:13-36` builds a product -> recipes map at runtime; item placing an entity: prototype
  `items_to_place_this` (see `gui/pipette.lua:62-67`).
- Recipe amounts: vanilla transport belt recipe makes 2 belts from 1 plate + 1 gear; underground belt makes 2 from
  10 plates + 5 belts (so one underground = 5 + 2.5 x 1.5 ... compute, do not hardcode).

## What to build

1. **`logic/bp/material_cost.lua` (new, pure, no `prototypes`/`game`)**:
   - `MaterialCost.compute(graph, names) -> {[entity_name] = cost}` where `graph = {place = {[entity] = item},
     recipe_of = {[item] = recipe_name|nil}, recipes = {[name] = {ingredients = {{name, amount}}, products =
     {{name, amount}}}}}`. cost(entity) = cost(item placing it) for ONE item. cost(item) = sum(ingredient amount x
     cost(ingredient)) / amount of that item among the recipe products; item with no recipe (or `recipe_of` nil) = 1
     per unit (fluids alike). Memoized; a cycle (item met again while being costed) = that item counts as leaf 1.
     Iterative (explicit stack), no recursion deeper than Lua's C stack; bounded by a visit counter.
   - `MaterialCost.parse_fixture(text) -> {[entity_name] = cost}`; fixture lines `MATERIAL <entity> <cost>` (cost
     printed `%.4f`), `#` comments.
   - `MaterialCost.of_entity(catalog, name)` -> `catalog.material and catalog.material[name]`.
2. **Catalog hook (`logic/catalog.lua`)**: after families are built, `Catalog.fill_material(catalog)` builds the graph
   from prototypes for entity names: `catalog.belt.{belt, underground, splitter}`, `catalog.pipe.{pipe, underground}`,
   every crafting machine / beacon / inserter / pole name present in `catalog.entity`, `catalog.inserter`,
   `catalog.pole`. Placing item = first of `items_to_place_this`. Recipe pick per item: a recipe named exactly like
   the item that produces it, else the lowest-name producing recipe; skip hidden recipes and recipes whose category
   name contains `recycling`. Walk ingredients transitively (breadth-first, fixed order). Result
   `catalog.material = MaterialCost.compute(...)`. Guard every prototype read (2.0 userdata: `pcall` where a field may
   be missing). Must not change any other catalog field.
3. **Offline inject (`tests/golden/generate.lua`)**: when the prepared catalog has no `material`, load
   `tests/fixtures/material_cost_2.1.txt` (fallback 2.0) through `parse_fixture` into `catalog.material`. Layered
   pack never reads it (bytes unchanged).
4. **Fixtures** `tests/fixtures/material_cost_2.0.txt`, `material_cost_2.1.txt`: seed both from factorio-draftsman
   vanilla data (`~/.venvs/draftsman/bin/python`, `draftsman.data.recipes.raw`, `draftsman.data.items.raw
   [..]['place_result']`) for the names in the list above for vanilla + space-age entities, with a header line
   `# seed: draftsman 2.1.17 data, replaced by headless probe at merge`. Same rule as the Lua code (write the seed
   script as `tools/material_seed.py`). Add rows to `tests/fixtures/INDEX.tsv`.
5. **Headless probe** `tests/game/test_material_cost.lua` registered in `tests/game/index.lua`: builds a catalog in
   the running game, prints every `MATERIAL <entity> <cost>` line (sorted), asserts transport belt < underground belt
   < splitter cost ordering is sane (each > 0). Check it ONLY offline: `lua5.2 tests/game/offline.lua
   tests/game/test_material_cost.lua` (the integrator runs it in the game).
6. **`tools/material_score.py <bp.txt|r.json> <fixture>`**: loads entities through `tools/blueprint_audit.py`
   `load_entities`, `Counter` of names, prints `material=<sum %.1f> unknown=<n> unknown_names=<a,b|->`.

## Tests (print code when each passes)

`tests/test_material_cost.lua`:
- MC1 hand graph: plate leaf, gear = 2 plates, belt recipe 1 plate + 1 gear -> 2 belts => belt 1.5; underground recipe
  10 plates + 5 belts -> 2 => 8.75 per underground (17.5 per pair).
- MC2 fluid ingredient counts 1 per unit.
- MC3 cycle (A needs B, B needs A) terminates; costs finite.
- MC4 multi-product recipe divides by wanted product amount only.
- MC5 both fixtures parse; every name in them has cost > 0; 2.0 and 2.1 agree on transport belt.
- MC6 `Catalog.fill_material` with the `prototypes` mock of `tests/harness.lua` (pattern: `tests/test_box_binding.lua`)
  fills `catalog.material` for the belt family (red on base).
`tests/test_material_score.py` (python3, unittest; print `MS1` on pass): 3 belts + 1 underground pair from a tiny
blueprint JSON with a tiny fixture -> exact sum; unknown name counted.

## Files this lane owns

`logic/bp/material_cost.lua`, `logic/catalog.lua`, `tests/golden/generate.lua`, `tools/material_score.py`, `tools/material_seed.py`, `tests/test_material_cost.lua`, `tests/test_material_score.py`, `tests/game/test_material_cost.lua`, `tests/game/index.lua`, `tests/fixtures/material_cost_2.0.txt`, `tests/fixtures/material_cost_2.1.txt`, `tests/fixtures/INDEX.tsv`, `docs/tasks/294_material_cost.md`. Nothing under `logic/bp/` except the new module.

## Commit, THEN check

Commit on `lane/294`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane294-tests", "command": "git diff --name-only round-53-base HEAD | grep -Ev '^(logic/bp/material_cost\\.lua|logic/catalog\\.lua|tests/golden/generate\\.lua|tools/material_score\\.py|tools/material_seed\\.py|tests/test_material_cost\\.lua|tests/test_material_score\\.py|tests/game/test_material_cost\\.lua|tests/game/index\\.lua|tests/fixtures/material_cost_2\\.0\\.txt|tests/fixtures/material_cost_2\\.1\\.txt|tests/fixtures/INDEX\\.tsv|docs/tasks/294_material_cost\\.md)$' | ( ! grep . ) && for t in test_material_cost test_catalog test_catalog_recipe_facts test_catalog_inserter_speed test_box_binding test_fixture_facts test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane294-tests-ok", "expect_exit": 0, "expect_regex": "lane294-tests-ok", "timeout_s": 3000}
{"name": "lane294-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_material_cost.lua; timeout 60 python3 tests/test_material_score.py) 2>&1); for c in MC1 MC2 MC3 MC4 MC5 MC6 MS1; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|FAIL |[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane294-ok", "expect_exit": 0, "expect_regex": "lane294-ok", "timeout_s": 300}
```

# bound: 5400s
