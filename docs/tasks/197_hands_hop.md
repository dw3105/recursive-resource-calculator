# 197_hands_hop hands: offer hand hops to other machine faces; apply kept hops

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-197_hands_hop`, branch `lane/197_hands_hop`,
base tag `round-31-base`, merge target `int/r31`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data state only (resumable across game
ticks). Every unit test you write must finish in under 20 s.

Read `docs/contracts/round31_hand_hop.md` first: it is the contract. Your clauses: H1, H2. Code EXACTLY the field
names it gives; the other half is built against the same names.

## Explain very simply

Today `Hands.offer_slides` (`logic/bp/hands.lua`) lets a hand move one tile along its machine face (`slide_options`), and `Hands.place` applies the moves the route kept (`route_result.port_slides` with `dx, dy`). The player's green fix moved hands to OTHER faces of their machine (e.g. the cable plant's copper input from its left face to under it, right on the copper belt), saving 22 entities. Offer those moves as `hop_options` and apply kept hops (`hop = {...}`).

## What to build

1. H1: `hop_options` per the contract (free hand tile on another face or farther along the same face, free port tile, `turns`), at most 16, nearest first; only single-port hands of single machines (no `row_port`).
2. H2: `Hands.place` applies `hop` entries: port tile, attach, travel/normal dir rotated by `turns`; hand tile, position, dir rotated, pickup/drop recomputed (input picks the port tile, drops in the machine; output the reverse); `_occupied` follows.
3. New `tests/test_hands_hop.lua` (red at base first): a 3x3 machine with one input hand on its west face in a 10x10 grid with one blocked tile: (a) `hop_options` list tiles on north/south/east faces, never corners, never taken tiles, `turns` correct for each face, <= 16, nearest first; (b) a row port gets none; (c) `Hands.place` with `{port_id =, hop = {...}}` moves hand + port, pickup on the port tile, drop inside the machine, dir rotated; output hand case reversed. Keep `tests/test_hands.lua`, `tests/test_route_hand_slide.lua` green.

## Same bytes (your half alone changes nothing)

Without the other half, no hop is ever taken, so `sh tools/bytes_hash.sh player-red-science-1s` and
`sh tools/bytes_hash.sh player-green-science-1s` must print exactly `tests/fixtures/bytes_round30.txt`.

## Files this lane owns

logic/bp/hands.lua, tests/test_hands_hop.lua, tests/test_hands.lua, tests/test_route_hand_slide.lua. Never touch anything else.

## Commit, THEN check

Commit on `lane/197_hands_hop`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane197_hands_hop-tests", "command": "git diff --name-only round-31-base HEAD | grep -v '^docs/tasks/197_hands_hop' | grep -Ev '^(logic/bp/hands\\.lua|tests/test_hands_hop\\.lua|tests/test_hands\\.lua|tests/test_route_hand_slide\\.lua)$' | ( ! grep . ) && ! git diff round-31-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_hands_hop test_hands test_route_hand_slide; do timeout 180 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane197_hands_hop-tests-ok", "expect_exit": 0, "expect_regex": "lane197_hands_hop-tests-ok", "timeout_s": 1500}
{"name": "lane197_hands_hop-same", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && sh tools/bytes_hash.sh player-red-science-1s > /tmp/r197_hands_hop.txt && sh tools/bytes_hash.sh player-green-science-1s >> /tmp/r197_hands_hop.txt && diff tests/fixtures/bytes_round30.txt /tmp/r197_hands_hop.txt && echo lane197_hands_hop-ok", "expect_exit": 0, "expect_regex": "lane197_hands_hop-ok", "timeout_s": 900}
```

# bound: 3600s
