# 290_box_binding: learn from the engine which fluid box each recipe fluid uses

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-290`, branch `lane/290`,
base tag `round-52-base` (`f13b7496e3df8592499363ee4c50bf28df08c0d2`), merge target `int/r52`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet
or headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4) or `timeout 90 python3 -m unittest tests/<file>.py`;
headless test files only offline: `timeout 90 lua5.2 tests/game/offline.lua tests/game/<file>.lua`. Never use
`coroutine` or `math.random`. `require` only at file top level. **No game item or entity name in `logic/`.** Every
new test must FAIL on the base code where this task says "red on base" (say so in its header comment, with date
2026-09-30); commit it red first, then the code.

## Explain very simply

Read `CONTEXT.md` term **Box binding**. Player ruling 2026-09-30: fix this validity hole this round.

A crafting machine has several fluid boxes. The engine decides which box each fluid of the recipe uses. Measured
headless 2026-09-30 on 2.0.77 AND 2.1.20 (`tests/fixtures/flip_filters_2.0.txt`, `_2.1.txt`, made by
`tests/game/test_flip_fluidboxes.lua:80-125`):
- recipe filling every box of a role: fluid k -> box k.
- fewer fluids, machine-specific: foundry `casting-iron` molten-iron box 1 `conns=2` (spare connection merged);
  oil-refinery `basic-oil-processing`: crude at runtime box 1 whose connection is (1,2) = prototype box 2's spot;
  cryogenic-plant `fluoroketone`: fluorine box 1 conns=2, ammonia box 2 conns=1.
- fixture `box=` is the RUNTIME fluidbox index, not the prototype index. Map runtime -> prototype by matching the
  row's `pos` with `tests/fixtures/flip_fluidboxes_2.0.txt` `CONN <m> dir=0 ... mirror=false ... box=<proto>` rows,
  or at runtime by `LuaFluidBox.get_prototype(i)` (2.0) / `LuaEntity.get_fluid_box_prototype(i)` (2.1).
No code knows this today: validate (`validate.lua:2102-2191`) pins a box only when the recipe fills all boxes of a
role, inputs only; groups (`groups.lua:112-166`) guesses by ordinal / first box (refinery crude -> (-1,2), wrong).
Those two call sites are NOT yours: the integrator wires them to your `BoxBinding.box_for` after merge.

Engine API (`docs/api/2.0.77.members.json`, `docs/api/2.1.19.members.json`): 2.0 `entity.fluidbox` ->
`get_filter(i)`, `get_prototype(i)`, `get_pipe_connections(i)`; 2.1 has no `LuaFluidBox`: `entity.get_fluid_filter(i)`,
`entity.get_fluid_box_prototype(i)`, `entity.get_fluid_box_pipe_connections(i)`. No prototype-only route: the
binding exists only on a created entity with its recipe (create with `recipe=` in the spec: a machine created
without a recipe ignores direction, round 51 trap).

## What to build

1. `logic/bp/box_binding.lua` (frozen signatures in the file; replace bodies; no item names):
   - `BoxBinding.probe(surface, machine_proto, recipe_proto)`: create the machine at a free spot with `recipe=`,
     for i = 1..#fluidbox read filter + prototype index (2.0 / 2.1 API above, each through `pcall`), destroy the
     entity; return `{[fluid_name] = {box = <prototype index>, role = "input"|"output"}}` (role from the prototype
     box `production_type`). A fluid read on two boxes keeps the lowest prototype index.
   - `BoxBinding.fill(catalog, steps, surface_provider)`: for each plan step whose machine has fluid boxes and
     whose recipe has a fluid ingredient or product, once per (machine, recipe): probe and store
     `catalog.recipe[recipe].fluid_boxes[machine] = <probe result>`. `surface_provider()` returns a surface or nil
     (offline nil -> nothing stored). Game side: one scratch surface created by name on first use and deleted
     after the fill (`game.delete_surface`); guard every engine call with `pcall`.
   - `BoxBinding.box_for(catalog, machine_name, recipe_name, fluid_name, role)`: stored `box` or nil.
   - `BoxBinding.parse_fixture(text)` -> same table shape per (machine, recipe), for tests and twins.
2. `logic/bp/generation.lua`: after the catalog is complete and the plan steps are known, call `BoxBinding.fill`
   once, budgeted like other generation work (1 op per probe; resumable if the generation phase model needs it).
   Surface provider: `game` present -> scratch surface; else nil. Offline runs must stay byte-identical (no game ->
   no binding -> call sites keep today's rule).
3. `logic/catalog.lua`: document the new `fluid_boxes` recipe field in the schema comment (16-20) and keep it when
   a catalog is copied/exported (grep how recipe fields are copied).
4. Fixture seed `tests/fixtures/box_binding_{2.0,2.1}.txt` (keep the 2 header lines): one line per bound fluid
   `BIND <machine> recipe=<r> fluid=<f> role=<input|output> box=<prototype index>` for every FILTER row with
   `mirror=false` and a fluid filter in `flip_filters_<v>.txt`, prototype index mapped as above.
5. `tests/game/test_box_binding.lua` (headless; for you offline shim only): for every crafting machine with fluid
   boxes x every recipe of its categories with a fluid, `BoxBinding.probe`, write `script-output/rrc_box_binding.txt`
   in the fixture format; assert surface count before == after. Model on `tests/game/test_flip_fluidboxes.lua`.
6. Tests `tests/test_box_binding.lua` (header: BB1-BB5 red on round-52-base):
   - BB1 parse both fixtures; 2.0 rows == 2.1 rows; oil-refinery basic-oil-processing crude-oil box == the
     prototype box whose dir 0 connection is (1,2).
   - BB2 `box_for` returns the stored box; nil when absent.
   - BB3 `probe` against a mock entity (2.0 shape: `fluidbox.get_filter`, `get_prototype`) -> expected table.
   - BB4 same with the 2.1 shape (`get_fluid_filter`, `get_fluid_box_prototype`).
   - BB5 `fill` with nil surface stores nothing; with a mock surface stores one entry per (machine, recipe), once.
   Print "BB1".."BB5" when each passes.
7. Keep green (one at a time): list in the first check below, plus offline `tests/game/test_box_binding.lua`.

## Files this lane owns

logic/bp/box_binding.lua, logic/catalog.lua, logic/bp/generation.lua, tests/test_box_binding.lua, tests/game/test_box_binding.lua, tests/fixtures/box_binding_2.0.txt, tests/fixtures/box_binding_2.1.txt, docs/tasks/290_box_binding.md. In `generation.lua` add only the fill call + its budget step.

## Commit, THEN check

Commit on `lane/290`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane290-tests", "command": "git diff --name-only round-52-base HEAD | grep -Ev '^(logic/bp/box_binding\\.lua|logic/catalog\\.lua|logic/bp/generation\\.lua|tests/test_box_binding\\.lua|tests/game/test_box_binding\\.lua|tests/fixtures/box_binding_2\\.0\\.txt|tests/fixtures/box_binding_2\\.1\\.txt|docs/tasks/290_box_binding\\.md)$' | ( ! grep . ) && for t in test_box_binding test_catalog test_catalog_recipe_facts test_generation_controls test_generation_interim test_generation_reload test_generation_recipe_facts test_flip_geometry test_fluid_box test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane290-tests-ok", "expect_exit": 0, "expect_regex": "lane290-tests-ok", "timeout_s": 3000}
{"name": "lane290-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_box_binding.lua; timeout 120 lua5.2 tests/game/offline.lua tests/game/test_box_binding.lua) 2>&1); for c in BB1 BB2 BB3 BB4 BB5; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane290-ok", "expect_exit": 0, "expect_regex": "lane290-ok", "timeout_s": 300}
```
