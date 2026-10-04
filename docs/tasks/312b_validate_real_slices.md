# 312b_validate_real_slices: every Validate.step within one tick of Tick cost (validate.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-312`, branch `lane/312`,
base tag `round-56-312b-base` (the commit that holds this task file, on top of lane 312's own work), merge target
`int/r56`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until the check below passes. Commit early, commit again, run the check LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`, `tools/bytes_hash.sh`,
`tools/sheet_verdict.sh`, `tools/golden_profile.lua` on a sheet, `tools/game_test.sh`, `tools/turn_flip_census.sh`,
`tools/ckpt.lua save`, `tests/golden/generate.lua`, `factorio`, `tests/test_turn_flip_census.lua`,
`tests/test_drawn_e2e.lua`, `tests/test_collector_trial.lua`, any `*_delivers.lua`, or any full suite, census, whole
golden sheet or headless run of any kind.** Single test files only: `timeout 100 lua5.2 tests/<file>.lua` (lua5.2
ONLY), each under 60 s. Never `coroutine` or `math.random`. `require` only at file top level. No game item or entity
name in `logic/`. Deterministic. Every new test case must FAIL on the base commit (header comment says so, date
2026-10-04); commit it red first, then the code. Each case prints its marker at the end of its passing run.

Read `CONTEXT.md` (**Engine rule**, **Waste rule**, **Tick cost**), `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`,
`docs/tasks/r56_probes/06-tail-ticks.md` (validate spike classes), probe `docs/tasks/r56_probes/validate_tick_cost.lua`.

## What is true (explain very simply)

Lane 312's first pass (4790cf1..a18671e on this branch) failed its check, and review found it slices nothing:
`charge_whole_pass` banks ops over several ticks, then still runs the whole `check_beacons` / `check_fluid_mix` /
`check_transport_shapes` in ONE call. The tick that runs the pass costs the same as before.

Measured on legalcopilot-dev 2026-10-04 at base (round-56-base), 4000 ops per `Validate.step`, cost = instructions
+ 78 x `tostring` calls (probe `docs/tasks/r56_probes/validate_tick_cost.lua`; budget 2.44 M = 50 ms Tick cost):

| fixture | worst step | phase |
|---|---|---|
| tests/fixtures/validate_red_green_r40_c1.json | 4.71 M (96 ms) | port_approaches |
| tests/fixtures/validate_red10s_attempt1.json | 3.85 M (79 ms) | physical |
| tests/fixtures/validate_ins10s_v3_chain.json | 4.85 M (99 ms) | physical |

Charges today: `port_approaches` 20 ops per port; `physical` 500 ops per machine; one-shot passes (beacon, segments,
fluid_mix, underground, shapes) one whole pass per call. Blue spike map (06-tail-ticks.md): `check_physical_transfers`
(validate.lua:2331) 205 ms, `check_beacons` (:1071) 115, `check_transport_shapes` (:1590) 91, `check_fluid_mix`
(:2979) 51.

## What to build (in `logic/bp/validate.lua` only)

1. Every `Validate.step(state, {ops = 4000})` costs <= 2.44 M weighted instructions on the three fixtures above.
2. Get there by REAL slices: a cursor inside each heavy check (beacon, fluid mix, transport shapes, physical
   transfers per machine and inside one machine if one machine is too big, port approaches) so one call does a bounded
   part and the next call continues; and by charging ops in proportion to real work (unit = one entity / segment /
   transfer pair checked) so 4000 ops never buys more than one tick of work. Drop `charge_whole_pass`.
3. Same errors, same order, same codes, same verdict as base, at any ops per step (50, 2000, 4000, 100000).
4. Fewer ticks is better: do not over-charge (a pass that fits a tick stays one call).

## Tests (`tests/test_validate_slices.lua`; keep VS1-VS4 meaning, never weaken an assertion)

- VS1-VS4 codes + verdict equal base on the two lane-312 fixtures at 50 / 2000 / 4000 / 100000 ops.
- VS5 per unit charge (as before).
- VS6 worst `Validate.step` at 4000 ops <= 2.44 M weighted instructions (instr via `debug.sethook(f, "", 1000)`,
  1000 per fire, + 78 x wrapped `_G.tostring` calls) on all three fixtures in the table.
- VS7 `charge_whole_pass` gone; no phase runs a whole heavy check in one call (assert by step count > 1 for each heavy
  phase on `validate_ins10s_v3_chain.json` at 4000 ops, where base takes 1).

## Files this lane owns

`logic/bp/validate.lua`, `tests/test_validate_slices.lua`, `tests/fixtures/r56/312/`.

## Integrator-proven (not yours; do not try)

Validate worst tick on blue, magenta, stack1 whole sheets.

## Commit, THEN check

Commit on `lane/312`. **Run the check as the very LAST action.**

## What done mean

- VS1-VS7 pass and print markers; VS6 and VS7 red on `round-56-312b-base`.
- Every validate test listed in `tools/lane_check_r56.sh` (R312) green.
- Diff only inside owned files (vs `round-56-312b-base`); guards green.

```checks
{"name": "lane312b-check", "command": "sh tools/lane_check_r56.sh 312b", "expect_exit": 0, "expect_regex": "lane312b-ok", "timeout_s": 3000}
```
