# 193 pack + power: same placements, a fraction of the work, no long tick

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-193`, branch `lane/193`,
base tag `round-30-base`, merge target `int/r30`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 45 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its tests pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), the
probe `sh tools/first_verdict.sh` (~10 s) and `lua5.2 tools/pack_placements.lua <prepared_input.json>` (red ~5 s,
green ~60 s on base). Never use `coroutine` (Factorio has none). Plain data state only (resumable across ticks).

Read `docs/contracts/round30.md` first: it is the contract. Your clause: P1.

## Explain very simply

Green science (corrected input, 54x54 grid, 2026-09-24): generation 29.17 s CPU, pack 16.17 s (4.27 s and 32556
origins per run, several runs), worst single tick 0.665 s in POWER and 0.468 s in pack (the game runs one step per
tick; anything over ~0.15 s is a visible stutter).

Pack puts each block (a group of machines) on the map, trying every origin tile of every free region and keeping
the cheapest (link distance to already-placed partners + bounding-box growth; ties by BSSF, then y, x, dir). On green (8 blocks, every port pinned so every region is fully scanned) it evaluates 32556 origins per run. Free regions are MAXIMAL rectangles, so they
overlap: the same origin is scored several times. And no origin is ever skipped even when it cannot beat the best.

Make it fast WITHOUT changing a single placement. Base answers are recorded:
`tests/fixtures/pack_base_red.txt`, `tests/fixtures/pack_base_green.txt` (lines `PLACE ...`, from
`lua5.2 tools/pack_placements.lua tests/golden/cases/<case>/prepared_input.json`). Your output lines `PLACE ...`
must be identical.

## Where the code is (`logic/bp/pack.lua`, ~677 lines)

`PORT_ORIGIN_OPS` ~24, `prune_regions` ~126, `port_tile` ~304, `linked_cost` ~317, `choose_port_slots` ~350
(backtracking), `scan_origin` ~417 (zones, blockers, port cells, BSSF, slots, link cost, `better`), `scan_one` ~445
(origin cursor; a region's non-corner origins are scanned only when `pinned_failed`), `region_can_beat` ~487
(returns true whenever links exist: no pruning at all), `place` ~504 (unbudgeted: subtract + `prune_regions` +
`rebuild_indexes`), `Pack.step` ~638.

## What to build (all exact; placements must not change)

1. Evaluate each (block, dir, x, y) once per block; when an origin lies in several regions, its BSSF is the best
   (lowest short, then long) over those regions, so `better` sees what it saw before.
2. Admissible cut with links: lower bound for a region/origin = sum over this block's links whose partner is placed
   or is an edge, of the Manhattan distance from the partner's port tile (or the edge line) to the candidate rect
   grown by 1 tile (a port may sit one tile outside its block), + bbox growth lower bound (growth to include the
   region's nearest possible rect; 0 is allowed). Skip only when bound > best cost (strict).
3. Order: cheapest checks first in `scan_origin` (bound, then zone fit/blockers, then port cells, then
   `choose_port_slots`).
4. Charge `place()` work to `budget.ops` (e.g. ops proportional to regions touched) so one tick at 2000 ops stays
   bounded. POWER (`logic/bp/power.lua`): find the unbudgeted work behind the 0.665 s tick (profile:
   `lua5.2 ~/.claude/plans/rrc-round-22-probes/profile.lua tests/golden/cases/player-green-science-1s/prepared_input.json`)
   and charge it to `budget.ops` / split it across steps; pole choice must not change (red + green entity output
   identical: compare `sh tools/measure_sheet.sh` entity counts and `bytes` before/after).
5. Tests, red at `round-30-base` first:
   - new `tests/test_pack_same_answer.lua`: capture the green `Pack.begin` input (write a small capture probe,
     commit the captured input as `tests/fixtures/pack_green_input.lua`, plain data) and assert the placements
     equal `tests/fixtures/pack_base_green.txt`; runs in a few seconds after your change.
   - new `tests/test_pack_speed.lua`: on that fixture, `state.counters.origins` (origins actually evaluated)
     `<= 69151` (25% of 276607).
   - keep `tests/test_pack.lua`, `test_pack_budget.lua`, `test_pack_buffer.lua`, `test_pack_links.lua`,
     `test_pack_zone_blockers.lua` green (update `test_pack_budget.lua` only if op accounting changes a number; say
     why in the commit).
6. Measure: `lua5.2 tools/pack_placements.lua` on both golden inputs: PLACE lines identical to the fixtures; green
   `PACK-CPU` <= 2 (base 4.27), red `PACK-CPU` <= 3.96 (base); profile worst tick in pack and power <= 0.15 s on
   both sheets.

## Checks (lua5.2 only, one file at a time)

`test_pack_same_answer test_pack_speed test_pack test_pack_budget test_pack_buffer test_pack_links
test_pack_zone_blockers`, then `sh tools/first_verdict.sh`, then the placement comparison.

## Files this lane owns

`logic/bp/pack.lua`, `logic/bp/power.lua`, `tests/test_pack_same_answer.lua`, `tests/test_pack_speed.lua`,
`tests/fixtures/pack_green_input.lua`, `tests/test_pack_budget.lua`, `tests/test_power_budget.lua`, `tests/test_power_ops.lua` (update only if op accounting changes a number; say why).

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/contracts/**`,
`tests/fixtures/pack_base_*.txt`, nor any test file not listed here.

## Commit, THEN check

Commit on `lane/193` with both PACK-CPU lines and the worst step time in the message. **Run the checks below as the
very LAST action.**

## What done mean

```checks
{"name": "lane193-tests", "command": "git diff --name-only round-30-base HEAD | grep -v '^docs/tasks/193' | grep -Ev '^(logic/bp/pack\\.lua|logic/bp/power\\.lua|tests/test_power_budget\\.lua|tests/test_power_ops\\.lua|tests/test_pack_same_answer\\.lua|tests/test_pack_speed\\.lua|tests/fixtures/pack_green_input\\.lua|tests/test_pack_budget\\.lua)$' | ( ! grep . ) && ! git diff round-30-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_pack_same_answer test_pack_speed test_pack test_pack_budget test_power test_power_make_room test_power_budget test_power_ops test_pack_buffer test_pack_links test_pack_zone_blockers; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane193-tests-ok", "expect_exit": 0, "expect_regex": "lane193-tests-ok", "timeout_s": 900}
{"name": "lane193-same-answer", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && lua5.2 tools/pack_placements.lua tests/golden/cases/player-red-science-1s/prepared_input.json > /tmp/rrc193-red.txt && lua5.2 tools/pack_placements.lua tests/golden/cases/player-green-science-1s/prepared_input.json > /tmp/rrc193-green.txt && grep ^PLACE tests/fixtures/pack_base_red.txt > /tmp/rrc193-red-base.txt && grep ^PLACE /tmp/rrc193-red.txt | diff /tmp/rrc193-red-base.txt - && grep ^PLACE tests/fixtures/pack_base_green.txt > /tmp/rrc193-green-base.txt && grep ^PLACE /tmp/rrc193-green.txt | diff /tmp/rrc193-green-base.txt - && grep PACK-CPU /tmp/rrc193-red.txt /tmp/rrc193-green.txt && awk '/PACK-CPU/ {exit !($2 <= 2)}' /tmp/rrc193-green.txt && awk '/PACK-CPU/ {exit !($2 <= 3.96)}' /tmp/rrc193-red.txt && echo lane193-same-answer-ok", "expect_exit": 0, "expect_regex": "lane193-same-answer-ok", "timeout_s": 600}
```

# bound: 3000s
