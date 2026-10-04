# 310_groups_slices: Groups: cache per search, candidate_inserter hoists, every big call sliced (groups.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-310`, branch `lane/310`,
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
2026-10-04); commit it red first, then the code. Each new test prints its marker (e.g. `GS1`) at the end of its
passing case.

Read `CONTEXT.md` first (**Block**, **Row**, **Tick cost**) and `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`.
Evidence and the in-memory probe patches this lane ports: `docs/tasks/r56_probes/` (p_box.lua, fp.lua, spike.lua, 18-groups-per-grid.md, 17-pack-spikes.md, 06-tail-ticks.md).

## Slice rule (frozen, every lane that slices)

A sliced call keeps a cursor in its work table, charges `budget.ops` at least 1 per unit of real work (named per
item below), returns when `budget.ops <= 0`, and resumes on the next call with the same result. A slice never
changes iteration order: final result byte-identical to the one-shot call. Game gives 2000 ops per tick
(`logic/jobs.lua:28`; never change it — the integrator raises it to 4000 after all lanes merge).

## What is true (explain very simply)

- Groups re-runs at each grid start, all buckets in one tick, charged 1 op per bucket (`logic/bp/groups.lua:2724`).
  Per regroup (lua5.2): blue 0.9 s x6, magenta 2.2 s x6. Its output is equal across grids of one search (ticket 18,
  `fp.lua`): `groups.lua` never reads the grid. Only `split_steps` and `ring_bump` change it, and ring_bump only
  shifts the buffer_zones ring.
- `candidate_inserter` builds a world box per tile (`:536`) and a rotation per direction (`:508`); `p_box.lua` hoists
  both (BOX + ROT): Groups 2.0-5.6x faster, bytes same.
- Unsliced calls: hand loop (`:1007`), beacon `place_row` (`:2018`) / `redundant` (`:2159`) (blue chem 247 ms),
  `build_block` (`:1360`, 204 ms).

## What to build

1. Groups result cache per search keyed by `split_steps` + `ring_bump` (exact rule from `18-groups-per-grid.md`);
   cache hit returns a result equal to a fresh run.
2. BOX + ROT hoists from `p_box.lua` as real code.
3. Slice per Slice rule: hand loop (unit = one hand), beacon place_row / redundant (unit = one beacon candidate),
   build_block (unit = one machine), bucket loop at `:2724` charged by real work.

## Tests (`tests/test_groups_slices.lua`, fixture `tests/fixtures/r56/blue_bound_groups.json`)

- GS1 second Groups call with same split_steps + ring_bump = cache hit, output equal to fresh run.
- GS2 candidate list with hoists == base list (record base sha in the test).
- GS3 at 2000 ops no Groups call does more than one unit past budget; resumable; beacon rows resume same placements.
- GS4 whole Groups result sha on blue fixture and `tests/fixtures/groups_am2.json` == base sha.

## Files this lane owns

`logic/bp/groups.lua`, `tests/test_groups_slices.lua`, `tests/fixtures/r56/310/`.

## Integrator-proven (not yours; do not try)

Groups phase worst tick <= 50 ms on blue, magenta; Groups CPU per sheet.

## Commit, THEN check

Commit on `lane/310`. **Run the check as the very LAST action.**

## What done mean

- GS1, GS2, GS3, GS4 pass and print markers; red on base.
- Every groups test listed in `tools/lane_check_r56.sh` (R310) green.
- Diff only inside owned files; guards green.

```checks
{"name": "lane310-check", "command": "sh tools/lane_check_r56.sh 310", "expect_exit": 0, "expect_regex": "lane310-ok", "timeout_s": 3000}
```
