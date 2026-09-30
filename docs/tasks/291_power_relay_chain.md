# 291_power_relay_chain: power joins pole groups by a shortest relay chain when greedy repair gives up

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-291`, branch `lane/291`,
base tag `round-52-wave2-base` (`185231e78ca5612a0c0c16e94db1a662e25c0605`), merge target `int/r52`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet
or headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4) or `timeout 90 python3 -m unittest tests/<file>.py`;
headless test files only offline: `timeout 90 lua5.2 tests/game/offline.lua tests/game/<file>.lua`. Never use
`coroutine` or `math.random`. `require` only at file top level. **No game item or entity name in `logic/`.** Every
new test must FAIL on the base code where this task says "red on base" (say so in its header comment, with date
2026-09-30); commit it red first, then the code.

## Explain very simply

Read `CONTEXT.md` terms **Drawn pack**, **Fallback**. Player ruling 2026-09-30: every golden must deliver a drawn
layout (no Fallback). Two goldens fall back today because power fails: `BP_PW_DISCONNECTED`.

Power places poles, then joins pole groups with wires (reach = wire reach, 9 for medium poles). When groups stay
apart it runs a repair (`logic/bp/power.lua:693-800`, modes 1187-1290):
- direct: one relay tile in reach of BOTH poles of a pair;
- frontier: one relay tile in reach of the left pole, closest (straight line) to the right pole, repeat.
Frontier is greedy: it heads straight at the other group through walls of machines, gets stuck in a pocket, and
`frontier_pair` runs out of pairs -> `finish_repair` (693) -> prune -> `BP_PW_DISCONNECTED`.

Measured 2026-09-30 (legalcopilot-dev), drawn red-science-10s, grid 54x54, reach 9: group B = 3 poles at x=0
(y=10,18,22) powering two blocks on the left edge; group A = 13 poles at x>=19. Free ground at rows 24-49, x=0..22
gives a 3-relay chain, e.g. (0,22) -> (8,24) -> (16,26) -> A near (25,28). Drawn inserter-10s-stack1 (54x104): group
A = 3 poles (37,4),(41,9),(35,11); free column x=35..40 rows 14-27 gives A(35,11) -> (37,19) -> (37,27) -> B(39,29).
Both power states are frozen: `tests/fixtures/power_r10s_drawn_state.lua.gz`,
`tests/fixtures/power_s1_drawn_state.lua.gz` (load with `require "tools.lib.graph_dump".load(path)`, then
`Power.step(state, {ops = 2000})` until `state.done`; today both end `ok=false` with `BP_PW_DISCONNECTED`, 65 / 136
steps, worst step 25 ms).

## What to build

1. In `logic/bp/power.lua`, when the frontier repair has no pair left AND `work.connect.components > 1`, run a new
   repair mode "chain" before `finish_repair`:
   - BFS over relay spots: nodes = every pole spec x every tile where that spec fits free (same legality as
     `repair_position_usable` + the occupancy check `begin_repair_eval` / `repair_check` does: inside grid, not on an
     occupied rect, not on a chosen pole). Edges = `wire_legal` between two spots or between a spot and a chosen pole.
   - Sources = every chosen pole of the SMALLEST component; targets = any chosen pole of another component.
   - Shortest chain (fewest relays) wins; ties -> first found in fixed scan order (y, then x, then spec index).
     Never `math.random`.
   - Commit the whole chain (select each relay, join components), then continue the normal `connect` phase; repeat
     until one component or no chain exists -> `finish_repair` as today.
   - Sliced: the BFS state lives in `work` (plain data, checkpoints save it) and spends `budget.ops` per visited node /
     edge check; one `Power.step` call never exceeds the ops it is given. Cap visited nodes by the existing
     `relay_check_limit`; hitting it sets `work.relay_bound_hit = true` exactly like today.
2. Gentle rule: the chain mode runs ONLY where today's repair already gave up with >1 component. A layout that
   connects today must keep identical poles (same selected list, same order) -> every delivered layout keeps bytes.
3. Tests `tests/test_power_relay_chain.lua` (replace the stub; header: PR1-PR4 red on round-52-wave2-base):
   - PR1 red-10s fixture: power ends ok, `components == 1`, no `BP_PW_DISCONNECTED`; print relay count added.
   - PR2 stack1 fixture: same.
   - PR3 hand-built grid: two poles walled apart with only a detour path of 2 relays -> connected with exactly 2
     relays; a grid with no path at all -> still `BP_PW_DISCONNECTED`, no hang (bounded).
   - PR4 slicing: PR1 with `ops = 1` per step gives the same selected poles as `ops = 2000`; worst single
     `Power.step` wall time with `ops = 2000` on the stack1 fixture <= 16 ms (os.clock; print it).
   Print "PR1".."PR4" when each passes.
4. Keep green (one at a time): the list in the first check below.

## Files this lane owns

logic/bp/power.lua, tests/test_power_relay_chain.lua, docs/tasks/291_power_relay_chain.md. In `power.lua` add the chain mode and its hook where the frontier repair gives up; do not change direct/frontier behaviour.

## Commit, THEN check

Commit on `lane/291`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane291-tests", "command": "git diff --name-only round-52-wave2-base HEAD | grep -Ev '^(logic/bp/power\\.lua|tests/test_power_relay_chain\\.lua|docs/tasks/291_power_relay_chain\\.md)$' | ( ! grep . ) && for t in test_power_relay_chain test_power test_power_budget test_power_demand test_power_make_room test_power_ops test_power_semantics test_power_ticks test_power_wires test_search_draw_phase test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane291-tests-ok", "expect_exit": 0, "expect_regex": "lane291-tests-ok", "timeout_s": 3000}
{"name": "lane291-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_power_relay_chain.lua) 2>&1); for c in PR1 PR2 PR3 PR4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane291-ok", "expect_exit": 0, "expect_regex": "lane291-ok", "timeout_s": 300}
```

# bound: 5400s
