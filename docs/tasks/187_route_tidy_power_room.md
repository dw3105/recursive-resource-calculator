# 187 route: tidy as its own step and free a tile; power: make room for a pole

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-187`, branch `lane/187`,
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

Today route runs its improve pass (re-route keep-if-cheaper, hand slide, bury, merge feed) inside first routing,
before poles exist. The player wants poles first, then tidy. So route gets a switch to stop after first routing and
a separate tidy step that avoids given obstacle cells (the poles). Power, when no free spot can cover a machine or
hand, may ask to bury a belt/pipe tile or shift a hand; route offers `Route.free_cell` for the belt/pipe part.

## Where the code is

`logic/bp/route.lua` (3404 lines): `Route.begin` (~2653), `Route.step` (~3262; improve at ~3272-3288,
`unbury_empty_pairs` ~2334), `improve_begin` (~2970), `improve_step` (~2982, merge trials inside), `route_snapshot`
(~1251), `bury_candidate` (~1415), `apply_bury` (~1479), `result_for`. Obstacles enter through `Route.begin` input
(`obstacles`, ~377). `logic/bp/power.lua` (1268 lines): `Power.begin` (~734), `normalize_occupied` (~233),
`candidate_is_occupied` (~273), `greedy` (~899), connect/repair/prune/publish phases, `uncovered` in result.

## What to build

1. C6: `Route.begin{tidy = false}` -> `Route.step` done after first routing (no improve, no unbury). `tidy` nil ->
   unchanged. `Route.tidy_begin(done_state, {obstacles = {TileRect}})` + `Route.tidy_step(state, budget)` = the
   same improve pass + unbury, never placing anything on an obstacle cell, budgeted like today, result shape of
   `result_for`. Merge-feed trials stay inside the tidy pass.
2. C6: `Route.free_cell(state, x, y) -> boolean` on a done route state: bury the straight same-flow run through the
   tile (belt: underground pair; pipe: pipe-to-ground pair if route supports it, else false); update
   `state.result` (entities, segments) in place; refuse near a port, at a turn, beyond underground reach.
3. C7: `Power.begin{make_room = fn}` + `occupied[i].kind`; after greedy, per uncovered consumer try at most 8 best
   spots blocked only by belt/underground/pipe/inserter cells, calling `make_room` per blocked cell; all true ->
   spot freed and selected; then connect/repair as today. No callback -> unchanged.
4. Tests, red at `round-29-base` first:
   - new `tests/test_route_tidy.lua`: `tidy=false` result has no improve counters and equals first routing; tidy
     after it gives the same entity count as today's one-shot route on the same fixture; an obstacle on the only
     cheaper path keeps the old path.
   - new `tests/test_route_free_cell.lua`: 5-tile straight belt -> middle tile freed, underground pair emitted,
     flow still connected; tile at a turn or next to a port -> false.
   - new `tests/test_power_make_room.lua`: a consumer walled by belts -> no callback: uncovered; callback that
     frees -> covered with a pole on the freed cell; callback that refuses -> uncovered, nothing moved.
   - keep `test_route_improve`, `test_route_merge_feed`, `test_route_bury`, `test_power` green.

## Checks (lua5.2 only, one file at a time)

`tests/test_route_tidy.lua`, `tests/test_route_free_cell.lua`, `tests/test_power_make_room.lua`, `tests/test_route_improve.lua`, `tests/test_route_merge_feed.lua`, `tests/test_route_bury.lua`, `tests/test_route.lua`, `tests/test_route_rows.lua`, `tests/test_power.lua`, `tests/test_power_budget.lua`, then `sh tools/first_verdict.sh` (must print `ok=true`), then the
measure command (must print `LANE-SIM mixed=0`).

## Files this lane owns

`logic/bp/route.lua`, `logic/bp/power.lua`, `tests/test_route_tidy.lua`, `tests/test_route_free_cell.lua`, `tests/test_power_make_room.lua`, `tests/test_route_improve.lua`, `tests/test_route_merge_feed.lua`, `tests/test_route_bury.lua`

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
`docs/contracts/pipeline_r29.md`, nor any test file not listed here. A test file listed here that tests code you
deleted is deleted or rewritten by you.

## Commit, THEN check

Commit on `lane/187` with the measured entity count in the message. **Run the two checks below as the very LAST
action.**

## What done mean

```checks
{"name": "lane187-tests", "command": "git diff --name-only round-29-base HEAD | grep -v '^docs/tasks/187' | grep -Ev '^(logic/bp/route\\.lua|logic/bp/power\\.lua|tests/test_route_tidy\\.lua|tests/test_route_free_cell\\.lua|tests/test_power_make_room\\.lua|tests/test_route_improve\\.lua|tests/test_route_merge_feed\\.lua|tests/test_route_bury\\.lua)$' | ( ! grep . ) && ! git diff round-29-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_tidy test_route_free_cell test_power_make_room test_route_improve test_route_merge_feed test_route_bury test_route test_route_rows test_power test_power_budget; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane187-tests-ok", "expect_exit": 0, "expect_regex": "lane187-tests-ok", "timeout_s": 1500}
{"name": "lane187-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc187-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc187-first.txt && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E '^  (entities|belts) ' | tee /tmp/rrc187-measure.txt; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1 | grep -q 'mixed=0' && echo lane187-probe-ok", "expect_exit": 0, "expect_regex": "lane187-probe-ok", "timeout_s": 600}
```

# bound: 3000s
