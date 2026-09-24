# 185 groups: one group per machine kind, ring bump, far belt with long hands

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-185`, branch `lane/185`,
base tag `round-29-base`, merge target `int/r29`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 45 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its tests pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), the
probe `sh tools/first_verdict.sh` (~10 s) and the measure command below (~60 s). Never use `coroutine` (Factorio has
none). Plain data state only (the job is resumable across game ticks).

Read `docs/contracts/pipeline_r29.md` first: it is the contract. Your clauses are named below; code EXACTLY the
field names it gives, other lanes code against the same names.

## Measure (player's real sheet)

Base (`round-29-base`) prints `entities 174` and `LANE-SIM mixed=0`. You must still print `LANE-SIM mixed=0`; put the
printed entity count in your last commit message.

```sh
d=$(mktemp -d); lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E "^  (entities|belts) "; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1
```

## Explain very simply

Today `Groups` offers up to 128 candidate layouts (every way to split steps into blocks, rows and not-rows) and the
search tries them all. The player wants ONE: all machines of one recipe on one machine type are one group. A group of
2+ machines is a row (`docs/contracts/row_block.md`). Rings can be made wider for a retry (`ring_bump`). A recipe
with 3-4 item inputs gets a second belt behind the first on the input face, read by long-handed inserters; 5-6 inputs
get one more far belt behind the output belt.

## Where the code is

`logic/bp/groups.lua`:
- `make_candidates_once` (~line 1986) and `make_candidates` (~2084): enumeration, fragment split (~2005-2034),
  `partition_specs` (~1877), `rows_enabled` switch.
- `build_block` (~996); row hands (~1435-1457, hard-coded hand at `machine.y-1` / `machine.y+h`); buffer zones
  (~1847-1873, `Buffer.ring(catalog, step.recipe)` at ~1857).
- `step_can_join` (~260) is the group key. `inserter_offsets` (~310) reads catalog offsets.
- Row contract `docs/contracts/row_block.md`, fixture `tests/fixtures/row_block.lua`.
- Keep `Groups.reverse_run` and `Groups.materialize` working (the search still calls them on this base).

## What to build

1. C4: `Groups.step` returns exactly one candidate, id `"one"`, `candidate_id = "one"`; delete `partition_specs`,
   the rows/legacy double pass, `max_candidates` truncation. One group per `step_can_join` key; row form when 2+
   machines, item outputs <= 1, item inputs <= 6; else today's block form, keeping the fragment split only for a
   non-row multi-machine step with more than 2 distinct item flows.
2. C1: every ring is `Buffer.ring(catalog, recipe) + (input.ring_bump or 0)`; the in-block assert still holds for
   bumped rings (row neighbours share rings, row rule unchanged).
3. C4 far belts: 3-4 item inputs -> far in-run on the input face one tile beyond the near in-run (`far = true`,
   own head/feeds like the near run), second input hand per machine `long = true`, `name` from
   `catalog.long_inserter` (fallback `"long-handed-inserter"`), offsets from `catalog.long_inserter` (fallback
   pickup `{x=0,y=2}`, drop `{x=0,y=-2}`), at another column of the face than the plain hand. 5-6 -> far run
   beyond the output run, long hand on the output face. 7+ -> `BP_P_NO_FIT` `row-inputs`. Grow the block envelope
   and ports so `Groups.materialize` carries the far runs and long hands (rotations too). Update
   `docs/contracts/row_block.md` (new section "Far belt") and `tests/fixtures/row_block.lua` if its shape changes.
4. Tests, red at `round-29-base` first:
   - new `tests/test_groups_one.lua`: player-like plan (two steps x N machines, one recipe each) -> exactly one
     candidate `"one"`, one block per step; `ring_bump = 1` widens every `buffer_zones[i].ring` by 1.
   - new `tests/test_groups_long_hands.lua`: 3 machines of a 3-input recipe -> one row, two in-runs (one `far`),
     3 plain + 3 long input hands, long pickup on a far-run tile, drop inside its machine; 5 inputs -> far run on
     output face; 7 inputs -> `row-inputs` failure. Uses a catalog with `long_inserter` facts AND one without
     (fallback).
   - update the other listed tests that counted candidates.

## Checks (lua5.2 only, one file at a time)

`tests/test_groups_one.lua`, `tests/test_groups_long_hands.lua`, `tests/test_groups.lua`, `tests/test_groups_rows.lua`, `tests/test_groups_buffer.lua`, `tests/test_hand_economy.lua`, `tests/test_inserter_geometry.lua`, `tests/test_beacon_coverage.lua`, `tests/test_rows_integration.lua`, `tests/test_row_reverse.lua`, then `sh tools/first_verdict.sh` (must print `ok=true`), then the
measure command (must print `LANE-SIM mixed=0`).

## Files this lane owns

`logic/bp/groups.lua`, `docs/contracts/row_block.md`, `tests/fixtures/row_block.lua`, `tests/test_groups_one.lua`, `tests/test_groups_long_hands.lua`, `tests/test_groups.lua`, `tests/test_groups_rows.lua`, `tests/test_groups_buffer.lua`, `tests/test_hand_economy.lua`, `tests/test_inserter_geometry.lua`, `tests/test_beacon_coverage.lua`, `tests/test_rows_integration.lua`

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
`docs/contracts/pipeline_r29.md`, nor any test file not listed here. A test file listed here that tests code you
deleted is deleted or rewritten by you.

## Commit, THEN check

Commit on `lane/185` with the measured entity count in the message. **Run the two checks below as the very LAST
action.**

## What done mean

```checks
{"name": "lane185-tests", "command": "git diff --name-only round-29-base HEAD | grep -v '^docs/tasks/185' | grep -Ev '^(logic/bp/groups\\.lua|docs/contracts/row_block\\.md|tests/fixtures/row_block\\.lua|tests/test_groups_one\\.lua|tests/test_groups_long_hands\\.lua|tests/test_groups\\.lua|tests/test_groups_rows\\.lua|tests/test_groups_buffer\\.lua|tests/test_hand_economy\\.lua|tests/test_inserter_geometry\\.lua|tests/test_beacon_coverage\\.lua|tests/test_rows_integration\\.lua)$' | ( ! grep . ) && ! git diff round-29-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_one test_groups_long_hands test_groups test_groups_rows test_groups_buffer test_hand_economy test_inserter_geometry test_beacon_coverage test_rows_integration test_row_reverse; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane185-tests-ok", "expect_exit": 0, "expect_regex": "lane185-tests-ok", "timeout_s": 1500}
{"name": "lane185-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc185-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc185-first.txt && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E '^  (entities|belts) ' | tee /tmp/rrc185-measure.txt; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1 | grep -q 'mixed=0' && echo lane185-probe-ok", "expect_exit": 0, "expect_regex": "lane185-probe-ok", "timeout_s": 600}
```

# bound: 3000s
