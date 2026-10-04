# 315_split_units_recipe: split units (RRC_CASE, JUnit per unit) + Suite Runner recipe, image, lock

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-315`, branch `lane/315`,
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
2026-10-04); commit it red first, then the code. Each new test prints its marker (e.g. `SU1`) at the end of its
passing case.

Read `CONTEXT.md` first (**Split unit**, **Case**, **Sheet sim**) and `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`.
Evidence and the in-memory probe patches this lane ports: `docs/tasks/r56_probes/` (15-suite-runner-unit-format.md, 03-suite-time.md).

## Slice rule (frozen, every lane that slices)

A sliced call keeps a cursor in its work table, charges `budget.ops` at least 1 per unit of real work (named per
item below), returns when `budget.ops <= 0`, and resumes on the next call with the same result. A slice never
changes iteration order: final result byte-identical to the one-shot call. Game gives 2000 ops per tick
(`logic/jobs.lua:28`; never change it — the integrator raises it to 4000 after all lanes merge).

## What is true (explain very simply)

- Suite Runner (saas-mvp 88ce28b) splits a recipe with `"split": "auto"` by JUnit address: unit = part before the
  first `::`; `{ids}` in the test command gets shlex-quoted chunk addresses; collected id must equal JUnit address
  `classname::name` exactly, else the chunk is INCOMPLETE; prefix must not contain `::` (ticket 15).
- RRC has no per-case filter and no JUnit output. Big files: census 904 s, turn_flip_sims 456 s, sheet sims 176 s.

## What to build

1. `tests/harness.lua`: `RRC_CASE=<name>` runs only that case (exact name; several comma-separated); default all.
2. `tools/junit.lua`: harness writes `junit-<file>.xml` when `RRC_JUNIT_DIR` set; classname `lua/<file>`, except
   census -> `census/<case>`, sheet sims -> `sheets/<case>`, Turn/Flip sims -> `turnflip/<case>`, other headless ->
   `game/<file>`.
3. `tools/suite_units.sh collect` prints every unit address (one `classname::name` per line) without running tests;
   `tools/suite_units.sh run <ids...>` runs exactly those.
4. `tests/game/support.lua`: one unit per sheet sim (address `sheets/<case>::sim`).
5. `ci/suite-runner/rrc.recipe.json` (schema v1 run-recipe, `"split": "auto"`, test command with `{ids}`),
   `ci/image/Dockerfile` (lua5.2, python3, Factorio 2.0.77 + 2.1.20 headless, player mods from
   `tests/player_mods.lock.json`), `ci/image.lock` (`<ref>@sha256:<64 hex>` placeholder line marked TODO-integrator).

## Tests

- `tests/test_split_units.lua`: SU1 `RRC_CASE=a` runs only a; SU2 collect ids == JUnit addresses of the same tiny
  suite (fixture under `tests/fixtures/r56/315/`); SU3 no `::` inside classname; SU4 census + sheets get per-case
  prefixes; SU5 unknown RRC_CASE -> exit non-zero, names it.
- `tests/tools/test_recipe.py`: RC1 recipe has split auto + `{ids}`; RC2 lock line format; RC3 Dockerfile pins
  versions. Print markers RC1..RC3.

## Files this lane owns

`tests/harness.lua`, `tools/junit.lua`, `tools/suite_units.sh`, `tests/game/support.lua`, `ci/suite-runner/rrc.recipe.json`,
`ci/image/Dockerfile`, `ci/image.lock`, `tests/test_split_units.lua`, `tests/tools/test_recipe.py`, `tests/fixtures/r56/315/`.

## Integrator-proven (not yours; do not try)

Image build + real lock sha; one local collect over the real suite; cloud run (round 57).

## Commit, THEN check

Commit on `lane/315`. **Run the check as the very LAST action.**

## What done mean

- SU1-SU5, RC1-RC3 pass and print markers; red on base.
- `test_harness`, `test_harness_api`, `test_no_runtime_require` green (harness change keeps every other test file working: integrator suite proves).
- Diff only inside owned files; guards green.

```checks
{"name": "lane315-check", "command": "sh tools/lane_check_r56.sh 315", "expect_exit": 0, "expect_regex": "lane315-ok", "timeout_s": 3000}
```
