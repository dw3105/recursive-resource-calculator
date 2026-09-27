# 257_golden_profile profile one golden generation into JSON and render all profiles as one HTML page

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-257`, branch `lane/257`,
base tag `round-45-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/route_fail_snapshot.lua`, `tools/game_test.sh`, `factorio`,
or any full suite, sheet run or headless run of any kind, never `tests/golden/generate.lua` directly (only through your tool, only on player-red-science-1s).** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or
entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment); commit it red
first.

## Explain very simply

We need detailed profiling of every golden case: where time goes, per phase, per grid, per candidate, per stage call,
per route demand, and why candidates are rejected. Game rate: `Search.step` gets 2000 ops per tick
(`logic/jobs.lua:28`); `tests/golden/generate.lua:513` defaults to 100000 -> profile at 2000 by default.

Reuse patterns: `tools/tick_parts.lua` (wrap every function of `logic.bp.{plan,groups,pack,route,power,validate,
hands,serialize}` with `os.clock`, then `dofile("tests/golden/generate.lua")` with `arg` set), `tools/speed_probe.sh`
MOD lines. Hook `local` functions of `logic/bp/search.lua` (`set_phase` ~79, `start_grid` ~1240, `record_rejection`
~121, `record_valid_attempt` ~1308) and `logic/bp/route.lua` (demand start: `work.current = begin_search(...)` in
`Route.step`; `fail_demand`; `restart_with_priority`) through `package.preload` + same-line `gsub` (assert exactly
one match; replacement as function). NEVER `require "tests.harness"`. Note: `state.interim` is never set by
search.lua -> first valid layout = first `record_valid_attempt` call.

## What to build

1. `tools/golden_profile.lua <case|prepared.json> <out.json> [--ops 2000] [--cap <cpu seconds>]` writing JSON:
   `case, git_head, ops_per_step, ok, error_codes[], entities, canonical_sha256, ticks, cpu_total, ops_used,
   capped(bool), worst_tick{cpu,tick,phase,parts{Module.fn:cpu}}, first_valid{tick,cpu}|null,
   phases[{name, entries, ticks, cpu, ops}], grids[{nth, grid_index, w, h, attempt, layered, start_tick, cpu, ops,
   outcome_stage, reject_codes[]}], stages{groups|pack|route|tidy|hands|power|validate|serialize: {calls, cpu, worst}},
   route{demands_attempted, restarts, expansions, abandoned{}, crossings_placed, runs}, route_demands_top[{flow_id,
   kind, cpu, expansions, outcome}] (20 slowest), calls{Module.fn: {n, cpu, worst}}, rejections{code: {count,
   stages{}}}, search{stop_reason, bound_reason, grid_trials, attempts}`. With `--cap`, stop at that CPU and write
   `capped: true` with everything so far.
2. `tools/golden_report.py <dir_with_json> <out.html>`: one self-contained HTML (inline CSS, no external files),
   light + dark via `prefers-color-scheme`, 16 px side gutter, no horizontal page scroll (tables scroll inside their
   own box). Summary table sorted by cpu_total: case, ok, cpu s, ticks, entities, slowest stage, top 3 calls, grids
   tried, route restarts, first valid tick. Then one section per case: phases table, grids table, stages table,
   top 10 calls, top 10 route demands, rejections. Numbers only, no prose paragraphs. Title from argument
   `--title` (default "RRC golden profile").
3. `tests/test_golden_profile.lua` (runs tools via `io.popen`, case `player-red-science-1s`, ~10 s):
   - GP1: JSON has every top-level field; `ok == true`; sum of `phases[].cpu` within 10 % of `cpu_total`;
     `ticks > 0`; `calls` has `Route.step`.
   - GP2: `--cap 1` on `player-red-science-1s` -> `capped == true` and file still valid JSON.
   - GP3: `python3 tools/golden_report.py <dir with 2 JSON> <out.html>` -> exit 0, HTML contains both case names and
     `prefers-color-scheme`.

## Files this lane owns

tools/golden_profile.lua, tools/golden_report.py, tests/test_golden_profile.lua, docs/tasks/257_golden_profile.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/257`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane257-tests", "command": "git diff --name-only round-45-base HEAD | grep -Ev '^(tools/golden_profile\\.lua|tools/golden_report\\.py|tests/test_golden_profile\\.lua|docs/tasks/257_golden_profile\\.md)$' | ( ! grep . ) && git diff --quiet round-45-base HEAD -- docs/tasks && ! git diff round-45-base HEAD -- logic tools | grep -q '^+.*coroutine' && for t in test_golden_profile test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane257-tests-ok", "expect_exit": 0, "expect_regex": "lane257-tests-ok", "timeout_s": 3000}
{"name": "lane257-fast", "command": "out=$(lua5.2 tests/test_golden_profile.lua 2>&1); for c in GP1 GP2 GP3; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane257-ok", "expect_exit": 0, "expect_regex": "lane257-ok", "timeout_s": 600}
```

# bound: 3000s
