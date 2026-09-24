# 200_route_hand_freedom route + hands: a hand may take any free face tile of its machine

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-200_route_hand_freedom`, branch `lane/200_route_hand_freedom`,
base tag `round-32-base`, merge target `int/r32`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data state only (resumable across game
ticks: every trial state lives in `st`, no closures). Every unit test you write must finish in under 20 s.

Read `docs/contracts/round32_bleed_and_hands.md` first: it is the contract. Your clauses: F1, F2, F3.

## Explain very simply

Player: "inserter placement must not be restricted artificially!" Their green fix put the inserter assembler's
product hand on its EAST face at (22,14) and the foundry's gear input on its TOP face. We could not, three measured
reasons (green, attempt 2, legalcopilot-dev 2026-09-24):
1. `Hands.offer_slides` (`logic/bp/hands.lua`) builds `hop_options` once, before routing, skipping tiles any entity
   holds then: (22,14) held the gear input hand at that moment, so it was never offered (F1).
2. The offered east tiles (22,15), (22,16) were REFUSED live in `hop_endpoint` (tile taken at trial time) and never
   tried again after the blocker moved (F3).
3. `improve_step` (`logic/bp/route.lua` ~3338) tries slides/hops only when `bindings_on_port(...) == 1`; the gear
   output port serves 2 bindings, so it never moves (F2).

## What to build

1. F1 in `hands.lua` per contract (other hands' tiles offered; no 16 cap; nearest first).
2. F2 in `route.lua` improve pass: multi-binding ports lift all their bindings, move, re-route all, keep if smaller
   and every binding reaches its sink. Resumable across ticks like today's trial (`trial_start/run/finish/undo`).
3. F3 in `route.lua`: remember refused moves; one retry round after a pass that kept at least one move.
4. Tests (red at base first):
   - `tests/test_hands_hop.lua`: add a case where a face tile holds another hand: it IS offered; >16 face tiles all
     offered (a 5x5 machine).
   - new `tests/test_route_hop_multi.lua`: (a) a source port with 2 bindings to 2 sinks where a hop to another face
     shortens both: kept, published in `port_slides`, both bindings reach their sinks; (b) a hop refused on the first
     pass because another endpoint's hand held the tile, freed by that endpoint's own kept move later in the pass:
     taken in the retry round.
   Keep `test_hands`, `test_hands_hop`, `test_route_hop`, `test_route_hand_slide`, `test_route_improve`,
   `test_route_tidy`, `test_route_ticks`, `test_route_budget` green.

## Measure (one command each)

`sh tools/measure_sheet.sh player-red-science-1s` must end `ok=true`, entities <= 169, `mixed=0 starved=0 bleed=0`.
Green alone may still bleed until the other half lands; print it and report its MEASURE line and route weight, do not
gate on it: `sh tools/measure_sheet.sh player-green-science-1s`.

## Files this lane owns

logic/bp/route.lua, logic/bp/hands.lua, tests/test_hands.lua, tests/test_hands_hop.lua, tests/test_route_hop.lua,
tests/test_route_hop_multi.lua, tests/test_route_hand_slide.lua, tests/test_route_improve.lua, tests/test_route_tidy.lua,
tests/test_route_ticks.lua, tests/test_route_budget.lua. Never touch anything else.

## Commit, THEN check

Commit on `lane/200_route_hand_freedom`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane200_route_hand_freedom-tests", "command": "git diff --name-only round-32-base HEAD | grep -v '^docs/tasks/200_route_hand_freedom' | grep -Ev '^(logic/bp/route\\.lua|logic/bp/hands\\.lua|tests/test_hands\\.lua|tests/test_hands_hop\\.lua|tests/test_route_hop\\.lua|tests/test_route_hop_multi\\.lua|tests/test_route_hand_slide\\.lua|tests/test_route_improve\\.lua|tests/test_route_tidy\\.lua|tests/test_route_ticks\\.lua|tests/test_route_budget\\.lua)$' | ( ! grep . ) && ! git diff round-32-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_hop_multi test_hands test_hands_hop test_route_hop test_route_hand_slide test_route_improve test_route_tidy test_route_ticks test_route_budget; do timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane200_route_hand_freedom-tests-ok", "expect_exit": 0, "expect_regex": "lane200_route_hand_freedom-tests-ok", "timeout_s": 2400}
{"name": "lane200_route_hand_freedom-measure", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && sh tools/measure_sheet.sh player-red-science-1s | tail -1 | awk '/ok=true/ && /mixed=0 starved=0 bleed=0/ {split($0,a,\"entities=\"); split(a[2],b,\" \"); if (b[1] <= 169) ok=1} END {exit !ok}' && echo lane200_route_hand_freedom-ok", "expect_exit": 0, "expect_regex": "lane200_route_hand_freedom-ok", "timeout_s": 900}
```

# bound: 5400s
