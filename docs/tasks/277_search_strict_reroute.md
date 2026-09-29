# 277_search_strict_reroute a layout refused by validate for belt shape is routed once more in strict mode

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-277`, branch `lane/277`,
base tag `round-49-base`, merge target `int/r49`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua save|list|uninterrupted`, `factorio`, or any full suite, whole sheet or
headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No
game item or entity name in `logic/`.** Every new test must FAIL on the base code where this task says "red on
base" (say so in its header comment); commit it red first.

## Explain very simply

Player sheet `player-magenta-science-10s` fails in game. Offline (legalcopilot-dev 2026-09-29, lua5.2, base
`90a3b81`) layout 6 (grid 6) routes, then validate refuses it for belt shape (80 `BP_V_BELT_BLEED`, 23
`BP_V_TRANSPORT_UNUSED`, 8 `BP_V_ROUTE_DISCONTINUOUS`, 1 each `BP_V_BELT_NO_SOURCE`,
`BP_V_UNDERGROUND_SIDELOAD_BLOCKED`, `BP_V_ROUTE_LOOP`). Search throws the layout away. The SAME packing routes
clean when route runs with three stricter rules, which route turns on only when its input carries
`strict_ends = true` (route side is another lane; you only pass the flag).

Rule: when validate refuses a candidate and any error code is one of those 6 belt-shape codes, the candidate is
not in strict mode yet, and no collector trial is running (`state.work.collector_trial == nil`): set
`state.work.strict_ends = true` and call `start_grid(state)` (same `cursor.grid_index`, same attempt, same layered
state) so groups, pack and route run again for that grid; every route input made while the flag is set carries
`strict_ends = true`. Otherwise clear the flag and `discard_candidate(state)` as today. The flag is also cleared
inside `discard_candidate`, so the next candidate always starts non-strict.

Measured in memory with reference patch
`/home/dev_zaigraev_gmail_com/wt-rrc-int49/docs/tasks/r49_probes/p_strict.lua` (search part): whole magenta sheet
strict redo at grid 6, tick 18351, then `ok=true` tick 34785. On the other 14 golden sheets no candidate is ever
refused by validate (13: power refusals only; gray-magenta: pack only), so their bytes cannot change. Copy its
search logic; drop every `io.write`.

## What to build

1. `logic/bp/search.lua`:
   - module-local table (near other constants) of the 6 codes: `BP_V_BELT_BLEED`,
     `BP_V_UNDERGROUND_SIDELOAD_BLOCKED`, `BP_V_ROUTE_DISCONTINUOUS`, `BP_V_ROUTE_LOOP`, `BP_V_BELT_NO_SOURCE`,
     `BP_V_TRANSPORT_UNUSED`.
   - after `local route_input = make_route_input(state, state.work.grid, blocks, ports, state.work.robo_obstacles)`
     (~:1698): `if route_input and state.work.strict_ends then route_input.strict_ends = true end`.
   - validate-refused branch (~:1823-1826, `record_rejection(state, state.work.validate.errors, "validate")` then
     `discard_candidate(state)`): the rule above.
   - `discard_candidate` (~:1606): first line clears `state.work.strict_ends = nil`.
   - Short comment with the measured numbers above + date 2026-09-29.
2. New `tests/test_search_strict.lua` (header: ST1 red on round-49-base). Use the doubles in
   `tests/fixtures/search_doubles.lua` the way `tests/test_search_retry.lua` does (read it first); record every
   route input the stubbed Route receives.
   - ST1: first validate refuses with `BP_V_BELT_BLEED`, second ok -> exactly 2 route inputs; the 1st has no
     `strict_ends`, the 2nd has `strict_ends == true`; both at the same grid index; result delivered (ok).
   - ST2: first validate refuses with a non-shape code only (e.g. `BP_V_COLLISION`) -> no strict re-route: the next
     route input has no `strict_ends` (search continues exactly as in `test_search_retry` SR1).
   - ST3: every validate refuses with `BP_V_BELT_BLEED` -> each candidate gets exactly one strict re-route, the
     candidate after it starts non-strict; search ends `BP_FAIL_NO_LAYOUT` as today.
   - Bound every wait (600 steps); fail naming the stuck phase.
3. Also run and keep green (one at a time, `timeout 90`): `test_search`, `test_search_retry`,
   `test_search_pipeline`, `test_search_budget`, `test_search_stop`, `test_search_allowance`,
   `test_search_exit_slot`, `test_search_fluid_door_gap`, `test_progress_view`, `test_jobs`, `test_no_item_names`,
   `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/bp/search.lua, tests/test_search_strict.lua, docs/tasks/277_search_strict_reroute.md. Never touch anything
else.

## Commit, THEN check

Commit on `lane/277`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane277-tests", "command": "git diff --name-only round-49-base HEAD | grep -Ev '^(logic/bp/search\\.lua|tests/test_search_strict\\.lua|docs/tasks/277_search_strict_reroute\\.md)$' | ( ! grep . ) && for t in test_search_strict test_search test_search_retry test_search_pipeline test_search_budget test_search_stop test_search_allowance test_search_exit_slot test_search_fluid_door_gap test_progress_view test_jobs test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane277-tests-ok", "expect_exit": 0, "expect_regex": "lane277-tests-ok", "timeout_s": 3000}
{"name": "lane277-fast", "command": "out=$(lua5.2 tests/test_search_strict.lua 2>&1); for c in ST1 ST2 ST3; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane277-ok", "expect_exit": 0, "expect_regex": "lane277-ok", "timeout_s": 900}
```

# bound: 3600s
