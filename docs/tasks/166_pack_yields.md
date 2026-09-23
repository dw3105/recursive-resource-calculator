# 166 pack: a pack step yields within its ops and scans by index, not by list

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-166`, branch
`lane/166`, base tag `round-23-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-23-base`.

## You have about 35 minutes — do NOT stop early

**Do not end your turn until every item under "What to build" exists, is committed, and both checks have
run.** Stopping with uncommitted work is a failed lane. If one item is truly blocked, commit everything
else, then say which item and why.

## Explain very simply

The player clicked "generate" in Factorio 2.0.77 on 2026-09-23. After 10 minutes it was still
calculating and the game ran at 3 UPS the whole time. The game advances a blueprint search once per tick
with a budget of 2000 ops (`Jobs.OPS_PER_TICK`, `logic/jobs.lua`). A tick must stay short (a frame is
16.7 ms). Some steps do seconds of work inside ONE call and never give the tick back.

`tools/speed_probe.sh` replays the player's sheet exactly as the game does (2000 ops per `Search.step`) and
times every `begin`/`step` of each `logic/bp` module. `tools/speed_gate.sh` turns its output into a
pass/fail line. Measured at `round-23-base` on legalcopilot-dev 2026-09-23, `CAP=40`:

```
pack.step     worst 8.157 s   (4 calls, 18.3 s)
route.begin   worst 1.340 s   (4 calls, 4.2 s)
route.step    worst 0.783 s   (25 calls, 6.6 s)
groups.begin  worst 0.611 s
power.step    416 calls per power.begin (about 830k ops per candidate), worst 0.016 s
```

The rule for every module: **one op costs a few microseconds**, so 2000 ops fit in about 20 ms. A long
loop checks the budget and returns; the next call resumes from a cursor stored on the state.

The result must not change. `tests/fixtures/blueprints/round22_v5.txt` is the player's accepted blueprint
(v5, 242 entities, placed in game 2026-09-23).

## Where the code is

`logic/bp/pack.lua`. `Pack.step` spends ONE op per free region and calls `scan_region` on it. For a block
with a pinned port, `scan_region` then tries EVERY origin `(x, y)` of the region, and each `try` calls
`choose_port_slots`, which calls `cell_is_free` for every slot option. `cell_is_free` walks the whole
`state.port_cells` list and the whole `state.regions` list; `placement_avoids_port_cells` walks
`state.port_cells` again. So one op can mean thousands of origins times list walks: 8.157 s in one call.

## What to build

1. **Resumable scan.** Keep the scan position (direction, origin x/y, needs_offset) on `state.cursor`;
   spend one op per origin tried (or per small constant chunk), and return when `budget.ops` hits 0.
   The next call resumes exactly there. The origin order, the `better` comparison, and therefore the chosen
   placement must be identical to today.
2. **Index lookups.** Build a set keyed by cell for `port_cells` and a fast way to answer
   "is (x, y) inside a free region" (for example a cell set rebuilt when `regions` change), so
   `cell_is_free` and `placement_avoids_port_cells` stop walking lists.
3. `tests/test_pack_budget.lua` (new), each row **red at `round-23-base`**:
   - **PB1** a pinned-port block in a large region: `Pack.step` with `{ops = 50}` returns with the budget
     spent and `state.done == false`, and no single call exceeds 50 ops of scanning (count origins tried
     via a counter on state).
   - **PB2** packing the same input with budget 1 per call and with budget 10^9 gives identical
     `placements` (x, y, dir, port_slots).
4. Report `CAP=40 sh tools/speed_probe.sh` before and after, and the final product line.

## Traps

- **Determinism.** Same input, same layout: `tests/test_route_budget.lua`, `coord_key`. A cursor that
  resumes must visit exactly the same things in exactly the same order as the one-shot loop did.
- **Every budget size gives the same answer.** Run your module's tests with a budget of 1 op and of a huge
  budget; results must be identical.
- **Measure with the probe, not the full product.** `CAP=40 sh tools/speed_probe.sh` takes about 40 s;
  `sh tools/round21_product.sh` takes about 200 s — run it once, at the end, alone. Never run two long
  commands at the same time (the host wedged 2026-09-23 when two ran together).
- **Never touch** `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except
  this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/pack.lua`, `tests/test_pack_budget.lua`

## Commit, THEN check

Commit on `lane/166` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "pack-regress", "command": "git diff --name-only round-23-base HEAD | grep -v '^docs/tasks/166' | grep -Ev '^(logic/bp/pack\\.lua|tests/test_pack_budget\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_pack_budget.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo pack-regress-ok", "expect_exit": 0, "expect_regex": "pack-regress-ok", "timeout_s": 1800}
{"name": "pack-speed", "command": "CAP=60 sh tools/speed_probe.sh > /tmp/rrc166-speed.txt; cat /tmp/rrc166-speed.txt; sh tools/speed_gate.sh worst pack.step 0.03 < /tmp/rrc166-speed.txt && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1 && python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && cmp $d/bp.txt tests/fixtures/blueprints/round22_v5.txt && echo pack-speed-ok", "expect_exit": 0, "expect_regex": "pack-speed-ok", "timeout_s": 1500}
```

# bound: 2400s
