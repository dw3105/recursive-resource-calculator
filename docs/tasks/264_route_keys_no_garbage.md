# 264_route_keys_no_garbage route search stops building strings and tables it throws away

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-264`, branch `lane/264`,
base tag `round-46-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/ckpt.lua save`, `tools/ckpt.lua uninterrupted`, `factorio`, or any full suite, whole sheet or headless run of
any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
`lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/<fixture>` (seconds). Never use `coroutine`. `require`
only at file top level. **No game item or entity name in `logic/`.** Every new test must FAIL on the base code where
this task says "red on base" (say so in its header comment); commit it red first.

## Explain very simply

Route search is slow because each search step builds garbage (measured legalcopilot-dev 2026-09-28, lua5.2):
- K1 `logic/bp/route.lua:148` `coordinate_key` builds `tostring(x)..":"..tostring(y)` 29-32 times per step.
  Fix: 2-level cache `KEY_CACHE[x][y]` holding the SAME strings. Patch text: `docs/tasks/r46_probes/p_keycache.lua`.
- K2 `logic/bp/grid.lua:202` `Grid.dir_vector` builds a table of 4 tables on EVERY call (74 % of garbage). Fix:
  constant table built once. Patch text: `docs/tasks/r46_probes/p_dirvec.lua`.
- K3 `route.lua` `state_key` (~:2288) = 5 string joins per enqueue. Fix: number
  `(((y + 8) * 4096 + (x + 8)) * 32 + (arrival_direction or 0)) * 8 + (underground_mode or 0)`.
  Patch text: `docs/tasks/r46_probes/p_statekey.lua`. Before committing, grep every use of `state_key(`
  results: they must only be used as table keys / equality, never parsed or concatenated.
- P1 `logic/bp/pipe_runs.lua:20-34` `opens_to` scans EVERY entity per neighbour test. Fix: index by
  `segment_id` + tile, built ONCE per `PipeRuns.prune_redundant` call as a LOCAL of that call (NEVER a field of
  `work`: `work` is saved in the map between ticks), first live candidate in `work.entities` order wins exactly as
  today. Probe `docs/tasks/r46_probes/p_pipeindex.lua` stores it in `work` — do NOT copy that part.
Measured with all 4 applied in memory: garbage per step 5.04 KB -> 1.31 KB; blue publish 573-773 ms -> 98 ms;
canonical sha of all 13 golden sheets unchanged.

`route.lua` main chunk has 171 top-level `local` lines; Lua limit 200. Add at most 1 (`KEY_CACHE`).

Probe usage (patch applied in memory at load):
`lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/green_tidy.lua.gz --patch docs/tasks/r46_probes/p_garbage.lua`
prints `GARBAGE steps=... kb_per_step=...` and at END `sha=...`. Base digests: `tests/fixtures/route_snaps/r46_digests.txt`.
Base green resume to end ~18 s.

## What to build

1. `tests/test_route_keys.lua` (`package.path = "./?.lua;" .. package.path`; subprocess via `io.popen` is fine):
   - KY1 10,000 `Grid.dir_vector` calls with collector stopped grow memory <= 16 KB. Red on base.
   - KY2 `tools/ckpt.lua resume green_tidy.lua.gz --patch docs/tasks/r46_probes/p_garbage.lua`: kb_per_step <= 1.4.
     Red on base (5.04).
   - KY3 same run: `sha=6b65a1d1c6408dc4d805159f33345d2b8b901da398ffc3ca846d2f6f6d464976`, ticks=1444, entities=299.
   - KY4 publish prune on a small fluid layout (build from `tests/test_pipe_prune.lua` shapes, >= 40 entities):
     entity visits inside `opens_to` <= 4 per call (count through a test-only counter, e.g. `PipeRuns._visits`
     incremented only when `PipeRuns._count_visits` is true). Red on base. Result identical to base result
     (same removed set).
   - KY5 `coordinate_key` returns the same string value as `tostring(x)..":"..tostring(y)` for negative, zero and
     large x/y (export it as `Route._coordinate_key` if needed for the test).
2. `logic/bp/route.lua`, `logic/bp/grid.lua`, `logic/bp/pipe_runs.lua`: K1 K2 K3 P1, short comments with the
   measured numbers + date.
3. Also run and keep green: `test_route`, `test_route_improve`, `test_route_ticks`, `test_pipe_prune`,
   `test_pipe_runs`, `test_pipe_leaf_prune`, `test_route_pipe_join`, `test_grid`.

## Files this lane owns

logic/bp/route.lua (ONLY `coordinate_key` ~:148-150, `state_key` ~:2288-2291, optional `Route._coordinate_key`
export), logic/bp/grid.lua (ONLY `Grid.dir_vector`), logic/bp/pipe_runs.lua, tests/test_route_keys.lua,
docs/tasks/264_route_keys_no_garbage.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/264`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane264-tests", "command": "git diff --name-only round-46-base HEAD | grep -Ev '^(logic/bp/route\\.lua|logic/bp/grid\\.lua|logic/bp/pipe_runs\\.lua|tests/test_route_keys\\.lua|docs/tasks/264_route_keys_no_garbage\\.md)$' | ( ! grep . ) && git diff --quiet round-46-base HEAD -- docs/tasks && for t in test_route_keys test_route test_route_improve test_route_ticks test_pipe_prune test_pipe_runs test_pipe_leaf_prune test_route_pipe_join test_grid test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane264-tests-ok", "expect_exit": 0, "expect_regex": "lane264-tests-ok", "timeout_s": 3000}
{"name": "lane264-fast", "command": "out=$(lua5.2 tests/test_route_keys.lua 2>&1); for c in KY1 KY2 KY3 KY4 KY5; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane264-ok", "expect_exit": 0, "expect_regex": "lane264-ok", "timeout_s": 600}
```

# bound: 3000s
