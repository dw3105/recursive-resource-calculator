# 268_route_search_inner_loop one search step builds each tile key once and no throwaway closures

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-268`, branch `lane/268`,
base tag `round-46-w1`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/ckpt.lua save`, `tools/ckpt.lua uninterrupted`, `factorio`, or any full suite, whole sheet or headless run of
any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), plus
`lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/<fixture> ...` and `lua5.2 tools/route_prof.lua <fixture> ...`
(seconds). Never use `coroutine`. `require` only at file top level. **No game item or entity name in `logic/`.**
Every new test must FAIL on the base code where this task says "red on base" (say so in its header comment);
commit it red first.

## Explain very simply

One A* search step (`search_step` `logic/bp/route.lua:2620`, `path_cell_free` `:2147`, `enqueue_state` `:2362`,
`begin_search` `:2385`, `faces_ok` closure `:2511`, `bury_candidate` `:1760`) still costs 35-40 us after round-46
wave 1: green tidy 38,391 steps, `coordinate_key` called 26.6 times per step (legalcopilot-dev 2026-09-28,
`tools/route_prof.lua tests/fixtures/route_snaps/green_tidy.lua.gz --until phase=validate --set all`).
Fix, no behaviour change:
- build a tile's key ONCE per step and pass it down to `path_cell_free`, `transition_cost`, `same_flow_port_tile`,
  `static_owner` and friends (add a `key` parameter; fall back to `coordinate_key(x, y)` when nil so other callers
  keep working);
- hoist closures built per call (`faces_ok` `:2511`; in `route_chain_walk` `enqueue` `:1615`, `exposed_key` `:1630`)
  to file-level local functions taking their upvalues as parameters;
- `route_chain_walk` reads x, y from the segment / queue entry instead of `string.match` on the key (`:1683`);
- `enqueue_state` (`:2362`): the heap node and `search.points[key]` share ONE table (today 2 tables per state).
Order of heap pops, ties, costs and every returned value must stay identical: blueprint bytes must not change.
`route.lua` main chunk top-level locals: keep total under 200 (check with `grep -c '^local' logic/bp/route.lua`).

Garbage: measure with `lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/green_tidy.lua.gz --patch
docs/tasks/r46_probes/p_garbage.lua` (prints `GARBAGE ... kb_per_step=`; base w1 = 1.31). Do NOT use
`route_prof --set all` for garbage: its timers allocate (shows 4.65).

## What to build

1. `tests/test_route_search_loop.lua`:
   - SL1 `coordinate_key` calls per search step <= 10 on `green_tidy` (use `tools/route_prof.lua ... --set all`,
     `== keys` block). Red on base (26.6).
   - SL2 resume `green_tidy.lua.gz` and `ins10_tidy2.lua.gz` to END: sha = `tests/fixtures/route_snaps/r46_digests.txt`.
   - SL3 `p_garbage` kb_per_step <= 1.0 on `green_tidy`. Red on base (1.31).
   - SL4 resume `stack1_restart27.lua.gz --until kind=route-restart`: same saved tick as base (record from base
     code first, freeze).
2. `logic/bp/route.lua` changes above.
3. Keep green: `test_route`, `test_route_improve`, `test_route_improve_waste`, `test_route_hop`,
   `test_route_hop_multi`, `test_route_hand_slide`, `test_route_ticks`, `test_route_budget`, `test_route_keys`,
   `test_route_no_replay`, `test_route_pipe_join`, `test_route_pipe_ptg_side`, `test_route_ug_exit_rear`.

## Files this lane owns

logic/bp/route.lua ONLY lines 2147-2886 (`path_cell_free` .. end of `search_step`), `route_chain_walk` (~1600-1700),
`bury_candidate` (~1760-1790) and helpers they call that live in those ranges; tests/test_route_search_loop.lua,
docs/tasks/268_route_search_inner_loop.md. Never touch anything else (another change edits route_snapshot,
append_* and improve_step).

## Commit, THEN check

Commit on `lane/268`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane268-tests", "command": "git diff --name-only round-46-w1 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_search_loop\\.lua|docs/tasks/268_route_search_inner_loop\\.md)$' | ( ! grep . ) && git diff --quiet round-46-w1 HEAD -- docs/tasks && for t in test_route_search_loop test_route test_route_improve test_route_improve_waste test_route_hop test_route_hop_multi test_route_hand_slide test_route_ticks test_route_budget test_route_keys test_route_no_replay test_route_pipe_join test_route_pipe_ptg_side test_route_ug_exit_rear test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane268-tests-ok", "expect_exit": 0, "expect_regex": "lane268-tests-ok", "timeout_s": 3000}
{"name": "lane268-fast", "command": "out=$(lua5.2 tests/test_route_search_loop.lua 2>&1); for c in SL1 SL2 SL3 SL4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane268-ok", "expect_exit": 0, "expect_regex": "lane268-ok", "timeout_s": 900}
```

# bound: 3000s
