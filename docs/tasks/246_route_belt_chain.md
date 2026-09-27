# 246_route_belt_chain a belt never dives on the tile it surfaced on, and never turns off its source tile without a splitter

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-246`, branch `lane/246`,
base tag `round-44-wave3`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tests/golden/generate.lua`, `tools/game_test.sh`, `factorio`, or any
full suite, sheet run or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item
or entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment).

## Explain very simply

The player's gray + magenta sheet: the router finds a good belt path, then its own commit check throws it away,
because the search offered a move nobody can build. Two such moves, both traced on the frozen route input
`tests/fixtures/route_gray_magenta_154.json` (grid 154x154, legalcopilot-dev, 2026-09-27):

1. **Chain dive.** Coal (0,40) -> sink (140,70). Path surfaces from an underground at (85,69) (pair (76,69)->(85,69))
   and dives again on the SAME tile (85,69)->(96,69). One tile holds one entity: it cannot be an exit and an entrance.
   `append_normal_path` consumes the exit tile with the first pair (`index = index + 1`), never lays the second jump,
   and `route_chain_reaches_sink` rejects the path `route-discontinuous`. Pipes already refuse this dive
   (guard `and not (current.mode == 1 and search.demand.kind == "pipe")` in `search_step`); belts do not.
2. **Sideways off the source tile.** The second coal demand of one output (sink `plastic-bar:1`) starts on a source
   tile that already holds its own flow's belt. The search seeds the source with heading `travel_dir or 0`, not the
   heading of that belt, and `refused_body` (in `search_step`) only refuses a sideways step off a trunk that
   `splitter_can_absorb`. So the search turns sideways on tile 1; commit needs a splitter there, refuses
   `splitter-footprint` twice, and the demand dies.

Why GENTLE: banning both moves always was measured to change frozen tests (`test_route_chain` RC8 surface belts
80 -> 88, `test_route_collision` RX1 entities 85 -> 95, `test_route_tidy_junk` TJ1, `test_route_budget` RB1). Old
sheets survive these refusals because `restart_with_priority` reorders demands. So the ban applies to ONE demand,
only after its refusal repeats and `restart_with_priority` refuses (the demand is already first). Measured: gentle
form keeps all 31 `tests/test_route*.lua` + `test_pipe_runs` + `test_pipe_prune` green.

The exact change is already written and measured as an in-memory patch: `docs/tasks/ref/246_patch_reference.lua`
(gsubs on `logic/bp/route.lua`). Put the same logic into the source, readable, with a short comment at each spot
saying why (cite the tiles above and the date 2026-09-27). Keep behaviour identical to the reference.

## What to build

1. `tests/test_route_belt_chain.lua` (commit red first). Load `tests/fixtures/route_gray_magenta_154.json` with
   `helpers.json_to_table` after `H.new_world("2.0")` (see `tests/test_route_pipe_join.lua` PJ4/PJ5 for the exact
   loading and step loop), run `Route.begin` + `Route.step(st, {ops = 2000})` until BOTH coal demands below are
   placed (a binding with that `sink_port_id` exists) or 120 s CPU (`os.clock`) passes:
   - BC1: `in:item/coal:inserter:plastic-bar:2:input:1` placed (base: dies by chain dive).
   - BC2: `in:item/coal:inserter:plastic-bar:1:input:1` placed (base and chain-dive fix alone: dies by sideways step).
   One run serves both cases (run once, cache the state). Each case prints its name.
2. `logic/bp/route.lua`: F1c and F2c exactly as the reference patch does:
   - dive guard also refuses when `search.demand.no_chain_dive`;
   - route step, commit refused `route-discontinuous` with two crossing steps in a row and no `no_chain_dive` yet:
     `restart_with_priority`; if it refuses, `demand.no_chain_dive = true` and search again (`begin_search(..., 1)`);
   - splitter-footprint branch, no new search queued: `strict_branch` already set -> `fail_demand` as today; else
     `restart_with_priority`; if refused, `demand.strict_branch = true` and search again;
   - with `strict_branch`: source seed heading = direction of a same-flow surface belt (not underground, not pipe)
     already on the source tile; `refused_body` ignores `splitter_can_absorb`.

## Files this lane owns

logic/bp/route.lua, tests/test_route_belt_chain.lua, docs/tasks/246_route_belt_chain.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/246`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane246-tests", "command": "git diff --name-only round-44-wave3 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_belt_chain\\.lua|docs/tasks/246_route_belt_chain\\.md)$' | ( ! grep . ) && git diff --quiet round-44-wave3 HEAD -- docs/tasks/246_route_belt_chain.md && ! git diff round-44-wave3 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_belt_chain test_route test_route_budget test_route_chain test_route_collision test_route_tidy_junk test_route_footprints test_route_splitter_physics test_route_splitter_straight test_route_merge_feed test_route_output_join test_route_pipe_join test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane246-tests-ok", "expect_exit": 0, "expect_regex": "lane246-tests-ok", "timeout_s": 2400}
{"name": "lane246-fast", "command": "out=$(lua5.2 tests/test_route_belt_chain.lua 2>&1); for n in BC1 BC2; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane246-ok", "expect_exit": 0, "expect_regex": "lane246-ok", "timeout_s": 300}
```

# bound: 2400s
