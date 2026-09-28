# 267b_route_undo_journal_sites tidy trials and path commits roll back by an undo journal, every mutation site converted

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-267b`, branch `lane/267b`,
base tag `round-46-w1b`, merge target `int/r44`. Host `legalcopilot-dev`.

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

## An earlier attempt was NOT accepted — read why

It added journal helpers only: no call site converted, `route_snapshot` still ran on every trial, tests read text
files instead of running the router, and its target lookup scanned every entity per change. This attempt must
convert EVERY site listed below and prove it by running the router on the fixtures.

## Explain very simply

`route_snapshot` (`logic/bp/route.lua:1549`) deep-copies every entity, segment (with allocations), binding and 4
maps; `restore_route_snapshot` (`:1592`) swaps them back. Copies cost 2.0 ms (green) to 12.2 ms (blue) each
(legalcopilot-dev 2026-09-28). Three sites move to an undo journal:
- `append_normal_path` `:1900` (commit point of one path; restored only on reject);
- `improve_step` `:4327` (`st.snapshot = route_snapshot(work)` at trial_start / commit_start), restored at `:4343`
  (trial_end) and `:4377` (commit_end, not kept).
Other `route_snapshot` callers (merge trials, pair trials ~`:4238`, `:4396`-`:4545`) stay as they are.

DESIGN (use exactly this — simple and O(1) per change):
- `work.journal` = nil when closed, else a list of frames; a frame is a list of entries.
- Entry = `{t = <the table changed>, k = <key>, old = <old value>, had = <old ~= nil>}` — a DIRECT reference to the
  changed table. That is plain data: Factorio `storage` and `tools/lib/graph_dump.lua` keep shared table refs.
  No function, no metatable, no string path lookup, no scan.
- `local function jset(work, t, k, v)`: if a frame is open, push entry (only when `t[k] ~= v`); then `t[k] = v`.
- `jinsert(work, t, v)` = `jset(work, t, #t + 1, v)`; `jremove(work, t, i)` = series of `jset` shifting down, then
  `jset(work, t, #t, nil)` (or record `{op="remove", t, i, v}` and undo with `table.insert`; your choice, both exact).
- `journal_open(work)`, `journal_rollback(work)` (apply newest frame backwards, pop), `journal_commit(work)`
  (pop; if a parent frame exists append the entries to it, so an inner commit is undone by an outer rollback).
- Snapshot also stored `entity_serial` / `segment_serial`: set them through `jset(work, work, "entity_serial", n)`.

EVERY mutation site of these must go through jset/jinsert/jremove: `work.entities`, `work.segments`,
`work.bindings`, each segment's `allocations`, `work.segments_by_cell`, `work.entity_by_segment`,
`work.underground_cells`, `work.splitter_blocked_cells`, whole-table replacement of any of those
(`work.segments_by_cell = {...}`), any field of an entity / segment / binding / allocation (`_route_removed`,
`direction`, `fixed`, `flow_ids`, ...), `work.entity_serial`, `work.segment_serial`. Lines in
`logic/bp/route.lua` found by grep at base (115 lines, NOT complete for field sets on entity / segment locals —
grep those too, e.g. `^\s*[a-z_]+\.[a-z_]+ *= ` where the local holds an entity / segment / binding):
161 166 1189 1190 1191 1192 1359 1364 1397 1403 1406 1410 1467 1525 1526 1527 1529 1530 1531 1532 1533 1539 1540 1571 1593 1594 1597 1600 1601 1602 1630 1854 1860 1867 1868 1869 1870 1871 1873 1875 1876 1877 1885 2063 2073 2074 2075 2076 2093 2135 2136 2137 2138 2139 2140 2143 2144 2147 2738 2770 2936 2942 2947 2952 2958 2963 2968 3029 3030 3042 3043 3108 3163 3165 3166 3167 3168 3169 3170 3173 3179 3185 3186 3187 3188 3340 3380 3381 3382 3393 3394 3395 3748 3751 3753 3760 3761 3764 3798 3799 3801 3802 3803 3804 3811 3815 3816 3817 3818 3894 3895 3898 3900 3901 3902 
`logic/bp/pipe_runs.lua:243-244` pushes to `work.entities`: find whether it can run inside an open frame (route
`result_for` / tidy); if it can, route it through an exported `Route._jinsert` or report it.
When no frame is open, jset costs one table read + the assignment — first routing stays as fast as today.

## What to build

1. `tests/test_route_journal2.lua`:
   - JN1 resume `green_tidy.lua.gz` and `ins10_tidy2.lua.gz` to END with `tools/ckpt.lua resume`: `sha=` equals
     `tests/fixtures/route_snaps/r46_digests.txt`.
   - JN2 resume `ins10_tidy2.lua.gz --until phase=validate --save <tmp>`, load with
     `require("tools.lib.graph_dump").load(tmp).state.work.route_state.counters` (or where `route_snapshots`
     lives): `route_snapshots` <= 20 (base: hundreds). Red on base.
   - JN3 resume `stack1_restart27.lua.gz --until kind=route-restart`: same `END ... ticks=` as base code (run base
     first, freeze the number in the test).
   - JN4 unit: for each refusal `crossing-occupied`, `splitter-footprint`, `route-discontinuous`, `capacity` build a
     small work where `append_normal_path` refuses AFTER mutating; assert work deep-equals a deep copy taken
     before the call (entities, segments incl. allocations, bindings, 4 maps, serials). Export what you need via
     `Route._test`.
   - JN5 nested: open, change, open, change, commit inner, rollback outer -> deep-equal to start.
   - JN6 source guard: in `logic/bp/route.lua`, outside the journal helper bodies, no raw assignment matches the
     grep pattern above (`work.entities[...] =`, `segments_by_cell[...] =`, `._route_removed =`, `.allocations[...] =`,
     `table.insert(work.entities`, ...). Red on base.
2. `logic/bp/route.lua`: helpers + 3 sites + every mutation site.
3. Keep green: `test_route`, `test_route_improve`, `test_route_improve_waste`, `test_route_hop`, `test_route_hop_multi`,
   `test_route_hand_slide`, `test_route_ticks`, `test_route_budget`, `test_route_chain_jump_commit`, `test_route_keys`,
   `test_route_no_replay`, `test_route_search_loop`, `test_route_pipe_join`, `test_pipe_runs`.

## Files this lane owns

logic/bp/route.lua, logic/bp/pipe_runs.lua (ONLY lines 240-246 if needed), tests/test_route_journal2.lua,
docs/tasks/267b_route_undo_journal_sites.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/267b`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane267b-tests", "command": "git diff --name-only round-46-w1b HEAD | grep -Ev '^(logic/bp/route\\.lua|logic/bp/pipe_runs\\.lua|tests/test_route_journal2\\.lua|docs/tasks/267b_route_undo_journal_sites\\.md)$' | ( ! grep . ) && git diff --quiet round-46-w1b HEAD -- docs/tasks && for t in test_route_journal2 test_route test_route_improve test_route_improve_waste test_route_hop test_route_hop_multi test_route_hand_slide test_route_ticks test_route_budget test_route_chain_jump_commit test_route_keys test_route_no_replay test_route_search_loop test_route_pipe_join test_pipe_runs test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane267b-tests-ok", "expect_exit": 0, "expect_regex": "lane267b-tests-ok", "timeout_s": 3000}
{"name": "lane267b-fast", "command": "out=$(lua5.2 tests/test_route_journal2.lua 2>&1); for c in JN1 JN2 JN3 JN4 JN5 JN6; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane267b-ok", "expect_exit": 0, "expect_regex": "lane267b-ok", "timeout_s": 900}
```

# bound: 3000s
