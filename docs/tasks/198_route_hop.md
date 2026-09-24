# 198_route_hop route: try hand hops in the keep-if-cheaper pass

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-198_route_hop`, branch `lane/198_route_hop`,
base tag `round-31-base`, merge target `int/r31`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data state only (resumable across game
ticks). Every unit test you write must finish in under 20 s.

Read `docs/contracts/round31_hand_hop.md` first: it is the contract. Your clauses: R5. Code EXACTLY the field
names it gives; the other half is built against the same names.

## Explain very simply

The improve pass (`logic/bp/route.lua`, `improve_step` ~3230-3350) already tries hand SLIDES: `slide_endpoint` (~3115) moves an endpoint and its hand one tile along the face, re-routes that one binding, keeps it only when `route_weight` drops, else restores (`unslide_endpoint`). Ports will now also carry `hop_options`: the hand moves to another face of its machine, so the port tile moves anywhere around the machine and the belt's `travel_dir` turns with it. Try those exactly like slides.

## What to build

1. `normalize_endpoint` (~510) copies `port.hop_options` to the endpoint (with `hand_x/hand_y`).
2. `hop_endpoint` / `unhop_endpoint` per contract R5 (plain-data undo; same free-tile checks as `slide_endpoint`; rotate `travel_dir` by `turns`; re-reserve port cells).
3. In the improve pass, after the slide options of an endpoint, trial each hop option the same way; publish kept hops in `result.port_slides` as `{port_id =, hop = {hand_x, hand_y, port_x, port_y, turns}}` (~2491).
4. New `tests/test_route_hop.lua` (red at base first): a source block and a sink block where the sink's port faces AWAY from the source (belt must go round the machine); give the sink endpoint a hop option on the face toward the source: the tidied route keeps the hop, publishes it in `port_slides`, uses fewer belts, its last belt heads the rotated `travel_dir`; a hop onto a taken tile is refused and the layout is unchanged; undo restores the endpoint exactly. Keep the other listed tests green.

## Same bytes (your half alone changes nothing)

Without the other half, no hop is ever taken, so `sh tools/bytes_hash.sh player-red-science-1s` and
`sh tools/bytes_hash.sh player-green-science-1s` must print exactly `tests/fixtures/bytes_round30.txt`.

## Files this lane owns

logic/bp/route.lua, tests/test_route_hop.lua, tests/test_route_hand_slide.lua, tests/test_route_improve.lua, tests/test_route_tidy.lua, tests/test_route_ticks.lua, tests/test_route_budget.lua. Never touch anything else.

## Commit, THEN check

Commit on `lane/198_route_hop`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane198_route_hop-tests", "command": "git diff --name-only round-31-base HEAD | grep -v '^docs/tasks/198_route_hop' | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_hop\\.lua|tests/test_route_hand_slide\\.lua|tests/test_route_improve\\.lua|tests/test_route_tidy\\.lua|tests/test_route_ticks\\.lua|tests/test_route_budget\\.lua)$' | ( ! grep . ) && ! git diff round-31-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_hop test_route_hand_slide test_route_improve test_route_tidy test_route_ticks test_route_budget; do timeout 180 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane198_route_hop-tests-ok", "expect_exit": 0, "expect_regex": "lane198_route_hop-tests-ok", "timeout_s": 1500}
{"name": "lane198_route_hop-same", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && sh tools/bytes_hash.sh player-red-science-1s > /tmp/r198_route_hop.txt && sh tools/bytes_hash.sh player-green-science-1s >> /tmp/r198_route_hop.txt && diff tests/fixtures/bytes_round30.txt /tmp/r198_route_hop.txt && echo lane198_route_hop-ok", "expect_exit": 0, "expect_regex": "lane198_route_hop-ok", "timeout_s": 900}
```

# bound: 3600s
