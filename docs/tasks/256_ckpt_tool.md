# 256_ckpt_tool save the whole generation state at any named step and resume from it

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-256`, branch `lane/256`,
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

We need to repeat ANY step of a golden generation in seconds, from ANY point, instead of rerunning from the start.
Search state is pure data (`logic/bp/search.lua:3-5`; no functions, coroutines, metatables in state). Measured
2026-09-27 on `player-red-science-1s` in memory: dump state after the Search.step tick at phases pack/route/tidy/
power/validate as a Lua chunk, `load()` it, continue with `Search.step(st, {ops = 2000})` -> every resume ended at tick
171, `ops_used = 332165`, 148 entities, deep-equal result. Dump 4 MB in 0.43 s, load 0.12 s.

Existing serializer `save_graph` in `tools/route_fail_snapshot.lua` has two bugs: `tostring(number)` keeps 14 digits
(145 numbers of a red-1s snapshot changed); `math.huge` is written as `inf` and reloads as nil
(`route.lua` stores `st.pair_best_weight = math.huge`). Move it to `tools/lib/graph_dump.lua` fixed: integers
`|n| < 2^53` as `%d`, other numbers `%.17g`, `math.huge` / `-math.huge` / `(0/0)` written explicitly; shared
references and cycles preserved; functions/userdata/threads skipped with a stderr list. Make
`tools/route_fail_snapshot.lua` use the lib (same output behaviour; `tests/test_route_fail_snapshot.lua` stays green).

Hook points (all `local` in `logic/bp/search.lua`): `set_phase` (~79), `record_rejection` (~121), `start_grid`
(~1240), `discard_candidate` (~1604); in `logic/bp/route.lua`: `begin_search` call sites (a demand start increments
`work.counters.demands_attempted`), `fail_demand`, `restart_with_priority` (`counters.restarts`). Hook with
`package.preload[...]` + `gsub` of the function's first line appending `if _G.__ckpt then _G.__ckpt(...) end` ON THE
SAME LINE (tracebacks keep line numbers), assert exactly one match. Replacement strings as functions (`%` breaks
gsub). NEVER `require "tests.harness"` (it resets `logic.*` and sets game globals that change Plan's output);
drive `tests/golden/generate.lua` via `dofile` with `arg` set, like `tools/tick_parts.lua`.

Module state not in the snapshot: `pack.lua` reads env `RRC_PACK`, `RRC_PACK_EXTRA` at load -> record in meta,
resume warns on mismatch.

## What to build

1. `tools/lib/graph_dump.lua`: `dump(value, path)` -> writes chunk returning the value; `load(path)` (plain or
   `.gz` via `gzip -dc`).
2. `tools/ckpt.lua` (usage in header comment):
   - `lua5.2 tools/ckpt.lua list <case|prepared.json> [--ops 2000]` -> one line per event:
     `EV n=<k> tick=<t> ops=<o> kind=<phase|stage-begin|grid|reject|route-demand|route-restart> phase=<p>
     grid=<i> attempt=<a> layered=<0|1> detail=<...>`.
   - `save <case> <at-spec> <out.lua[.gz]> [--ops 2000]` -> runs until the at-spec matches, saves at the end of that
     Search.step tick: `{state, meta = {case, input_path, input_sha256, git_head, tick, ops_per_step, spec,
     env = {RRC_PACK, RRC_PACK_EXTRA}, lua = _VERSION}}`; prints `SAVED <out> tick=<t> event=<...>`.
   - `resume <file> [--until <at-spec> --save <out>] [--ops N] [--patch file.lua] [--output result.json]` -> replaces
     `Search.begin` with a function returning the loaded state, sets the tick counter to `meta.tick`, runs
     `generate.lua`; prints `RESUMED ... END ok=<b> ticks=<t> ops_used=<o> sha=<canonical_sha256> entities=<n>`.
     `--patch` = file returning `function(module_name, src) return src end` applied to every `logic.bp.*` source.
   - At-spec: comma-separated AND of `phase=`, `stage-begin=`, `grid=`, `attempt=`, `layered=`, `route-demand=`,
     `route-restart=`, `reject=`, `reject-code=`, `tick=`, plus `nth=K` (K-th match, default 1).
   - `uninterrupted <case> [--ops 2000]` -> plain run printing the same END line (reference for tests).
3. `tests/test_ckpt.lua` (runs tools via `io.popen`, case `player-red-science-1s`, ~10 s each):
   - CK1: `save` at `phase=route`, `phase=tidy`, `phase=validate`; `resume` each -> END line equal to `uninterrupted`
     (ok, ticks, ops_used, sha, entities).
   - CK2: `resume <route snapshot> --until phase=validate --save b` then `resume b` -> same END.
   - CK3: graph_dump round trip of `{a = 0.1 + 0.2, b = math.huge, c = -math.huge, d = 2^60 + 1.5, s = shared, t =
     shared}` -> exact numbers, `b == math.huge`, `s == t` (same table).
   - CK4: `list` prints at least one `kind=phase` and one `kind=route-demand` line.

## Files this lane owns

tools/lib/graph_dump.lua, tools/ckpt.lua, tools/route_fail_snapshot.lua, tests/test_ckpt.lua, docs/tasks/256_ckpt_tool.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/256`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane256-tests", "command": "git diff --name-only round-45-base HEAD | grep -Ev '^(tools/lib/graph_dump\\.lua|tools/ckpt\\.lua|tools/route_fail_snapshot\\.lua|tests/test_ckpt\\.lua|docs/tasks/256_ckpt_tool\\.md)$' | ( ! grep . ) && git diff --quiet round-45-base HEAD -- docs/tasks && ! git diff round-45-base HEAD -- logic tools | grep -q '^+.*coroutine' && for t in test_ckpt test_route_fail_snapshot test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane256-tests-ok", "expect_exit": 0, "expect_regex": "lane256-tests-ok", "timeout_s": 3000}
{"name": "lane256-fast", "command": "out=$(lua5.2 tests/test_ckpt.lua 2>&1); for c in CK1 CK2 CK3 CK4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane256-ok", "expect_exit": 0, "expect_regex": "lane256-ok", "timeout_s": 600}
```

# bound: 3000s
