# 186 pack: roboport-free buffer zones and placement near trade partners

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-186`, branch `lane/186`,
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

Pack puts blocks on the grid. Today it picks the tightest free corner (BSSF) and knows nothing about which block
feeds which. The player wants each block near the blocks it trades with, raw inputs near the input edge, products
near the output edge, small total area. And no roboport may stand inside a machine's buffer zone.

## Where the code is

`logic/bp/pack.lua` (585 lines): `Pack.begin` (~520), `scan_origin` (~352: `rotate_buffer_zones`,
`buffer_zones_fit`, `choose_port_slots`, `better`), `scan_one`, `region_can_beat` (~437), `place` (~450),
`Pack.bssf_score`. `copy_port` carries `attach_dx/attach_dy`. Budget constant `PORT_ORIGIN_OPS` (~24).

## What to build

1. C2: `Pack.begin{zone_blockers = {TileRect}}`; an origin whose rotated zones intersect any blocker is skipped.
2. C3: `Pack.begin{links = {...}}` cost = link distances to placed partners / edges + bounding-box growth; tie ->
   BSSF -> y -> x -> direction. `region_can_beat` must not wrongly skip a region when links are present (skip the
   prune, or use a correct lower bound). No links -> today's result byte for byte.
3. Keep one op near 8 µs: never loop over all links per origin more than once; precompute partner tiles per block.
4. Tests, red at `round-29-base` first:
   - new `tests/test_pack_zone_blockers.lua`: a machine block whose zone would touch a blocker at the only tight
     spot is placed elsewhere; with no room at all -> `BP_P_NO_FIT`.
   - new `tests/test_pack_links.lua`: A feeds B; B placed next to A's output side, not in the far corner BSSF picks;
     a block linked to edge `left` lands at the left; a block whose port faces its partner only when turned gets
     turned (all `allowed_dirs` tried); no links -> same placements as today.

## Checks (lua5.2 only, one file at a time)

`tests/test_pack_zone_blockers.lua`, `tests/test_pack_links.lua`, `tests/test_pack.lua`, `tests/test_pack_buffer.lua`, `tests/test_pack_budget.lua`, then `sh tools/first_verdict.sh` (must print `ok=true`), then the
measure command (must print `LANE-SIM mixed=0`).

## Files this lane owns

`logic/bp/pack.lua`, `tests/test_pack_zone_blockers.lua`, `tests/test_pack_links.lua`, `tests/test_pack.lua`, `tests/test_pack_buffer.lua`, `tests/test_pack_budget.lua`

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
`docs/contracts/pipeline_r29.md`, nor any test file not listed here. A test file listed here that tests code you
deleted is deleted or rewritten by you.

## Commit, THEN check

Commit on `lane/186` with the measured entity count in the message. **Run the two checks below as the very LAST
action.**

## What done mean

```checks
{"name": "lane186-tests", "command": "git diff --name-only round-29-base HEAD | grep -v '^docs/tasks/186' | grep -Ev '^(logic/bp/pack\\.lua|tests/test_pack_zone_blockers\\.lua|tests/test_pack_links\\.lua|tests/test_pack\\.lua|tests/test_pack_buffer\\.lua|tests/test_pack_budget\\.lua)$' | ( ! grep . ) && ! git diff round-29-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_pack_zone_blockers test_pack_links test_pack test_pack_buffer test_pack_budget; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane186-tests-ok", "expect_exit": 0, "expect_regex": "lane186-tests-ok", "timeout_s": 1500}
{"name": "lane186-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc186-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc186-first.txt && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E '^  (entities|belts) ' | tee /tmp/rrc186-measure.txt; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1 | grep -q 'mixed=0' && echo lane186-probe-ok", "expect_exit": 0, "expect_regex": "lane186-probe-ok", "timeout_s": 600}
```

# bound: 2400s
