# 189 search: one straight pipeline with retry, hands as their own step

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-189`, branch `lane/189`,
base tag `round-29-mid` (groups, pack, route and power already speak the contract), merge target `int/r29`.
Host `legalcopilot-dev`.

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

Round 28 (v9) printed `entities 174` and `LANE-SIM mixed=0`. You must print `LANE-SIM mixed=0` AND `entities` <= 191; put the
printed entity count in your last commit message.

```sh
d=$(mktemp -d); lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E "^  (entities|belts) "; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1
```

## Explain very simply

Today `search.lua` builds many layouts (candidates x orderings x grids, then flip trials) and keeps the best by a
comparator. The player wants ONE layout built in fixed steps: groups -> pack -> route -> hands -> power -> tidy ->
validate. Invalid -> redo from groups with every buffer ring 1 wider (`ring_bump`), at most 2 retries. On this base,
Groups already returns one candidate; Pack takes `zone_blockers` and `links`; Route takes `tidy = false` and offers
`Route.tidy_begin/tidy_step/free_cell`; Power takes `make_room`. You wire them (contract C8, C9) and delete the old
search machinery.

## Where the code is

`logic/bp/search.lua` (~1890 lines): `PHASES` (~23), constants (~153-160: `CANDIDATE_ALLOWANCE`,
`NO_IMPROVEMENT_LIMIT`, `MAX_LAYOUTS`, `MAX_FLIP_TRIALS`), `ordered_grid_specs` (~169), `roboport_obstacles` (~277),
`candidate_orders` (~326), `materialize_candidate` (~417), `offer_hand_slides` (~453), `apply_hand_slides` (~499),
`occupied_rects` (~647), `make_power_input` (~663), `perimeter_roboport_clearance` (~1057), `make_route_input`
(~1076), `make_candidate` (~1187), `start_grid` (~1288), `next_grid` (~1309), `declare_allowance` (~1432),
`stop_no_improvement` / `flip_trial_stops_search` / `publish_interim` (~1454-1470), `finish_grid_or_search`
(~1525), `queue_candidate_flips` (~1559), `prepare_candidate` (~1590), `discard_candidate` (~1628), `Search.step`
(~1650). `Groups.reverse_run` in `logic/bp/groups.lua` (~2155, used only by flip trials: delete it).
Generation reads `search.interim` only if present (`logic/bp/generation.lua` ~1176): leave generation alone.

## What to build

1. C8: new `logic/bp/hands.lua` with `Hands.offer_slides`, `Hands.place`, `Hands.free_cell` (move the two slide
   functions out of search.lua; `place` applies `port_slides` and returns the layout's inserter entities).
2. C9 stage machine: plan -> preflight -> groups -> pack -> route -> hands -> power -> tidy -> validate ->
   serialize; attempt 0..2 with `ring_bump = attempt` into Groups and Validate input; pack `BP_P_NO_FIT` -> next
   grid same attempt; any later failure -> next attempt from groups; attempt 2 fails -> `BP_FAIL_NO_LAYOUT`
   (register nothing new if the code exists; check `reason_codes.lua`) with every rejection in
   `errors[1].reason_details`. Keep op budgeting per tick, `Search.cancel`, progress phases, diagnostics
   (`search_diagnostics`) meaningful.
3. Pack input: `zone_blockers` = roboport rects; `links` built from flows (producer out port -> consumer in port,
   raw-input ports -> `input_edge`, product ports -> `output_edge`, edges from settings as today). Route input
   `tidy = false`. Power input `make_room(x, y)` = `Route.free_cell(route_state, x, y) or Hands.free_cell(...)` and
   `occupied[i].kind`. Tidy: `Route.tidy_begin(route_state, {obstacles = pole rects})`; after tidy, if a hand slid
   out of pole cover, rerun Power once.
4. Delete: orderings (keep only the greedy connectivity order), flip queue and `MAX_FLIP_TRIALS`, comparator loop and
   incumbent replacement, `NO_IMPROVEMENT_LIMIT`, `MAX_LAYOUTS`, interim publish, `Groups.reverse_run`. Delete
   `tests/test_search_run_direction.lua` and `tests/test_row_reverse.lua`; rewrite `test_search_stop.lua` /
   `test_search.lua` / `test_search_budget.lua` / `test_search_allowance.lua` cases that tested deleted behaviour
   (keep every case that still describes real behaviour). `test_generation_interim.lua` may need its search double
   adjusted only.
5. Tests, red at `round-29-mid` first:
   - new `tests/test_search_pipeline.lua`: stage doubles record call order = groups, pack, route, hands, power, tidy,
     validate, serialize; Pack got `zone_blockers` equal to roboport rects and non-empty `links`; Route got
     `tidy = false`; Power got a `make_room` function.
   - new `tests/test_search_retry.lua`: validate double fails twice -> Groups saw `ring_bump` 0, 1, 2, result
     `BP_FAIL_NO_LAYOUT` with 3 rejections; fails once -> ok with `ring_bump = 1`; pack no-fit -> next grid, same
     bump.
   - new `tests/test_hands.lua`: a slide moves hand, port and pickup/drop; `free_cell` shifts a hand one tile when free
     and on the same belt run, refuses otherwise.
6. Measure on the player's sheet: must print `entities` <= 191 and `LANE-SIM mixed=0`; also report generate wall
   time (round 28 took ~45 s wall). If entities > 191, look first at the `links` you build (wrong port ids make every
   distance fall back to centres).

## Checks (lua5.2 only, one file at a time)

`tests/test_search_pipeline.lua`, `tests/test_search_retry.lua`, `tests/test_hands.lua`, `tests/test_search.lua`, `tests/test_search_stop.lua`, `tests/test_search_budget.lua`, `tests/test_search_allowance.lua`, `tests/test_route_hand_slide.lua`, `tests/test_rows_integration.lua`, `tests/test_blueprint_pipeline.lua`, then `sh tools/first_verdict.sh` (must print `ok=true`), then the
measure command.

## Files this lane owns

`logic/bp/search.lua`, `logic/bp/hands.lua`, `logic/bp/groups.lua`, `tests/test_search_pipeline.lua`, `tests/test_search_retry.lua`, `tests/test_hands.lua`, `tests/test_search.lua`, `tests/test_search_stop.lua`, `tests/test_search_budget.lua`, `tests/test_search_allowance.lua`, `tests/test_search_run_direction.lua`, `tests/test_row_reverse.lua`, `tests/test_route_hand_slide.lua`, `tests/test_generation_interim.lua` (in `groups.lua` ONLY the `Groups.reverse_run` removal).

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
`docs/contracts/pipeline_r29.md`, nor any test file not listed here.

## Commit, THEN check

Commit on `lane/189` with the measured entity count and wall time in the message. **Run the two checks below as the
very LAST action.**

## What done mean

```checks
{"name": "lane189-tests", "command": "git diff --name-only round-29-mid HEAD | grep -v '^docs/tasks/189' | grep -Ev '^(logic/bp/search\\.lua|logic/bp/hands\\.lua|logic/bp/groups\\.lua|tests/test_search_pipeline\\.lua|tests/test_search_retry\\.lua|tests/test_hands\\.lua|tests/test_search\\.lua|tests/test_search_stop\\.lua|tests/test_search_budget\\.lua|tests/test_search_allowance\\.lua|tests/test_search_run_direction\\.lua|tests/test_row_reverse\\.lua|tests/test_route_hand_slide\\.lua|tests/test_generation_interim\\.lua)$' | ( ! grep . ) && ! git diff round-29-mid HEAD -- logic | grep -q '^+.*coroutine' && ! grep -nE 'flip_queue|partition_specs|candidate_orders|publish_interim|reverse_run' logic/bp/*.lua && for t in test_search_pipeline test_search_retry test_hands test_search test_search_stop test_search_budget test_search_allowance test_route_hand_slide test_rows_integration test_blueprint_pipeline; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane189-tests-ok", "expect_exit": 0, "expect_regex": "lane189-tests-ok", "timeout_s": 1500}
{"name": "lane189-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc189-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc189-first.txt && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E '^  (entities|belts) ' | tee /tmp/rrc189-measure.txt; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1 | grep -q 'mixed=0' && awk '/entities/ {exit !($2 <= 191)}' /tmp/rrc189-measure.txt && echo lane189-probe-ok", "expect_exit": 0, "expect_regex": "lane189-probe-ok", "timeout_s": 600}
```

# bound: 3000s
