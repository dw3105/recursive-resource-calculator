# 211_all_links search: every block of a shared step gets its links

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-211_all_links`, branch `lane/211_all_links`,
base tag `round-36-base`, merge target `int/r36`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data in `storage` only (no closures, no metatables). Unit tests
finish in under 20 s; GUI/control tests loop over `H.shapes()` and move time only with `H.run_ticks(world, n)`.

Read `docs/contracts/round36.md` first: it is the contract. Your clauses: L1.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>` (every stage verdict per attempt);
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK` or `GATE-FAIL`).

## Explain very simply

`logic/bp/search.lua` `candidate_links` keys ports by `step|flow|role`; the last block wins, so other blocks of a
shared step lose their links (measured by the pack author on inserter-10s: 13 links instead of 44; one foundry got no
molten-iron link). Layered pack reads these links; a guard `pack_layered(state)` switches in a list-per-key path that
is now on by default.

## What to build

1. L1 list per key everywhere; one link per producer/consumer block pair; external edges per block.
2. Remove the `pack_layered(state)` guard in the links code (one path).
3. Test (red at base first): new `tests/test_candidate_links.lua`: a step split into 2 blocks → both blocks linked to
   producer and consumer.

## Files this lane owns

logic/bp/search.lua, tests/test_candidate_links.lua, tests/test_search.lua, tests/test_search_pipeline.lua, tests/test_search_retry.lua, docs/tasks/211_all_links.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/211_all_links`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane211-tests", "command": "git diff --name-only round-36-base HEAD | grep -Ev '^(logic/bp/search\\\\.lua|tests/test_candidate_links\\\\.lua|tests/test_search\\\\.lua|tests/test_search_pipeline\\\\.lua|tests/test_search_retry\\\\.lua|docs/tasks/211_all_links\\\\.md)$' | ( ! grep . ) && ! git diff round-36-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_candidate_links test_search test_search_pipeline test_search_retry; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane211-tests-ok", "expect_exit": 0, "expect_regex": "lane211-tests-ok", "timeout_s": 2400}
{"name": "lane211-measure", "command": "sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 413 | tail -1 | grep -q GATE-OK && echo lane211-ok", "expect_exit": 0, "expect_regex": "lane211-ok", "timeout_s": 1800}
```

# bound: 3000s
