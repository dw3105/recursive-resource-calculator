# 265_route_tidy_no_waste tidy never repeats a trial in an unchanged world and never copies state for a trial that can not start

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-265`, branch `lane/265`,
base tag `round-46-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/ckpt.lua save`, `tools/ckpt.lua uninterrupted`, `factorio`, or any full suite, whole sheet or headless run of
any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
`lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/<fixture>` (seconds). Never use `coroutine`. `require`
only at file top level. **No game item or entity name in `logic/`.** Every new test must FAIL on the base code where
this task says "red on base" (say so in its header comment); commit it red first.

## Explain very simply

Tidy (`improve_begin` / `improve_step`, `logic/bp/route.lua` ~:4103-4263) re-routes each binding and keeps a new path
only when it is cheaper. It wastes most of its time (measured legalcopilot-dev 2026-09-28, lua5.2):
- T1 the retry list gets one entry PER REFUSED OPTION (`st.refused[#st.refused + 1] = st.wanted`, ~:4220), so one
  binding is retried N times in the same unchanged world: 37-79 % of all tidy search steps. Fix: while retrying,
  skip a binding already retried since the last kept re-route (`st.improved` unchanged). Patch text:
  `docs/tasks/r46_probes/p_dedupe.lua`.
- T2 at `trial_start` the whole state is copied (`route_snapshot`), THEN the lift inside `trial_start` finds the
  trial can not start (4407 of 4883 trials on stack1 run 0 steps). The answer is the same for every option of one
  binding in one world. Fix: pure `lift_check` (same test as `lift_binding` ~:3634, no mutation) BEFORE the copy;
  memo per binding in `st` as plain data (st is saved between ticks: no function, no metatable), reset when
  `st.index`, `st.improved` or `st.order` changes; skipped option costs 1 op and moves on exactly as the probe.
  Patch text: `docs/tasks/r46_probes/p_liftskip.lua` (it uses `_G.__cannot_start` — turn that into a module local).
- T3 `all_bindings_reach_sinks` (~:1732) walks one chain per binding; many bindings share source + flow. Fix: one
  walk per (source tile, flow), test each sink against the reached set. Patch text: `docs/tasks/r46_probes/p_reach.lua`.
  Keep the old `nil source/sink -> false` behaviour.
Measured with T1+T2+T3 in memory: green tidy trial steps 171,842 -> < 40,000; ins10 2nd tidy snapshots
3103 -> 488; stack1 tidy 159 s -> 6.5 s; canonical sha of all 13 golden sheets unchanged.

Counters in `work.counters` (plain numbers): `trials_run`, `trials_skipped_repeat`, `trials_skipped_cannot_start`,
`trial_steps`, `route_snapshots` (increment inside `route_snapshot`). `_G.__P` from the probes must NOT reach the repo.

Probe usage: `lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/green_tidy.lua.gz [--patch f.lua] [--output r.json]`
prints at END `ticks=... sha=... entities=...`. Chain several probes: `PATCHES=a.lua,b.lua ... --patch
docs/tasks/r46_probes/p_combo.lua`. Base digests: `tests/fixtures/route_snaps/r46_digests.txt`. To read counters,
use `--until phase=validate --save out.lua.gz` then `require("tools.lib.graph_dump").load(path).state.work.counters`.

## What to build

1. `tests/test_route_improve_waste.lua` (`package.path = "./?.lua;" .. package.path`; subprocess via `io.popen` ok):
   - IW1 resume `green_tidy.lua.gz` to END: `sha=6b65a1d1c6408dc4d805159f33345d2b8b901da398ffc3ca846d2f6f6d464976`,
     ticks <= 700 (base 1444), and (via `--until phase=validate --save`) `trial_steps` <= 40,000. Red on base.
   - IW2 resume `ins10_tidy2.lua.gz` to END: `sha=00cee6970e7757c4fe7039f946a0bda80e6be6a866e431798b769207545b9103`;
     `route_snapshots` counted in tidy <= 600 (base 3103). Red on base.
   - IW3 unit case, 2 bindings: after a kept re-route (`st.improved` grows) a binding already retried IS retried again.
   - IW4 unit case: `lift_check` never mutates `work` (deep compare before / after) and agrees with `lift_binding`
     on a refusing and on an accepting binding.
2. `logic/bp/route.lua`: T1 T2 T3 + counters, short comments with measured numbers + date.
3. Also run and keep green: `test_route_improve`, `test_route_hop`, `test_route_hop_multi`, `test_route_hand_slide`,
   `test_route_ticks`, `test_route`.

## Files this lane owns

logic/bp/route.lua (ONLY `route_snapshot` counter line, `all_bindings_reach_sinks` ~:1732-1739, new `lift_check`
beside `lift_binding` ~:3634, `improve_begin`/`improve_step` ~:4103-4263), tests/test_route_improve_waste.lua,
docs/tasks/265_route_tidy_no_waste.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/265`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane265-tests", "command": "git diff --name-only round-46-base HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_improve_waste\\.lua|docs/tasks/265_route_tidy_no_waste\\.md)$' | ( ! grep . ) && git diff --quiet round-46-base HEAD -- docs/tasks && for t in test_route_improve_waste test_route_improve test_route_hop test_route_hop_multi test_route_hand_slide test_route_ticks test_route test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane265-tests-ok", "expect_exit": 0, "expect_regex": "lane265-tests-ok", "timeout_s": 3000}
{"name": "lane265-fast", "command": "out=$(lua5.2 tests/test_route_improve_waste.lua 2>&1); for c in IW1 IW2 IW3 IW4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane265-ok", "expect_exit": 0, "expect_regex": "lane265-ok", "timeout_s": 900}
```

# bound: 3000s
