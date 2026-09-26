# 226_run_dir row run flows toward its partner: restore the deleted run reversal as logic/bp/run_dir.lua

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-226`, branch `lane/226`,
base tag `round-39-base`, merge target `int/r39`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Never touch
`logic/bp/validate.lua` or `logic/bp/search.lua`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
`sh tools/gate_sheet.sh`. Never use `coroutine`. Plain data only. `require` only at file top level
(`tests/test_no_runtime_require.lua`). **No game item or fluid name in code** (`tests/test_no_item_names.lua`).
Every new test must FAIL on the base code (write that in the test's header comment).

## Explain very simply

Ten science machines stand in one column. Their output belt must reach the exit at the TOP of the sheet. Today the
belt always flows from the first machine (top) to the far end (bottom), so it runs down, U-turns around the beacon
column and climbs back up: 115 belts. The player's fix: same belt flowing UP, 68 belts.

Round 27 had this fix (`Groups.reverse_run`, commit 9be06db; "Choose row run directions toward flow partners",
commit e71a5da, `choose_row_runs` in search.lua). Lane 189 (0c04f1b) deleted both. The contract
`docs/contracts/row_block.md` §Reversal still describes them.

Measured (legalcopilot-dev, 2026-09-26) on a probe tree = round-39-base + that old code restored, called in
`materialize_candidate` right before `Groups.materialize`: `player-red-science-10s-bulk` → ok, **221 entities,
112 belts**, lane_sim 0/0/0; output belt x=30 all NORTH. The exact probe code is `docs/tasks/r39_probe_reference.diff`
(the `PROBE_REV` parts: `Groups.reverse_run` added to groups.lua, `choose_row_runs` added to search.lua).

## What to build

Base already calls `RunDir.choose(block, placement, blocks, placements, grid, flows, input_edge, output_edge)` in
`logic/bp/search.lua` `materialize_candidate` (identity stub in `logic/bp/run_dir.lua`). Fill it:

1. `RunDir.reverse(block, role)` = `Groups.reverse_run` from `git show 9be06db:logic/bp/groups.lua`, verbatim
   logic (mirror tiles about `row.first_x + row.last_x`, refuse when `axis + 1 ~= block.w`, flip EAST/WEST, move
   head, feeds, run port, and `row:<role>:` ports). Returns a deep copy; never mutates the input. Own local `copy`.
2. `RunDir.choose(...)` = `choose_row_runs` from `git show e71a5da:logic/bp/search.lua`, verbatim logic (as in the
   reference diff), using `RunDir.reverse`. Entry id = `entry.step_id or entry.id or entry.block_id`. Uses
   `Grid.place_port`, `Grid.dir_vector` from `logic/bp/grid.lua`.
3. `tests/test_run_dir.lua`: port `git show 9be06db:tests/test_row_reverse.lua` (RR1-RR3) onto `RunDir.reverse`,
   and `git show e71a5da:tests/test_search_run_direction.lua` (SD1-SD4) onto `RunDir.choose` (call it directly,
   same arguments). All must fail on base (stub returns block unchanged).
4. `docs/contracts/row_block.md` §Reversal: name `logic/bp/run_dir.lua` (`RunDir.reverse`, `RunDir.choose`) and
   say it runs after pack, in `materialize_candidate`.

## Files this lane owns

logic/bp/run_dir.lua, tests/test_run_dir.lua, docs/contracts/row_block.md, docs/tasks/226_run_dir.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/226`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane226-tests", "command": "git diff --name-only round-39-base HEAD | grep -Ev '^(logic/bp/run_dir\\.lua|tests/test_run_dir\\.lua|docs/contracts/row_block\\.md|docs/tasks/226_run_dir\\.md)$' | ( ! grep . ) && git diff --quiet round-39-base HEAD -- docs/tasks/226_run_dir.md && ! git diff round-39-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_run_dir test_groups_rows test_rows_integration test_red10s_bulk_delivers test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane226-tests-ok", "expect_exit": 0, "expect_regex": "lane226-tests-ok", "timeout_s": 3000}
{"name": "lane226-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s-bulk 221 112 | tail -1 | grep -q GATE-OK && echo lane226-ok", "expect_exit": 0, "expect_regex": "lane226-ok", "timeout_s": 900}
```

# bound: 2400s
