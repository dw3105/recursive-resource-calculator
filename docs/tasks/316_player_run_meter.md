# 316_player_run_meter: Metered feed, bar 0.98 <= R <= 1.1, calc refs for Sheet sim (lab.lua + test_sheets.lua + refs)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-316`, branch `lane/316`,
base tag `player-run-base` (the commit that holds this task file), merge target `int/player-run`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until every check below passes. Commit early, commit again, run the check LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/game_test.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/golden_profile.lua`, `tools/ckpt.lua save`, `tests/golden/generate.lua`, `factorio`, any `*_delivers.lua`, or any
full suite, census, whole golden sheet or headless run of any kind.** Single test files only:
`timeout 100 lua5.2 tests/<file>.lua` or `timeout 100 lua5.2 tests/game/offline.lua tests/game/<file>.lua` (lua5.2 ONLY,
never lua5.4), each under 60 s. Never use `coroutine` or `math.random`. `require` only at file top level (headless
Factorio refuses runtime require). **No game item or entity name in `logic/`** (this lane touches no `logic/`).
Deterministic: fixed order, ties broken by id string. Every new test must FAIL on the base code (say so in its header
comment, date 2026-10-05); commit it red first, then the code. Each new test prints its marker (e.g. `MT1`) at the
end of its passing case.

Read `CONTEXT.md` first (**Player run**, **Metered feed**, **Sheet sim**, **Port feed**, **Case**).

## What is true (explain very simply)

Player asked (2026-10-05) for a **Player run** per golden: GUI clicks like a player, generate, blueprint in hand,
build it, feed exactly calc input rate, measure output, pass when each output R = measured / calc rate is
0.98 <= R <= 1.1. The integrator joins three lanes into `tests/game/test_player_run.lua`. This lane builds one part.
Cases (15): player-am2-chain-repaired, player-blue-science-10s, player-green-science-1s, player-inserter-10s,
player-inserter-10s-bulk, player-inserter-10s-stack1, player-red-green-science-10s, player-red-science-10s,
player-red-science-10s-bulk, player-red-science-10s-stack1, player-red-science-1s, player-red-science-1s-bulk,
player-red-science-1s-foundry, vanilla-2.1-red-science-1s, vanilla-2.1-green-science-1s. Magenta is skipped, never
touched.

Today (worktree read 2026-10-05): `Lab.feed_tick` (`tests/game/lib/lab.lua:194-216`) pushes as much as fits every
tick; `tests/game/test_sheets.lua` judges against `ports.targets`, which come from the generator's own blueprint
description (`tools/sheet_ports.py:310-311`), passes at 0.95 (`:141`, `:159`), stops at the first window >= 0.95,
and fails FEED_SHORT when a port belt lane is not full (`:127-136`, `:147`). With metering a belt is not full, so
FEED_SHORT must go.

## What to build

1. `tools/sheet_refs.py` (new): `tools/sheet_refs.py <case>` writes `tests/fixtures/sheets/<case>.refs.json` =
   `{"outputs": {full_name: rate_per_s}, "inputs": {full_name: rate_per_s}}`. Player Cases: outputs from
   `tests/golden/cases/<case>/prepared_input.json` `snapshot.targets[i]` (`full_name`, `rate_per_second`), inputs from
   `solver_result.unsolved_rates`. Vanilla Cases have no prepared input: write their refs by hand (calc of 1/s, checked
   2026-10-05 against the description): red `{"outputs":{"item/automation-science-pack":1.0},"inputs":{"item/copper-plate":1.0,"item/iron-plate":2.0}}`,
   green `{"outputs":{"item/logistic-science-pack":1.0},"inputs":{"item/copper-plate":1.5,"item/iron-plate":5.5}}`.
   Commit all 15 refs files (magenta: none).
2. `tools/game_stage.sh` + `tests/game/offline.lua`: stage each refs file as module `tests.game.fixtures.<case_underscored>_refs`
   (Lua table), and each player Case's prepared input as `tests.game.fixtures.<case_underscored>_prepared` (JSON string,
   like the fixtures.txt modules but with NO expected-file requirement). Offline preload mirrors both.
3. `tests/game/lib/lab.lua`, frozen API (the integrator and Sheet sim call exactly this):
   ```lua
   Lab.meter_new(inputs)  -- inputs {[full_name]=rate_per_s} -> pool {[full_name]={rate=r, credit=0}}
   Lab.meter_tick(pool, feeds, stack)  -- per input: credit += rate/60; items: walk that item's feeds in list order,
       -- each lane, insert_at_back one full stack while credit >= stack and the lane takes it, credit -= stack;
       -- fluids: insert_fluid{amount=credit} on that fluid's feeds in order, credit -= inserted
   Lab.meter_backlog(pool, feeds, stack) -> {full_name...}  -- items whose credit > 2 x stack x heads of that item
   Lab.judge(per_s, outputs) -> ok, problems, lines  -- per output R = per_s[full_name] / rate; problem
       -- "SHORT <name> R=<r>" if R < 0.98, "OVER <name> R=<r>" if R > 1.1; lines "<name> <x>/s of <y>/s R=<r>"
   ```
   Feeds keep their shape `{entity, item | fluid}` (item/fluid = bare name); pool keys are full names (`item/x`, `fluid/x`).
   `Lab.feed_tick` stays for the warmup fill (Port feed) and for twins (`per_tick`); do not change its behaviour.
4. `tests/game/test_sheets.lua`: refs from `<case>_refs` (never `ports.targets`/`ports.inputs` for judging; ports.json
   still gives tiles). Warmup = Port feed fill (`Lab.feed_tick`) as today; from measuring start, `Lab.meter_tick` only.
   Window loop: keep 3600-tick windows and 60000 limit; done when two windows in a row are within 2% (steady) or limit;
   judge the last window with `Lab.judge`. Remove FEED_SHORT; add problem `POOL_BACKLOG <names>` from `Lab.meter_backlog`
   at the judged window end. Log line `SHEET-SIM <case> ... R=` per output. Magenta stays `it.skip` as today.

## Tests (`tests/test_lab_meter.lua`, new; pure Lua with tiny fake belts/pipes, no harness game)

- MT1 rate 7.5/s, stack 4, one roomy feed: items inserted over 3600 ticks = 450 +- 4.
- MT2 two feeds of one item, first refuses (full): all credit goes to the second; total == MT1 total.
- MT3 fluid 133.6/s: inserted over 3600 ticks = 8016 +- 1, split across two pipes in list order.
- MT4 backlog fires when every feed refuses for long enough (> 2 x stack x heads), silent otherwise.
- MT5 judge: R 0.979 SHORT, 0.98 ok, 1.1 ok, 1.101 OVER; missing output counts as 0 -> SHORT.
- MT6 refs: 15 refs files exist; for player-red-green-science-10s refs inputs equal `ports.json` `inputs` within 1e-9
  (both are the same calc); magenta has no refs file.

## Files this lane owns

`tests/game/lib/lab.lua`, `tests/game/test_sheets.lua`, `tools/sheet_refs.py`, `tools/game_stage.sh`,
`tests/game/offline.lua`, `tests/fixtures/sheets/*.refs.json`, `tests/test_lab_meter.lua`.

## Integrator-proven (not yours; do not try)

Headless Sheet sim of 15 Cases under metering; Player run.

## Commit, THEN check

Commit on `lane/316`. **Run the check as the very LAST action.**

## What done mean

- MT1-MT6 pass and print markers; `tests/test_lab_meter.lua` red on base.
- `test_game_stage_tools` green; offline `test_sheets`, `test_feed`, `test_box_binding`, `test_flip_fluidboxes`, `test_turn_flip_sims`, `test_twins` green.
- Diff only inside owned files; guards green.

```checks
{"name": "lane316-check", "command": "sh tools/lane_check_pr.sh 316", "expect_exit": 0, "expect_regex": "lane316-ok", "timeout_s": 3000}
```
