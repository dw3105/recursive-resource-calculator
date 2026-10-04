# 309_route_search: route fix bundle D1-D3 + strict ends from start + copies shared or sliced (route.lua, search.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-309`, branch `lane/309`,
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
2026-10-04); commit it red first, then the code. Each new test prints its marker (e.g. `RF1`) at the end of its
passing case.

Read `CONTEXT.md` first (**Block**, **Row**, **Dead pair**, **Tick cost**) and `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`.
Evidence and the in-memory probe patches this lane ports: `docs/tasks/r56_probes/` (p_strict.lua, p_fix.lua, p_fix2.lua, p_fix3b.lua, p06.lua, 19-order-fragility.md, 06-cpu-levers.md, 06-tail-ticks.md).

## Slice rule (frozen, every lane that slices)

A sliced call keeps a cursor in its work table, charges `budget.ops` at least 1 per unit of real work (named per
item below), returns when `budget.ops <= 0`, and resumes on the next call with the same result. A slice never
changes iteration order: final result byte-identical to the one-shot call. Game gives 2000 ops per tick
(`logic/jobs.lua:28`; never change it — the integrator raises it to 4000 after all lanes merge).

## What is true (explain very simply)

- Strict redo: when validate finds a belt shape fault, search sets `state.work.strict_ends = true`
  (`logic/bp/search.lua:2419-2421`) and routes the whole grid again; `:2037` clears it per grid. On magenta this is
  a second full route. `p_strict.lua` sets strict ends from the first routing: magenta -50% ticks, all 14 layered
  goldens same bytes (ticket 13, bound ticket 21).
- D1 (`logic/bp/route.lua:3287` body_jump; commit guard `:1871-1876` exempts splitters): a splitter branch ends on a
  row-port sink whose `travel_dir` differs from the trunk heading. Fix = `p_fix.lua`.
- D2 (`route.lua:3392`): pipe dive starting on another machine's fluid port tile is refused only under
  `work.strict_ptg`. Fix = `p_fix2.lua` (guard always).
- D3 (`route.lua:4334` `untangle_splitter_chains`, called `:4391`): untangle leaves a belt ending on nothing. Fix =
  `p_fix3b.lua` (after untangle, trim plain flow belts whose output tile holds no segment and no endpoint, repeat).
- Deep copies charged 0 ops make long ticks: `stage_input` (`search.lua:343`, 24-31 ms), incumbent copy
  (`search.lua:2441-2450`, ~170 ms on big sheets), route-input glue `make_route_input` (`search.lua:1197`), tidy
  `result_for` (`route.lua:3471`, 132 ms). `p06.lua` shares catalog + snapshot in stage_input: copy 113 -> 5 ms on
  red-1s, bytes same.

## What to build

1. Strict ends from first routing (port `p_strict.lua`), redo path at `:2419` kept for safety but never taken when
   strict already on.
2. D1, D2, D3 fixes as in the probes, written as real code (no `_G` counters).
3. `stage_input` shares read-only catalog + snapshot instead of deep copy; incumbent keep shares tables the search
   never mutates afterwards (copy only what is mutated); `make_route_input` and `result_for` sliced per Slice rule
   (unit = 64 copied keys / one entity).

## Tests

- `tests/test_route_fix_bundle.lua`: RF1 D1, RF2 D2, RF3 D3, each a small hand-built route case that reproduces
  the defect on base (red) and is fixed after; RF4 a search over a tiny case starts its first route with
  `strict_ends == true`.
- `tests/test_copy_share.lua`: CS1 stage_input does not deep-copy catalog (same table identity) and the stage does
  not mutate it; CS2 incumbent stays equal after later work mutation; CS3 sliced `result_for` / route-input glue on
  `tests/fixtures/r56/blue_bound_route.json` (or `tests/fixtures/route_red10s_final.json`) at 2000 ops: resumed result
  == one-shot result, and no single call copies more than one slice.

## Files this lane owns

`logic/bp/route.lua`, `logic/bp/search.lua`, `tests/test_route_fix_bundle.lua`, `tests/test_copy_share.lua`,
`tests/fixtures/r56/309/`.

## Integrator-proven (not yours; do not try)

Magenta layered 16805 / cd71d3e1 valid; 13 other layered + 14 drawn goldens same bytes; worst tick rows.

## Commit, THEN check

Commit on `lane/309`. **Run the check as the very LAST action.**

## What done mean

- RF1, RF2, RF3, RF4, CS1, CS2, CS3 pass and print markers; RF1-RF3 red on base (header comment says so).
- Every route and search test listed in `tools/lane_check_r56.sh` (R309) green.
- Diff only inside owned files; guards green.

```checks
{"name": "lane309-check", "command": "sh tools/lane_check_r56.sh 309", "expect_exit": 0, "expect_regex": "lane309-ok", "timeout_s": 3000}
```
