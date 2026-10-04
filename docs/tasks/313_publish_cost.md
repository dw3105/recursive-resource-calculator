# 313_publish_cost: publish tick: sha256 only on engine-test demand, one persist copy (generation.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-313`, branch `lane/313`,
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
2026-10-04); commit it red first, then the code. Each new test prints its marker (e.g. `PC1`) at the end of its
passing case.

Read `CONTEXT.md` first (**Tick cost**, **Parity row**) and `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`.
Evidence and the in-memory probe patches this lane ports: `docs/tasks/r56_probes/` (t_publish.lua, 09-start-publish.md, 06-cpu-levers.md).

## Slice rule (frozen, every lane that slices)

A sliced call keeps a cursor in its work table, charges `budget.ops` at least 1 per unit of real work (named per
item below), returns when `budget.ops <= 0`, and resumes on the next call with the same result. A slice never
changes iteration order: final result byte-identical to the one-shot call. Game gives 2000 ops per tick
(`logic/jobs.lua:28`; never change it — the integrator raises it to 4000 after all lanes merge).

## What is true (explain very simply)

- Publish tick computes a pure-Lua sha256 of the canonical JSON (`logic/bp/generation.lua:1004`, `:1292`): magenta
  710 of 1529 ms. Only `engine_test_api.lua:307` and offline tools read the digest (ticket 09).
- `persist_handle` copies the capture (`:137`), then copies the whole record again (`:139`), called 3 times per
  publish: 417 ms on magenta proxy. `t_publish.lua`: magenta-size publish 929 -> 212 ms lua5.2 with both levers.

## What to build

1. Compute `canonical_sha256` only when asked (engine test API flag or offline tool flag); blueprint string,
   canonical JSON and every other field unchanged.
2. `persist_handle` keeps one capture copy; stop the second copy of the record at `:139` (store fields directly).

## Tests (`tests/test_publish_cost.lua`)

- PC1 publish without the flag: no sha256 call (count via wrapper), delivered string same as base.
- PC2 persist makes one capture copy per call (count copy_plain calls on a stub capture).
- PC3 with engine-test flag the digest is present and equal to base digest (mock `engine_test_api` path).

## Files this lane owns

`logic/bp/generation.lua`, `tests/test_publish_cost.lua`, `tests/fixtures/r56/313/`.

## Integrator-proven (not yours; do not try)

Publish tick row; parity rows (in-game sha == offline sha) on changed sheets.

## Commit, THEN check

Commit on `lane/313`. **Run the check as the very LAST action.**

## What done mean

- PC1, PC2, PC3 pass and print markers; red on base.
- Every generation test listed in `tools/lane_check_r56.sh` (R313) green.
- Diff only inside owned files; guards green.

```checks
{"name": "lane313-check", "command": "sh tools/lane_check_r56.sh 313", "expect_exit": 0, "expect_regex": "lane313-ok", "timeout_s": 3000}
```
