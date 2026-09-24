# 199_ends_turn ends: a flow's last belt never points into another flow's belt

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-199_ends_turn`, branch `lane/199_ends_turn`,
base tag `round-32-base`, merge target `int/r32`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data only. Every unit test you write must
finish in under 20 s.

Read `docs/contracts/round32_bleed_and_hands.md` first: it is the contract. Your clause: E1.

## Explain very simply

The player placed our green science blueprint and saw "belt bleeding": the circuit belt ends at the inserter
assembler's hand at (17,14) facing SOUTH, and the tile south of it (17,15) is the inserter-product belt, so circuits
run onto the product belt and on to the science machines (which eat no circuits). Same at the foundry: gear belt ends
at (31,23) facing SOUTH into the iron stub at (31,24). A belt on a hand's pickup tile may face any way (the hand reads
the tile). Turn such a last belt a quarter so it points at nothing that takes items (the hand, a machine, empty
ground). Validate already rejects the bleed (`BP_V_BELT_BLEED`, base commit), so today green gives
`BP_FAIL_NO_LAYOUT`; after your pass green must deliver.

## What to build

1. New `logic/bp/ends.lua` with `Ends.turn_heads(route_result)` exactly per contract E1 (game rules for "accepts";
   entity tile = floor of `x, y` for 1x1 belts; route entities carry `dir`, `flow_id`, optional `flow_ids`; a splitter
   covers 2 tiles across its facing; an underground has `ug_role`/`type` input/output). Returns the number of belts
   turned.
2. `logic/bp/search.lua`: call it once when the tidy stage is done, right before `Hands.place(...)` (~line 1647), on
   `state.work.route_state.result`.
3. New `tests/test_ends_turn.lua` (red at base first): (a) the box-1 shape: flow A down x=5 ending at (5,2) facing
   south, flow B belt east along y=3: A's last belt turns east or west and `Validate` then reports no
   `BP_V_BELT_BLEED`; (b) a turn that would face another foreign belt picks the other quarter; (c) a same-flow join
   (B declares A's flow too) is left alone; (d) no fitting heading: unchanged; (e) a splitter/underground is never
   turned. Keep `tests/test_search_pipeline.lua` green.

## Measure (one command each)

`sh tools/measure_sheet.sh player-green-science-1s` must end `ok=true` with `mixed=0 starved=0 bleed=0`.
`sh tools/bytes_hash.sh player-red-science-1s` must print exactly the red line of `tests/fixtures/bytes_round31.txt`
(red has no bleed: nothing turns).

## Files this lane owns

logic/bp/ends.lua, logic/bp/search.lua, tests/test_ends_turn.lua, tests/test_search_pipeline.lua. Never touch anything else.

## Commit, THEN check

Commit on `lane/199_ends_turn`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane199_ends_turn-tests", "command": "git diff --name-only round-32-base HEAD | grep -v '^docs/tasks/199_ends_turn' | grep -Ev '^(logic/bp/ends\\.lua|logic/bp/search\\.lua|tests/test_ends_turn\\.lua|tests/test_search_pipeline\\.lua)$' | ( ! grep . ) && ! git diff round-32-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_ends_turn test_search_pipeline test_validate_bleed; do timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane199_ends_turn-tests-ok", "expect_exit": 0, "expect_regex": "lane199_ends_turn-tests-ok", "timeout_s": 1200}
{"name": "lane199_ends_turn-measure", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && sh tools/bytes_hash.sh player-red-science-1s | grep -qx \"$(grep player-red tests/fixtures/bytes_round31.txt)\" && sh tools/measure_sheet.sh player-green-science-1s | tail -1 | grep -E 'ok=true .*mixed=0 starved=0 bleed=0' && echo lane199_ends_turn-ok", "expect_exit": 0, "expect_regex": "lane199_ends_turn-ok", "timeout_s": 900}
```

# bound: 3600s
