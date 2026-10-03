# 305_material_rows: whole-blueprint Material in Lua, TRIAL row lines, "trial" stage on progress bar

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-305`, branch `lane/305`,
base tag `round-55-base` (the commit that holds this task file), merge target `int/r55`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until every test below passes. Commit early, commit again, run the checks LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/game_test.sh`, `tools/turn_flip_census.sh`,
`tools/ckpt.lua`, `factorio`, `tests/test_drawn_e2e.lua`, `tests/golden/generate.lua` on a whole sheet,
`lua5.2 tools/golden_profile.lua <case>` (any real case), or any full suite, census, whole golden sheet or headless
run of any kind.** Single test files only: `timeout 100 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4).
`tests/test_golden_profile.lua` is allowed (5 s). Never use `coroutine` or `math.random`. `require` only at file top
level. **No game item or entity name in `logic/`** (tests may use names). Deterministic. Every new test must FAIL on
the base code (say so in its header comment, date 2026-10-03); commit it red first, then the code.

Read `CONTEXT.md` first: **Material cost**, **Material tie**, **Footprint**, **Turn trial**, **Trial fail**.

## Why (explain very simply)

A later step tries other Turns for each Block and keeps a try only if the whole blueprint costs less Material.
Today Lua cannot say what a whole blueprint costs: only the offline Python tool `tools/material_score.py` sums it
(name count x fixture price). Lua knows the price of one entity (`catalog.material[name]`, filled by
`Catalog.fill_material`, `logic/catalog.lua:1105`; empty `{}` when no prototypes). Also the offline golden runner
always loads the 2.1 price fixture, even for a 2.0 sheet (`tests/golden/generate.lua:489-491`). And the progress bar
has no "trial" stage, and nothing prints the try results.

## PRESERVE

- `MaterialCost.compute`, `parse_fixture`, `of_entity` and MC1-MC8 unchanged.
- `tools/golden_profile.lua`: its 4 patch anchors and every existing line of output unchanged; only the TRIAL
  lines are added.
- Progress bar never moves back; existing PV cases keep passing.

## What to build (frozen seams — other code relies on exactly these)

1. `logic/bp/material_cost.lua`:
   - `MaterialCost.blueprint(catalog, entities) -> total, unknown_count`: sum of `catalog.material[e.name]` over
     `entities` (list of tables with `name`, optional `flow_id`); names without a price count in `unknown_count` and
     add 0. `catalog.material` nil or empty (`next(...) == nil`) -> returns `nil, #entities`.
   - `MaterialCost.by_flow(catalog, entities) -> {[flow_id] = total}`: same sum per `flow_id`; entities without
     `flow_id` are left out. Empty material -> `nil`.
2. `tests/golden/generate.lua`: pick `tests/fixtures/material_cost_<version>.txt` by the sheet's Factorio version
   (the prepared input's version field, same one the run already uses for its catalog); fall back to the other file
   only if that one is missing. Change only the fixture-choosing lines (~487-493).
3. `tools/turn_trial_rows.lua` (new module + CLI):
   - `TurnTrialRows.format(case_id, trial) -> {lines}`, pure. `trial` = `{ticks_before=, ticks=, tried=, won=,
     fails=, rows = {{block=, rule="d/m", pose="d/m", result="won|lost|fail|forbidden|pin", code=, material=,
     area=}}}`. One line per row, exactly:
     `TRIAL case=<id> block=<block> rule=<rule> pose=<pose> result=<result> code=<code or -> material=<%.1f or -> area=<n or ->`
     then one summary line `TRIALSUM case=<id> tried=<n> won=<n> fails=<n> ticks_before=<n> ticks=<n>`.
     `trial` nil -> `{}`.
   - CLI: `lua5.2 tools/turn_trial_rows.lua <r.json>...` reads each file's `result.search.trial` (case id = file
     basename before `.r.json`), prints the lines. Use the repo's existing JSON module.
4. `tools/golden_profile.lua`: at the end, if the result has `search.trial`, print `TurnTrialRows.format` lines.
   Change nothing else in that file (its 4 patched `search.lua` lines stay as they are).
5. `logic/progress_view.lua`: `"trial"` after `"validate"` in `BLUEPRINT_ORDER`, weight `trial = 20`; bar stays
   forward-only. `locale/{en,cs,ro}/locale.cfg`: `progress_stage_trial=` (en "Trying other turns", cs "Zkouším jiná
   otočení", ro "Încerc alte rotiri"), next to `progress_stage_validate`. No locale key for any `BP_` code
   (`tests/test_locale_keys.lua` L3 forbids keys for internal codes).

## Tests

- `tests/test_material_cost.lua` (append, print marker on pass):
  - MC-BP1: prices from `tests/fixtures/material_cost_2.0.txt` (via `parse_fixture`). Entity list built from these
    frozen counts (blueprint `tests/fixtures/edge_input_magenta_drawn.bp.txt`, counted by integrator 2026-10-03):
    `assembling-machine-3=17 beacon=68 bulk-inserter=101 chemical-plant=5 electric-furnace=8 electromagnetic-plant=14
    foundry=13 long-handed-inserter=26 medium-electric-pole=31 oil-refinery=1 pipe=116 pipe-to-ground=112 roboport=9
    turbo-splitter=12 turbo-transport-belt=1303 turbo-underground-belt=86` -> total within 0.1 of `521885.2`
    (= `tools/material_score.py` on that file), unknown 0. Second list (`dead_pair_inserter10s.bp.txt`):
    `assembling-machine-3=4 beacon=7 electromagnetic-plant=1 fast-inserter=33 fast-splitter=2
    fast-transport-belt=234 fast-underground-belt=10 foundry=6 long-handed-inserter=4 medium-electric-pole=21 pipe=12
    pipe-to-ground=12 roboport=4` -> within 0.1 of `59323.7`.
  - MC-BP2: unknown name -> counted in `unknown_count`, adds 0.
  - MC-BP3: sum of `by_flow` values + priced entities without `flow_id` == `blueprint` total.
  - MC-BP4: `catalog.material = {}` and `nil` -> `blueprint` returns `nil, #entities`; `by_flow` returns `nil`.
  - MC-BP5: generate.lua fixture choice: extract the choosing logic into a small local function you can test by
    reading the source or by `package.loaded` stub; a 2.0 prepared input picks `material_cost_2.0.txt`.
- `tests/test_turn_trial_rows.lua` (new): TR1 exact line text for one won row, one fail row (code), one pin row
  (material/area `-`), plus TRIALSUM; TR2 `trial` nil -> empty list; TR3 CLI on a tiny r.json the test writes to
  `os.tmpname()` prints the same lines.
- `tests/test_progress_view.lua` (append): PV-TRIAL a blueprint job whose `progress.stage = "trial"` after
  `"validate"` shows a fraction >= the validate one and stage key `trial`.
- `tests/test_locale_keys.lua` stays green.

## Files this lane owns

`logic/bp/material_cost.lua`, `tests/golden/generate.lua`, `tools/turn_trial_rows.lua`, `tools/golden_profile.lua`,
`logic/progress_view.lua`, `locale/en/locale.cfg`, `locale/cs/locale.cfg`, `locale/ro/locale.cfg`,
`tests/test_material_cost.lua`, `tests/test_turn_trial_rows.lua`, `tests/test_progress_view.lua`.

## Commit, THEN check

Commit on `lane/305`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane305-tests", "command": "git diff --name-only round-55-base HEAD | grep -Ev '^(logic/bp/material_cost\\.lua|tests/golden/generate\\.lua|tools/turn_trial_rows\\.lua|tools/golden_profile\\.lua|logic/progress_view\\.lua|locale/(en|cs|ro)/locale\\.cfg|tests/test_material_cost\\.lua|tests/test_turn_trial_rows\\.lua|tests/test_progress_view\\.lua)$' | ( ! grep . ) && run() { o=$(timeout 100 lua5.2 tests/$1.lua 2>&1); l=$(echo \"$o\" | tail -1); n=$(echo \"$l\" | sed -n 's/.*: \\([0-9][0-9]*\\) cases.*/\\1/p'); echo \"$l\" | grep -q ' 0 failed' || { echo FAIL $1; return 1; }; [ -n \"$n\" ] && [ \"$n\" -ge $2 ] || { echo COUNT $1 got=$n floor=$2; return 1; }; return 0; }; out=$(timeout 100 lua5.2 tests/test_material_cost.lua 2>&1) || { echo FAIL test_material_cost; exit 1; }; for m in MC1 MC5 MC6 MC7 MC8 MC-BP1 MC-BP2 MC-BP3 MC-BP4 MC-BP5; do echo \"$out\" | grep -q \"$m\" || { echo NOMARK $m; exit 1; }; done; timeout 100 lua5.2 tests/test_golden_profile.lua 2>&1 | tail -1 | grep -q \" 0 failed\" || { echo FAIL test_golden_profile; exit 1; }; for p in test_turn_trial_rows:3 test_progress_view:9 test_no_item_names:1 test_no_runtime_require:3 test_locale_keys:3; do run ${p%%:*} ${p#*:} || exit 1; done && echo lane305-tests-ok", "expect_exit": 0, "expect_regex": "lane305-tests-ok", "timeout_s": 2400}
```
