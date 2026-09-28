# 267_route_undo_journal tidy trials and path commits roll back by journal, never by whole-state copy

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-267`, branch `lane/267`,
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

`route_snapshot` (`logic/bp/route.lua:1548`) deep-copies EVERY entity, segment (with allocations), binding and 4
maps; `restore_route_snapshot` (`:1591`) swaps them back. It is taken:
- once per path commit: `append_normal_path` `:1893` (restored only on reject);
- once per tidy trial and commit: `improve_step` `:4295` (restored `:4311`, `:4345`).
Cost grows with the sheet: 2.0 ms (green) to 12.2 ms (blue) per copy; after round-46 wave 1 it is still blue tidy
5.7 s of 21.0 s, stack1 tidy 3.5 s of 6.5 s, green tidy 0.77 s for 372 copies (legalcopilot-dev 2026-09-28).
Fix: an undo journal. While a journal is open, every change the route makes to `work.entities`,
`work.segments` (and each segment's `allocations`), `work.bindings`, `work.segments_by_cell`,
`work.entity_by_segment`, `work.underground_cells`, `work.splitter_blocked_cells`, entity / segment fields
(incl. `_route_removed`), `work.entity_serial`, `work.segment_serial` records ONE plain-data entry
(kind + target + key + old value). Rollback applies entries backwards. Commit = drop the journal.
Journal is plain data inside `work` (saved between ticks: no function, no metatable, no reference cycle
trouble — store ids / indices, not closures). Nested journals (a trial that commits a path) must work: the inner
commit folds its entries into the outer journal.

Step 1 (before editing): list EVERY mutation site of those tables/fields in `logic/bp/route.lua` (grep
`work.entities`, `work.segments`, `.allocations`, `_route_removed`, `segments_by_cell[`, `entity_by_segment[`,
`underground_cells[`, `splitter_blocked_cells[`, `work.bindings`, `entity_serial`, `segment_serial`, `table.remove`)
and put the list with line numbers in your lane report. Route all of them through small helpers
(`jset(work, tbl_kind, owner, key, value)`, `jpush`, `jremove`) that journal when a journal is open.
Other modules that mutate these tables during route (grep `logic/bp/pipe_runs.lua`, `logic/bp/beacon_prune.lua`)
run OUTSIDE trials/commits; if one runs inside, report it.

Keep `route_snapshot` / `restore_route_snapshot` for the other callers (merge trials `:4206`, pair trials
`:4360-4509`); only the 3 sites above move to the journal.

Fixtures + digests: `tests/fixtures/route_snaps/r46_digests.txt` (green_tidy, ins10_tidy2), stack1_restart27.
`lua5.2 tools/ckpt.lua resume <fixture>` prints `END ok= ticks= sha= entities=`. Profiler:
`lua5.2 tools/route_prof.lua <fixture> --until phase=validate --set coarse` (functions + trials block;
`snapshots=` = `route_snapshot` calls).

## What to build

1. `tests/test_route_journal.lua`:
   - UJ1 resume `green_tidy.lua.gz` and `ins10_tidy2.lua.gz` to END: sha = digests file values.
   - UJ2 `route_snapshot` calls during tidy of `ins10_tidy2` (to `phase=validate`) = 0 from trial + commit sites
     (count via `work.counters.route_snapshots`; merge / pair trials may still copy: assert total <= 20). Red on base.
   - UJ3 resume `stack1_restart27.lua.gz --until kind=route-restart`: same `END`/`SAVED` tick as base (2341) — record
     base value first from base code and freeze it.
   - UJ4 unit: for each refusal kind `crossing-occupied`, `splitter-footprint`, `route-discontinuous`, `capacity`,
     build a small work where `append_normal_path` refuses AFTER mutating, and assert `work` deep-equals its
     state before the call (deep compare of all tables above).
   - UJ5 nested: open journal, commit an inner path, roll back outer -> deep-equal to start.
2. `logic/bp/route.lua`: journal helpers + 3 call sites + every mutation site routed through helpers.
3. Keep green: `test_route`, `test_route_improve`, `test_route_improve_waste`, `test_route_hop`,
   `test_route_hop_multi`, `test_route_hand_slide`, `test_route_ticks`, `test_route_budget`,
   `test_route_chain_jump_commit`, `test_route_keys`, `test_route_no_replay`.

## Files this lane owns

logic/bp/route.lua EXCEPT lines 2147-2886 (search: `path_cell_free` .. `search_step`) and `route_chain_walk`
(~1600-1700) — those belong to another change; do not edit them. tests/test_route_journal.lua,
docs/tasks/267_route_undo_journal.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/267`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane267-tests", "command": "git diff --name-only round-46-w1 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_journal\\.lua|docs/tasks/267_route_undo_journal\\.md)$' | ( ! grep . ) && git diff --quiet round-46-w1 HEAD -- docs/tasks && for t in test_route_journal test_route test_route_improve test_route_improve_waste test_route_hop test_route_hop_multi test_route_hand_slide test_route_ticks test_route_budget test_route_chain_jump_commit test_route_keys test_route_no_replay test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane267-tests-ok", "expect_exit": 0, "expect_regex": "lane267-tests-ok", "timeout_s": 3000}
{"name": "lane267-fast", "command": "out=$(lua5.2 tests/test_route_journal.lua 2>&1); for c in UJ1 UJ2 UJ3 UJ4 UJ5; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane267-ok", "expect_exit": 0, "expect_regex": "lane267-ok", "timeout_s": 900}
```

# bound: 3000s
