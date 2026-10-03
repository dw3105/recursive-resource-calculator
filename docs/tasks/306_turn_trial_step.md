# 306_turn_trial_step: after a drawn sheet is valid, try other Turns per Block and keep the cheaper one

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-306`, branch `lane/306`,
base tag `round-55-base` (the commit that holds this task file), merge target `int/r55`. Host `legalcopilot-dev`.

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

Read `CONTEXT.md` first: **Block**, **Turn**, **Flip**, **Drawn pack**, **Fallback**, **Blocked fluid port**,
**Material cost**, **Material tie**, **Footprint**, **Turn trial**, **Trial fail**; and
`docs/adr/0002-turn-trials-may-trade-generation-time-for-layout.md`.

## Why (explain very simply)

Drawn pack turns each Block by a rule and never checks another Turn. We add one step at the end of a drawn search:
the sheet is already valid; then, one Block at a time, try another Turn (and a Flip for fluid Blocks), keep every
other Block where it was, route and validate again, and keep the try only if it is valid and cheaper. The valid
sheet stays saved the whole time; a bad try is thrown away. The same "try, compare, keep winner" already ships as
the collector trial (`logic/bp/search.lua:1846-1857`, `:2236-2257`) — copy its shape.

## Seams you call (other code provides them; in your tests, stand them in by assigning functions)

- `Pack.begin(input)` accepts `input.pins = {[block_id] = {x=, y=, dir=}}` (Block placed exactly there) and
  `input.trial = {block_id=, dir=}` (that Block only uses `dir`, placed last). Cannot fit -> pack state `failed`,
  error code `BP_P_TRIAL_PIN`.
- `MaterialCost.blueprint(catalog, entities) -> total, unknown_count` and
  `MaterialCost.by_flow(catalog, entities) -> {[flow_id] = total}` in `logic/bp/material_cost.lua`; both return
  `nil` when `catalog.material` is missing or empty. These two functions do NOT exist on your base: never edit
  `material_cost.lua`; in tests assign them on the module table (`MaterialCost.blueprint = function ... end`).
- Old placements: `state.incumbent.candidate.placements` (`{block_id, x, y, dir, w, h}`, set from
  `state.work.pack.result.placements` at search.lua:1320, incumbent built at :2232); posed Blocks:
  `state.incumbent.source_candidate.blocks`; entities: `state.incumbent.candidate.entities` (`name`, `flow_id`);
  catalog: `state.work.input.catalog`.

## PRESERVE

- Layered pack and every forced Turn/Flip run (`settings.force_turn_flip`) behave exactly as today.
- A drawn run where no try wins delivers the same placements and entities as today.
- The 4 frozen lines below stay byte-identical; no other test count drops.

## What to build (in `logic/bp/search.lua` only)

1. **Entry.** Both accept exits — the normal one (`if incumbent then`, :2258) and the collector-first win
   (:2236-2243, which sets `serialize_next` with `incumbent = nil`) — go to the trial step instead of serializing,
   when: `Pack.mode == "sugiyama"`, drawn not switched off (`state.work.drawn_off` falsy), no
   `settings.force_turn_flip`, `MaterialCost.blueprint` returns a number for the incumbent, and the step has not run
   yet for this search. Otherwise serialize exactly as today (Layered: never enters; bytes unchanged).
2. **Order.** Score each Block = sum of `by_flow[flow_id]` over `block.ports[].flow_id` (missing -> 0); try Blocks
   highest score first, ties by block id string. For each Block, poses in this order: the 3 other pack dirs
   (0,4,8,12 minus the incumbent placement dir) with today's machine pose; then, only if the Block uses a fluid port
   and every machine `can_flip` (same test as `logic/bp/orient.lua:20-23`), the mirror-toggled rebuild
   (`Groups.reorient(groups, block, {dir=<today's orient dir>, mirror=not today's})`) at all 4 pack dirs.
   Rebuild refused (nil) -> row `result=forbidden` if `Groups.fluid_port_walled(block)`, else `result=fail`,
   `code=BP_FAIL_FLIP_REBUILD`.
3. **One try.** Pack with `pins` = every other Block at its incumbent `{x, y, dir}`, `trial = {block_id, dir}`,
   the tried Block's rebuilt version if mirrored; then route -> hands -> power -> tidy -> validate as today. During
   a try: `state.incumbent` stays the saved valid sheet (so budget end delivers it — never
   `BP_FAIL_SEARCH_BUDGET`, :1592-1596); `collectors`, `lane_cap`, `strict_ends` copied from the incumbent's run;
   the collector trial branch (:2245-2255) and the lane_cap / strict_ends restarts (:2216-2225) are skipped; a
   failure never calls the normal `discard_candidate` retries (:1891-1916) or the Layered fallback — it ends the
   try only. No `record_valid_attempt` for a try: keep tries in `state.work.trial`.
4. **Keep rule.** Try valid -> `m_new, m_old` = `MaterialCost.blueprint` of try / incumbent. Win if
   `m_new < m_old` and `(m_old - m_new) > 0.10 * m_old`; or `|m_new - m_old| <= 0.10 * max(m_new, m_old)` and
   try `score.production_area` < incumbent's. A win replaces the incumbent (later tries pin against the new one).
   Row results: `won`, `lost`, `fail` (validate or route or power not ok; code = first error code), `pin` (pack
   `BP_P_TRIAL_PIN`), `forbidden` (Blocked fluid port).
5. **Stop.** Count calls of `Search.step` from `Search.begin` (`state.step_count`). At entry
   `ticks_before = state.step_count`. Stop when all poses are tried or
   `state.step_count - ticks_before >= ticks_before`; then serialize the incumbent (normal path).
6. **Record.** `state.result.search.trial = {ticks_before=, ticks=, tried=, won=, fails=, rows = {{block=,
   rule="<dir>/<0|1>", pose="<dir>/<0|1>", result=, code=, material=, area=}}}` (rule = incumbent pose at entry;
   material/area nil for pin/forbidden). Set next to `state.result.search = diagnostics` (:2278).
7. **Progress.** While the step runs, after every `set_phase` call put `state.progress.stage = "trial"` back.
8. **Frozen text.** These 4 lines stay byte-identical (a tool patches them by exact text):
   `local function set_phase(state, phase)`, `local function start_grid(state)`,
   `local function record_rejection(state, errors, stage)`, `local function record_valid_attempt(state, score)`.

## Tests (`tests/test_turn_trial.lua`, new; use `tests/fixtures/search_doubles.lua` like
`tests/test_search_draw_phase.lua` and `tests/test_search_strict.lua` do: stand in `Pack.begin/step`,
`Route.begin/step`, `Validate.begin/step`, `MaterialCost.blueprint/by_flow`; set `Pack.mode = "sugiyama"` and restore
everything after each case; every loop bounded at 3000 steps and failing with the stuck phase name; print each marker, e.g. `print("TT1")`, at the end of its passing case — the harness prints no case names)

- TT1 a try with lower Material (> 10%) wins: delivered placements use the tried dir; `trial.won == 1`.
- TT2 a try whose validate fails: incumbent delivered unchanged; row `result=fail`, `code` = validate code.
- TT3 try validate `BP_V_LANE_OVERLOAD`: no `start_grid` (route input count == 1 + tries), incumbent delivered.
- TT4 try route reports `collectors_used`: no nested collector trial, step goes on to next try.
- TT5 budget ends mid-try (`max_ops` small): `state.ok == true`, incumbent delivered, no `BP_FAIL_SEARCH_BUDGET`.
- TT6 both accept exits (plain and collector-first win) enter the step (`trial.tried > 0` in both).
- TT7 order: Block with larger `by_flow` sum tried first; mirror poses only for a fluid Block whose machines all
  `can_flip`; non-fluid Block gets exactly 3 tries.
- TT8 stop: tries stop once step_count - ticks_before >= ticks_before; `trial.ticks` recorded.
- TT9 Material tie + smaller `production_area` wins; Material tie + bigger area loses.
- TT10 `Pack.mode = "layered"`: step never runs, `search.trial` nil.
- TT11 during a try `state.progress.stage == "trial"` at route, validate and pack phases.
- TT12 pack `BP_P_TRIAL_PIN` -> row `result=pin`, next pose tried.

## Files this lane owns

`logic/bp/search.lua`, `tests/test_turn_trial.lua`. `logic/bp/groups.lua` is read-only: call `Groups.reorient` and
`Groups.fluid_port_walled` as they are.

## Commit, THEN check

Commit on `lane/306`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane306-tests", "command": "git diff --name-only round-55-base HEAD | grep -Ev '^(logic/bp/search\\.lua|tests/test_turn_trial\\.lua)$' | ( ! grep . ) && run() { o=$(timeout 100 lua5.2 tests/$1.lua 2>&1); l=$(echo \\\"$o\\\" | tail -1); n=$(echo \\\"$l\\\" | sed -n 's/.*: \\\\([0-9][0-9]*\\\\) cases.*/\\\\1/p'); echo \\\"$l\\\" | grep -q ' 0 failed' || { echo FAIL $1; return 1; }; [ -n \\\"$n\\\" ] && [ \\\"$n\\\" -ge $2 ] || { echo COUNT $1 got=$n floor=$2; return 1; }; return 0; }; for l in 'local function set_phase(state, phase)' 'local function start_grid(state)' 'local function record_rejection(state, errors, stage)' 'local function record_valid_attempt(state, score)'; do [ $(grep -cF \"$l\" logic/bp/search.lua) = 1 ] || { echo FROZEN $l; exit 1; }; done; out=$(timeout 100 lua5.2 tests/test_turn_trial.lua 2>&1); for m in TT1 TT2 TT3 TT4 TT5 TT6 TT7 TT8 TT9 TT10 TT11 TT12; do echo \"$out\" | grep -q \"$m\" || { echo NOMARK $m; exit 1; }; done; timeout 100 lua5.2 tests/test_golden_profile.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL test_golden_profile; exit 1; }; for p in test_turn_trial:12 test_search:46 test_search_draw_phase:4 test_search_retry:5 test_search_budget:6 test_search_stop:8 test_search_allowance:8 test_search_strict:5 test_candidate_links:1 test_force_turn_flip:8 test_ports_on_edge_ring:5 test_turned_block:6 test_orient:6 test_no_item_names:1 test_no_runtime_require:3 test_locale_keys:3; do run ${p%%:*} ${p#*:} || exit 1; done && echo lane306-tests-ok", "expect_exit": 0, "expect_regex": "lane306-tests-ok", "timeout_s": 2400}
```
