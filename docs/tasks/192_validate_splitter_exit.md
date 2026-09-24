# 192 validate: splitter game rules; search: price an edge exit from the port's first belt tile

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-192`, branch `lane/192`,
base tag `round-30-base`, merge target `int/r30`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its tests pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), the
probe `sh tools/first_verdict.sh` (~10 s) and `sh tools/measure_sheet.sh <case>` (red ~15 s, green ~3 min). Never use
`coroutine` (Factorio has none). Plain data state only.

Read `docs/contracts/round30.md` first: it is the contract. Your clauses: V1, E1.

## Explain very simply

V1. In the game a splitter takes items ONLY from behind (a belt, underground exit or splitter facing the same way,
one tile back). A belt that points into a splitter's side delivers nothing. A belt never feeds a belt that faces it
head-on. Our validator's belt walk (`transport_neighbors`, `logic/bp/validate.lua` ~579-624) links any tile to the
tile in front of it, whatever that tile is, so it passes a green-science layout whose splitters sit on belt corners
and starve 6 machines. Teach the walk those two game rules.

E1. The red v10 product belt leaves its port (19,9) EAST to (20,9), runs up column x=20, then jogs west at (20,1) to
reach exit slot (19,0) and goes up (19,1),(19,0): 3 belts where 2 do. `slot_cost` (`logic/bp/search.lua` ~800-828)
measures from the PORT tile (19,9), so x=19 looks nearest. Measure from the port's first belt tile instead (out:
port + one step along `travel_dir`; in: port - one step), and delete the `nearest_distance == 1 -> +2` patch
(~820-823), which only papered over the same mistake.

## What to build

1. V1 in `transport_neighbors`: when the candidate next tile holds a splitter, accept it only if the current
   entity's direction equals the splitter's direction; never accept a next entity whose direction is opposite to
   the current one. Pipes unchanged. No new reason code.
2. E1 in `slot_cost` and whatever builds its consumer points (`terminal_consumers` ~771-798): carry the first-belt
   tile; remove the +2 patch.
3. Tests, red at `round-30-base` first:
   - new `tests/test_validate_splitter_rules.lua`: build candidates like `tests/test_validate_splitter.lua` (read it;
     do NOT edit it). For each of 4 facings: back-fed splitter passes and both outputs are walked; a belt pointing
     into the splitter's side -> not ok with `BP_V_ROUTE_DISCONTINUOUS`; a belt facing a belt head-on -> not ok.
   - new `tests/test_search_exit_slot.lua`: an out port at (19,9) with `travel_dir` EAST and a top output edge ->
     chosen slot x=20; an in port with `travel_dir` EAST at (5,5) and a left input edge -> slot y=5, x=0.
   - update `tests/test_search.lua` only for exit coordinates that move (say which in the commit).
4. Measure: `sh tools/measure_sheet.sh player-red-science-1s` -> `ok=true`, `entities` <= 185 (base 186),
   `mixed=0 starved=0`. `sh tools/measure_sheet.sh player-green-science-1s` -> `ok=false` (correct on this base:
   its splitters sit on corners; another change fixes route).

## Checks (lua5.2 only, one file at a time)

`test_validate_splitter_rules test_search_exit_slot test_validate_splitter test_validate test_validate_transport_shapes
test_validate_rows test_validated_candidate test_search test_search_pipeline test_search_retry test_search_stop`,
then `sh tools/first_verdict.sh`, then both measures.

## Files this lane owns

`logic/bp/validate.lua`, `logic/bp/search.lua`, `tests/test_validate_splitter_rules.lua`,
`tests/test_search_exit_slot.lua`, `tests/test_search.lua`.

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/contracts/**`,
nor any test file not listed here.

## Commit, THEN check

Commit on `lane/192` with both MEASURE lines in the message. **Run the checks below as the very LAST action.**

## What done mean

```checks
{"name": "lane192-tests", "command": "git diff --name-only round-30-base HEAD | grep -v '^docs/tasks/192' | grep -Ev '^(logic/bp/validate\\.lua|logic/bp/search\\.lua|tests/test_validate_splitter_rules\\.lua|tests/test_search_exit_slot\\.lua|tests/test_search\\.lua)$' | ( ! grep . ) && ! git diff round-30-base HEAD -- logic | grep -q '^+.*coroutine' && ! grep -n 'nearest_distance == 1' logic/bp/search.lua && for t in test_validate_splitter_rules test_search_exit_slot test_validate_splitter test_validate test_validate_transport_shapes test_validate_rows test_validated_candidate test_search test_search_pipeline test_search_retry test_search_stop; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane192-tests-ok", "expect_exit": 0, "expect_regex": "lane192-tests-ok", "timeout_s": 1500}
{"name": "lane192-measure", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && sh tools/measure_sheet.sh player-red-science-1s | tail -1 | tee /tmp/rrc192-red.txt && sh tools/measure_sheet.sh player-green-science-1s | tail -1 | tee /tmp/rrc192-green.txt && grep -q 'ok=true .*mixed=0 starved=0' /tmp/rrc192-red.txt && grep -q 'ok=false' /tmp/rrc192-green.txt && sed -n 's/.* entities=\\([0-9]*\\) .*/\\1/p' /tmp/rrc192-red.txt | awk '{exit !($1 <= 185)}' && echo lane192-measure-ok", "expect_exit": 0, "expect_regex": "lane192-measure-ok", "timeout_s": 900}
```

# bound: 2400s
