# 307_trial_screen: screen every Turn try before tidy; only the cheapest screened try gets tidy + validate

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-307`, branch `lane/307`,
base tag `round-55-wave2-base` (the commit that holds this task file), merge target `int/r55`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until every test below passes. Commit early, commit again, run the checks LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tools/turn_flip_census.sh`, `tools/ckpt.lua`, `tests/golden/generate.lua`, `factorio`, `tests/test_drawn_e2e.lua`,
`tests/test_collector_trial.lua`, or any full suite, census, whole golden sheet or headless run of any kind.**
Single test files only: `timeout 100 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4). Never use `coroutine` or
`math.random`. `require` only at file top level. **No game item or entity name in `logic/`.** Deterministic: fixed
order, ties broken by id string. Every new test must FAIL on the base code (say so in its header comment, date
2026-10-03); commit it red first, then the code.

Read `CONTEXT.md` first: **Block**, **Turn**, **Flip**, **Drawn pack**, **Material cost**, **Material tie**,
**Footprint**, **Turn trial**, **Trial fail**; and `docs/adr/0002-turn-trials-may-trade-generation-time-for-layout.md`.

## What is true (explain very simply)

After a drawn sheet is valid, `logic/bp/search.lua` tries other Turns per Block (`begin_turn_trials` :1670,
`trial_next` :1614). Each try runs pack -> route -> hands -> power -> tidy -> validate. Trial time is capped at the
ticks the search took before trials (`state.step_count - ticks_before >= ticks_before`; a running try is cut, row
`result="cut"`). Measured on the real red-1s drawn sheet (legalcopilot-dev 2026-10-03): search before trials 186
ticks; ONE full try needs 466 ticks, tidy alone 104+ of them. So no try ever finishes under the cap.

Tidy starts at search.lua:2289 (`state.work.route_state = Route.tidy_begin(...)`), right after power succeeds with
`state.work.post_tidy_power` false (:2255-2290). At that point the try's entities are `state.work.hand_entities`
plus `state.work.power.result.entities`. Material of a list: `MaterialCost.blueprint(catalog, entities)`
(`logic/bp/material_cost.lua`), catalog `state.work.input.catalog`.

## PRESERVE

- Layered pack, forced Turn/Flip runs and every normal (non-trial) run: same flow, same bytes as base. Tidy of a
  normal run starts exactly as today.
- Cap rule and `result="cut"` (TT15), keep rule (TT9), stage "trial" only during trials (TT13), rule pose = pack dir
  (TT14). TT1-TT15 keep passing (update a test's stubs only where screening changes what it must stub; never weaken
  an assertion).
- The 4 frozen lines stay byte-identical: `local function set_phase(state, phase)`,
  `local function start_grid(state)`, `local function record_rejection(state, errors, stage)`,
  `local function record_valid_attempt(state, score)`.

## What to build (in `logic/bp/search.lua` only)

1. **Incumbent pre-tidy Material.** In every run (trial or not), when power succeeds just before tidy starts
   (:2289), store `state.work.pre_tidy_material = MaterialCost.blueprint(catalog, hand_entities + power entities)`
   (nil allowed). When a candidate is accepted as incumbent (both accept exits), copy it to
   `state.incumbent.pre_tidy_material`.
2. **Screen phase.** Trials run in two rounds:
   - **Screen**: for each pose in today's order, run pack -> route -> hands -> power only. At the pre-tidy point,
     compute that try's pre-tidy Material, record row `result="screened"`, `material=<pre-tidy>`, and DO NOT start
     tidy: go to the next pose. A pack/route/power failure is a row as today (`fail`, `pin`); a Flip rebuild refusal
     as today (`forbidden` / `fail`).
   - **Final**: after all poses are screened (or the cap is reached during screening -> current try cut, then no
     final), take the screened pose with the lowest pre-tidy Material (ties: lower pose index). If its Material
     `<= state.incumbent.pre_tidy_material` (or the incumbent has none), run it once in full (pack -> ... -> tidy ->
     validate) and judge it with today's keep rule; its row gets `won` / `lost` / `fail` / `cut`, `material` =
     post-tidy. Otherwise no final; serialize the incumbent.
   - The cap counts screen + final together (unchanged rule).
3. **Record.** `trial` gains `screened = <count>` and `finalist = "<block> <pose>"` (nil when no final). Rows keep
   their format; a screened row has `area=nil`.

## Tests (`tests/test_turn_trial.lua`, append; print each marker at the end of its passing case)

- TS1 screened tries never start tidy: count `Route.tidy_begin` calls = 1 (incumbent) + 1 (final) on a sheet with
  3 poses; rows show 3 `screened`.
- TS2 only the lowest screened pose runs in full: stub pre-tidy Material per pose dir (e.g. dir 4 -> 70, 8 -> 90,
  12 -> 95, incumbent 100): final is dir 4; `trial.finalist` names it.
- TS3 every screened pose above the incumbent's pre-tidy Material -> no final, incumbent delivered, `finalist` nil.
- TS4 a screened try whose route fails -> row `fail` with the route code; screening goes on.
- TS5 cap reached during screening -> current try `cut`, no final, incumbent delivered, `state.ok == true`.
- TS6 a normal accepted run records `state.incumbent.pre_tidy_material` (number when catalog has material).

## Files this lane owns

`logic/bp/search.lua`, `tests/test_turn_trial.lua`.

## Commit, THEN check

Commit on `lane/307`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane307-tests", "command": "git diff --name-only round-55-wave2-base HEAD | grep -Ev '^(logic/bp/search\\.lua|tests/test_turn_trial\\.lua)$' | ( ! grep . ) && run() { o=$(timeout 100 lua5.2 tests/$1.lua 2>&1); l=$(echo \"$o\" | tail -1); n=$(echo \"$l\" | sed -n 's/.*: \\([0-9][0-9]*\\) cases.*/\\1/p'); echo \"$l\" | grep -q ' 0 failed' || { echo FAIL $1; return 1; }; [ -n \"$n\" ] && [ \"$n\" -ge $2 ] || { echo COUNT $1 got=$n floor=$2; return 1; }; return 0; }; for l in \"local function set_phase(state, phase)\" \"local function start_grid(state)\" \"local function record_rejection(state, errors, stage)\" \"local function record_valid_attempt(state, score)\"; do [ \"$(grep -cF \"$l\" logic/bp/search.lua)\" = 1 ] || { echo FROZEN \"$l\"; exit 1; }; done; out=$(timeout 100 lua5.2 tests/test_turn_trial.lua 2>&1); for m in TT1 TT2 TT3 TT4 TT5 TT6 TT7 TT8 TT9 TT10 TT11 TT12 TT13 TT14 TT15 TS1 TS2 TS3 TS4 TS5 TS6; do echo \"$out\" | grep -qw \"$m\" || { echo NOMARK $m; exit 1; }; done; timeout 100 lua5.2 tests/test_golden_profile.lua 2>&1 | tail -1 | grep -q \" 0 failed\" || { echo FAIL test_golden_profile; exit 1; }; for p in test_turn_trial:21 test_search:46 test_search_draw_phase:4 test_search_retry:5 test_search_budget:6 test_search_stop:8 test_search_allowance:8 test_search_strict:5 test_candidate_links:1 test_force_turn_flip:8 test_pack_drawn:12 test_material_cost:1 test_progress_view:9 test_turned_block:6 test_orient:6 test_no_item_names:1 test_no_runtime_require:3 test_locale_keys:3; do run ${p%%:*} ${p#*:} || exit 1; done && echo lane307-tests-ok", "expect_exit": 0, "expect_regex": "lane307-tests-ok", "timeout_s": 2400}
```
