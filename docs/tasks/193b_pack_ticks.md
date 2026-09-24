# 193b pack: same bytes, less work, no long tick

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-193b`, branch `lane/193b`,
base tag `round-30b-base`, merge target `int/r30b`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and the
tools named below. Never use `coroutine` (Factorio has none). Plain data state only (resumable across game ticks).
Every unit test you write must finish in under 20 s.

## Same answer, byte for byte

Generation is deterministic. `tests/fixtures/bytes_round30.txt` holds the sha256 of the delivered blueprints
(red v11, green v1). After your change `sh tools/bytes_hash.sh player-red-science-1s` and
`sh tools/bytes_hash.sh player-green-science-1s` must print the SAME lines. You change HOW MUCH work one step does,
never WHAT it decides.

## Measure

`sh tools/tick_profile.sh <case>` prints per-phase CPU and worst single tick (the game runs one `Search.step` with
2000 ops per tick; anything over ~0.1 s is a visible stutter). Base on green (2026-09-24, legalcopilot-dev): total
15.69 s, pack 8.83 s worst 0.337 s, power 2.04 s worst 0.496 s, route 3.63 s worst 0.217 s.

## Explain very simply

Pack places each block (group of machines) on the map. It tries every origin tile of every free region and keeps
the cheapest (link distance to placed partners + bounding-box growth; ties by BSSF, then y, x, dir). Free regions are
MAXIMAL rectangles, so they overlap: the same origin is scored several times. When links exist, `region_can_beat`
(~487) returns true, so nothing is ever cut. `place()` (~504: subtract, `prune_regions`, `rebuild_indexes`) runs with
no budget at all, which is where a single tick can run long.

A first attempt timed out; its diff is in `docs/tasks/193b_wip_reference.diff` (read it, do not copy blindly). Its
known faults:
- it set `PORT_ORIGIN_OPS` to 512 (one op then does ~32x more work: longer ticks, the opposite of the goal);
- an origin cut by the bound was cached as `pinned_failed = true`, which makes `scan_one` fall into a full-region
  scan: a cut must never turn on the full scan;
- its unit test ran over 300 s.

## What to build (`logic/bp/pack.lua` only)

1. Evaluate each (block, dir, x, y) once per block; if an origin lies in several regions, it keeps the best BSSF over
   those regions (same tie order as today).
2. Admissible cut when links exist: lower bound = sum over this block's links with a placed partner or an edge of the
   Manhattan distance from the partner port tile / edge line to the candidate rect grown by 1, plus bbox growth; skip
   only when bound > best cost (strict). A cut origin is "not better", never "pinned failed".
3. Cheapest checks first in `scan_origin`.
4. Bound every tick: make `place()` resumable (split subtract / prune / rebuild across steps and charge ops), keep
   `PORT_ORIGIN_OPS` so one op stays ~8 us.
5. Tests (red at base first, each < 20 s): new `tests/test_pack_ticks.lua`: on a synthetic 54x54 input with 8 pinned
   blocks and links, (a) placements equal a reference run of the same input with the cut disabled (expose a test-only
   switch), (b) evaluated origins <= 50% of the uncut run, (c) no single `Pack.step(state, {ops = 2000})` exceeds
   0.05 s (os.clock). Keep `test_pack.lua`, `test_pack_budget.lua`, `test_pack_buffer.lua`, `test_pack_links.lua`,
   `test_pack_zone_blockers.lua` green (update `test_pack_budget.lua` numbers only if op accounting changes; say why).

## Done (targets)

Bytes identical on both sheets; `lua5.2 tools/pack_placements.lua tests/golden/cases/player-green-science-1s/prepared_input.json`
`PACK-CPU` <= 2.0 (base 3.85); `sh tools/tick_profile.sh` pack worst tick <= 0.10 s on both sheets.

## Files this lane owns

`logic/bp/pack.lua`, `tests/test_pack_ticks.lua`, `tests/test_pack_budget.lua`.
Never touch anything else.

## Commit, THEN check

Commit on `lane/193b` with PACK-CPU and both pack worst ticks in the message. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane193b-tests", "command": "git diff --name-only round-30b-base HEAD | grep -v '^docs/tasks/193b' | grep -Ev '^(logic/bp/pack\\.lua|tests/test_pack_ticks\\.lua|tests/test_pack_budget\\.lua)$' | ( ! grep . ) && ! git diff round-30b-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_pack_ticks test_pack test_pack_budget test_pack_buffer test_pack_links test_pack_zone_blockers; do timeout 120 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane193b-tests-ok", "expect_exit": 0, "expect_regex": "lane193b-tests-ok", "timeout_s": 900}
{"name": "lane193b-same-and-fast", "command": "sh tools/bytes_hash.sh player-red-science-1s > /tmp/r193b.txt && sh tools/bytes_hash.sh player-green-science-1s >> /tmp/r193b.txt && diff tests/fixtures/bytes_round30.txt /tmp/r193b.txt && lua5.2 tools/pack_placements.lua tests/golden/cases/player-green-science-1s/prepared_input.json | tail -1 | awk '{exit !($2 <= 2.0)}' && for c in player-red-science-1s player-green-science-1s; do sh tools/tick_profile.sh $c | awk '$1 == \"pack\" {print; exit !($NF <= 0.10)}' || { echo SLOW $c; exit 1; }; done && echo lane193b-ok", "expect_exit": 0, "expect_regex": "lane193b-ok", "timeout_s": 900}
```

# bound: 3600s
