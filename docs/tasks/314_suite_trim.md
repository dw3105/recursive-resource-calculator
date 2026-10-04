# 314_suite_trim: suite: Turn/Flip slice by default, full on demand; twins vanilla only (tests + run.sh + game_test.sh)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-314`, branch `lane/314`,
base tag `round-56-base` (the commit that holds this task file), merge target `int/r56`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until every check below passes. Commit early, commit again, run the check LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua` on a sheet, `tools/game_test.sh`,
`tools/turn_flip_census.sh`, `tools/ckpt.lua save`, `tests/golden/generate.lua`, `factorio`,
`tests/test_turn_flip_census.lua`, `tests/test_drawn_e2e.lua`, `tests/test_collector_trial.lua`, any `*_delivers.lua`,
or any full suite, census, whole golden sheet or headless run of any kind.** Single test files only:
`timeout 100 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4), each under 60 s. Never use `coroutine` or
`math.random`. `require` only at file top level. **No game item or entity name in `logic/`.** Deterministic: fixed
order, ties broken by id string. Every new test must FAIL on the base code (say so in its header comment, date
2026-10-04); commit it red first, then the code. Each new test prints its marker (e.g. `TS1`) at the end of its
passing case.

Read `CONTEXT.md` first (**Turn/Flip slice**, **Twin**, **Player profile**, **Vanilla profile**) and `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`.
Evidence and the in-memory probe patches this lane ports: `docs/tasks/r56_probes/` (03-suite-time.md).

## Slice rule (frozen, every lane that slices)

A sliced call keeps a cursor in its work table, charges `budget.ops` at least 1 per unit of real work (named per
item below), returns when `budget.ops <= 0`, and resumes on the next call with the same result. A slice never
changes iteration order: final result byte-identical to the one-shot call. Game gives 2000 ops per tick
(`logic/jobs.lua:28`; never change it — the integrator raises it to 4000 after all lanes merge).

## What is true (explain very simply)

Suite 53 min (legalcopilot-dev 2026-10-03, ticket 03): `tests/test_turn_flip_census.lua` 904 s (288 sheets, 4
cores); headless `tests/game/test_turn_flip_sims.lua` 456 s over 3 configs; twins (`tests/game/test_twins.lua`)
run on the player profile too (25-32 s per shard vs 8-13 vanilla). Player ruled (ticket 07): suite runs a slice,
full census + full sims on demand and at release; twins vanilla 2.0 + 2.1 only.

## What to build

1. `tools/turn_flip_slice.lua`: pure function `Slice.pick(cases, round_id, full) -> list`: 18 cases, one pose each,
   pose index = (case index + round_id) mod poses; `full` -> all cases all poses. Deterministic.
2. `tests/test_turn_flip_census.lua` and `tests/game/test_turn_flip_sims.lua` use it: default slice (2.0 only for
   census), full when `RRC_FULL_TURN_FLIP=1`. Round id from env `RRC_ROUND` (default 56).
3. `tests/game/test_twins.lua` runs only on the vanilla profile (skip with a named reason on player profile);
   `tools/game_test.sh` profile map says so as data.
4. `tests/run.sh` passes `RRC_FULL_TURN_FLIP` and `RRC_ROUND` through to children.

## Tests (`tests/test_turn_flip_slice.lua`; never run the census test itself)

- TS1 default pick = 18 cases, one pose each; TS2 round_id + 1 rotates every pose; TS3 full = every case and pose the census
  runs today (count from `tests/fixtures/turn_flip_cases_2.0.json` / the census case list, not hard-coded); TS4 twins file declares vanilla-only and `game_test.sh` profile map
  (read as text) excludes it from player; TS5 `tests/run.sh` text exports both env vars.

## Files this lane owns

`tools/turn_flip_slice.lua`, `tests/test_turn_flip_census.lua`, `tests/game/test_turn_flip_sims.lua`,
`tests/game/test_twins.lua`, `tests/run.sh`, `tools/game_test.sh`, `tests/test_turn_flip_slice.lua`.

## Integrator-proven (not yours; do not try)

Suite wall time; headless sims slice in game; full census at release.

## Commit, THEN check

Commit on `lane/314`. **Run the check as the very LAST action.**

## What done mean

- TS1-TS5 pass and print markers; red on base.
- `test_game_runner_guard`, `test_turn_flip_cases`, `test_turn_flip_census_tool`, `test_twins`, `test_twins_coverage`, `test_export_completeness`, `test_slow_guard` green.
- Diff only inside owned files; guards green.

```checks
{"name": "lane314-check", "command": "sh tools/lane_check_r56.sh 314", "expect_exit": 0, "expect_regex": "lane314-ok", "timeout_s": 3000}
```
