# 266_route_no_replay_and_prof a failed flood is not replayed in 3 more direction orders; route profiler tool in repo

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-266`, branch `lane/266`,
base tag `round-46-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/ckpt.lua save`, `tools/ckpt.lua uninterrupted`, `factorio`, or any full suite, whole sheet or headless run of
any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
`lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/<fixture> ...` (seconds). Never use `coroutine`. `require`
only at file top level. **No game item or entity name in `logic/`.** Every new test must FAIL on the base code where
this task says "red on base" (say so in its header comment); commit it red first.

## Explain very simply

R1: first routing (`logic/bp/route.lua` ~:4645-4666, branch `outcome == "failed"`): when a search floods the grid
and fails with only `saw_blocked`, it is started again with `search.order_index + 1`, up to 4 direction orders.
Measured on `player-inserter-10s-stack1` (legalcopilot-dev 2026-09-28): 75 replays, 1,293,951 search steps, 0
succeeded. Fix: no replay; fall through to the next branch (`next_endpoint_candidate`, then ride, then fail) exactly
as when `order_index == #DIRECTION_ORDERS`. Patch text: `docs/tasks/r46_probes/p_noreplay.lua`. Measured in memory
with the other round-46 rules: canonical sha of all 13 golden sheets unchanged, stack1 ticks 16077 -> 9132.
If `DIRECTION_ORDERS[2..4]` and `order_index` then have no other caller, leave them (another lane may use them); only
the replay branch goes.

Tool: the probes `docs/tasks/r46_probes/prof_patch3.lua` (function timer, trial census, search census),
`census.awk`, `searches.awk`, `p_garbage.lua` become ONE Lua tool with no awk:
```
lua5.2 tools/route_prof.lua <checkpoint.lua.gz> [--until <at-spec>] [--set coarse|fine|all] [--patch f.lua]
```
It runs `tools/ckpt.lua resume` logic in-process (reuse `tools/ckpt.lua` patch hook: pass its own timer patch,
chained AFTER a user `--patch` like `p_combo.lua` does) and prints 5 blocks, each headed by a line starting with
`== `: `== functions` (name, calls, incl s, excl s, worst ms; sorted by incl), `== trials` (tidy trials: run,
0-step, steps, snapshots), `== searches` (count, steps, failed floods, `order_index > 1` count), `== garbage`
(kb per search step), `== keys` (`coordinate_key` calls per search step). Last line
`END ticks=<n> sha=<sha> entities=<n>` same as ckpt resume. The tool is test-side only: nothing in `logic/` changes
for it.

Fixture: `tests/fixtures/route_snaps/stack1_restart27.lua.gz` (27th route-restart of stack1). Base:
`lua5.2 tools/ckpt.lua resume <it> --until kind=route-restart --save /tmp/x.lua.gz` runs 10.9 s and holds 6
`begin_search` calls with `order_index > 1`. Base digests: `tests/fixtures/route_snaps/r46_digests.txt`.

## What to build

1. `tests/test_route_no_replay.lua`:
   - NR1 resume `stack1_restart27.lua.gz --until kind=route-restart` with a counting patch on `begin_search`:
     calls with `order_index > 1` = 0. Red on base (6).
   - NR2 unit: a demand whose first search floods and fails blocked goes straight to the next endpoint candidate /
     fail path (no second `begin_search` with order 2).
2. `tests/test_route_prof.lua`: RP1 tool on `green_tidy.lua.gz --until phase=validate` prints all 5 `== ` blocks,
   `route_snapshot` and `search_step` rows present, garbage kb per step a number > 0. RP2 `--set coarse` omits
   `coordinate_key` row. Red on base (tool absent).
3. `logic/bp/route.lua` R1, `tools/route_prof.lua`.
4. `skills/rrc-code/SKILL.md`: one ladder / tool-table row for `tools/route_prof.lua` (caveman, one line, usage).
5. Keep green: `test_route_budget` (RB3), `test_route` (R5, R6), `test_route_ticks`, `test_ckpt`.

## Files this lane owns

logic/bp/route.lua (ONLY the `outcome == "failed"` branch ~:4645-4666), tools/route_prof.lua,
tests/test_route_no_replay.lua, tests/test_route_prof.lua, skills/rrc-code/SKILL.md,
docs/tasks/266_route_no_replay_and_prof.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/266`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane266-tests", "command": "git diff --name-only round-46-base HEAD | grep -Ev '^(logic/bp/route\\.lua|tools/route_prof\\.lua|tests/test_route_no_replay\\.lua|tests/test_route_prof\\.lua|skills/rrc-code/SKILL\\.md|docs/tasks/266_route_no_replay_and_prof\\.md)$' | ( ! grep . ) && git diff --quiet round-46-base HEAD -- docs/tasks && for t in test_route_no_replay test_route_prof test_route_budget test_route test_route_ticks test_ckpt test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane266-tests-ok", "expect_exit": 0, "expect_regex": "lane266-tests-ok", "timeout_s": 3000}
{"name": "lane266-fast", "command": "out=$(lua5.2 tests/test_route_no_replay.lua 2>&1; lua5.2 tests/test_route_prof.lua 2>&1); for c in NR1 NR2 RP1 RP2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; n=$(echo \"$out\" | grep -c ' 0 failed'); [ \"$n\" = 2 ] && echo lane266-ok", "expect_exit": 0, "expect_regex": "lane266-ok", "timeout_s": 900}
```

# bound: 3000s
