# 312_validate_slices: validate: slice transfers, beacons, transport shapes, fluid mix (validate.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-312`, branch `lane/312`,
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
2026-10-04); commit it red first, then the code. Each new test prints its marker (e.g. `VS1`) at the end of its
passing case.

Read `CONTEXT.md` first (**Engine rule**, **Waste rule**, **Tick cost**) and `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`.
Evidence and the in-memory probe patches this lane ports: `docs/tasks/r56_probes/` (06-tail-ticks.md (spike map, validate classes)).

## Slice rule (frozen, every lane that slices)

A sliced call keeps a cursor in its work table, charges `budget.ops` at least 1 per unit of real work (named per
item below), returns when `budget.ops <= 0`, and resumes on the next call with the same result. A slice never
changes iteration order: final result byte-identical to the one-shot call. Game gives 2000 ops per tick
(`logic/jobs.lua:28`; never change it — the integrator raises it to 4000 after all lanes merge).

## What is true (explain very simply)

Blue spike map (ticket 06, `06-tail-ticks.md`): single validate calls run in one tick: `check_physical_transfers`
(`logic/bp/validate.lua:2331`, 205 ms), `check_beacons` (`:1071`, 115 ms), `check_transport_shapes` (`:1590`,
91 ms), `check_fluid_mix` (`:2979`, 51 ms).

## What to build

Slice all four per Slice rule (unit = one machine / beacon / transport entity / fluid segment). Code list, code
order and verdict stay identical to the one-shot call.

## Tests (`tests/test_validate_slices.lua`)

- VS1 transfers, VS2 beacons, VS3 transport shapes, VS4 fluid mix: on `tests/fixtures/validate_red_green_r40_c1.json`
  and `tests/fixtures/validate_red10s_attempt1.json` at 2000 ops every code list + verdict == one-shot base.
- VS5 each of the four charges >= 1 op per unit (count units in the fixture, compare ops spent).

## Files this lane owns

`logic/bp/validate.lua`, `tests/test_validate_slices.lua`, `tests/fixtures/r56/312/`.

## Integrator-proven (not yours; do not try)

Validate worst tick rows on blue, magenta, stack1.

## Commit, THEN check

Commit on `lane/312`. **Run the check as the very LAST action.**

## What done mean

- VS1-VS5 pass and print markers; red on base.
- Every validate test listed in `tools/lane_check_r56.sh` (R312) green.
- Diff only inside owned files; guards green.

```checks
{"name": "lane312-check", "command": "sh tools/lane_check_r56.sh 312", "expect_exit": 0, "expect_regex": "lane312-ok", "timeout_s": 3000}
```
