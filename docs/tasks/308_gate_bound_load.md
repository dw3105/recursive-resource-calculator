# 308_gate_bound_load: round 56 gate tool: tick cost model, gate rows, proof-checked baseline writer, offline box binding loader

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-308`, branch `lane/308`,
base tag `round-56-base` (the commit that holds this task file), merge target `int/r56`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until every check below passes. Commit early, commit again, run the check LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua` on a sheet, `tools/game_test.sh`,
`tools/turn_flip_census.sh`, `tools/ckpt.lua save`, `tests/golden/generate.lua`, `factorio`,
`tests/test_turn_flip_census.lua`, `tests/test_drawn_e2e.lua`, `tests/test_collector_trial.lua`, any `*_delivers.lua`,
or any full suite, census, whole golden sheet or headless run of any kind.** Single test files only:
`timeout 100 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4), each under 60 s. Never use `coroutine` or
`math.random`. `require` only at file top level. **No game item or entity name in `logic/`.** Deterministic: fixed
order, ties broken by id string. Every new test must FAIL on the base code (say so in its header comment, date
2026-10-04); commit it red first, then the code. Each new test prints its marker (e.g. `TC1`) at the end of its
passing case.

Read `CONTEXT.md` first (**Tick cost**, **Box binding**, **Bytes baseline**, **Accepted DIFF**, **Parity row**, **Speed tie**) and `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`.
Evidence and the in-memory probe patches this lane ports: `docs/tasks/r56_probes/` (tt.lua, p_units.lua, fit4.py, ckpt_game_tick_tt.diff, bind_input.py, p11.lua, 06-tail-ticks.md, 11-blue-drift.md).

## Slice rule (frozen, every lane that slices)

A sliced call keeps a cursor in its work table, charges `budget.ops` at least 1 per unit of real work (named per
item below), returns when `budget.ops <= 0`, and resumes on the next call with the same result. A slice never
changes iteration order: final result byte-identical to the one-shot call. Game gives 2000 ops per tick
(`logic/jobs.lua:28`; never change it — the integrator raises it to 4000 after all lanes merge).

## What is true (explain very simply)

- The game probes each machine's fluid-box binding before search (`logic/bp/generation.lua:1197-1219`, only when
  `game` exists). Offline tools never do, so offline route has no fluid keepouts (`logic/bp/search.lua:1150`) and
  blue builds another layout offline than in game. Fixtures `tests/fixtures/box_binding_2.0.txt` /
  `box_binding_2.1.txt` hold the engine binding. `docs/tasks/r56_probes/bind_input.py` applies it to a prepared input
  (Python); offline route with it = engine 217/217 route events (ticket 11).
- Today's gate (`~/.claude/plans/rrc-round-55-probes/gate55.sh`) compares bytes sha only. No ticks, no worst tick,
  no proof check.
- Tick cost model (ADR 0003, fit legalcopilot-dev 2026-10-04): engine ms = 20.28 x M VM instructions + 1.58 x k
  `tostring` calls + 0.51. 50 ms = 2.44 M weighted instructions (instr + 78 x tostring). `r56_probes/tt.lua` +
  `ckpt_game_tick_tt.diff` count instructions and tostring per game tick in `tools/ckpt.lua`.

## What to build

1. `logic/bp/box_binding.lua`: add `BoxBinding.parse_fixture(path) -> table` (reads the fixture format) and
   `BoxBinding.apply_offline(prepared, version)` (version "2.0" default, "2.1"): fills the catalog binding exactly
   as `bind_input.py` does, only when the catalog carries none (bound catalog untouched). Game code paths unchanged.
2. Call `apply_offline` once in `tests/golden/generate.lua`, `tools/ckpt.lua`, `tools/first_stage.lua`,
   `tools/golden_profile.lua` after loading the prepared input (`RRC_BIND=0` turns it off for A/B).
3. `tools/tick_cost.lua`: `TickCost.of(instr, tostring_calls) -> ms`; reads per-tick lines and prints
   `TICK case=<id> tick=<n> instr=<n> ts=<n> ms=<x> phase=<p>` and `WORST case=<id> ms=<x> tick=<n> phase=<p>`.
   Per-tick counting hook in `tools/ckpt.lua` behind `RRC_TICK_COST=1` (port `ckpt_game_tick_tt.diff`).
4. `tools/gate56.sh <head-tree> <main-tree> <case> <layered|sugiyama>`: runs both trees back to back (same tool),
   prints `ROW case=<id> pack=<p> ticks=<n> worst_ms=<x> cpu_s=<x> sha=<8> valid=<ok|fail> main_cpu_s=<x>
   main_sha=<8> verdict=<SAME|DIFF|SLOWER|FAIL>`. SLOWER = not faster and not a **Speed tie**. Runner command is
   an env var (`GATE56_RUN`) so a test can stub it.
5. `tools/bytes_baseline.py <gate.log> <proof.log> <old baseline> <out>`: SAME rows copy; DIFF row needs a
   `PROOF case=<id> pack=<p> sha=<8> validate=ok lane_sim=0 lab=<rate>/<target> parity=<same|owed|drift>` line
   with matching sha, else exit 1 naming the row; writes `BYTES <case> <sha256>` lines.

## Tests

- `tests/test_tick_cost.lua`: TC1 three tick rows from `06-tail-ticks.md` (instr, tostring) -> ms within 0.1 of
  the formula; TC2 WORST line names max tick and phase.
- `tests/test_box_binding_offline.lua`: BO1 blue frozen route input `tests/fixtures/r56/blue_bound_route.json`
  catalog vs unbound `tests/golden/cases/player-blue-science-10s/prepared_input.json` + `apply_offline` -> same
  binding tables; BO2 already bound catalog untouched; BO3 version 2.1 reads 2.1 fixture.
- `tests/test_gate56.lua`: GT1 stub runner, same sha -> verdict SAME, ROW format exact; GT2 different sha + slower
  cpu -> SLOWER.
- `tests/test_bytes_baseline.py`: BB1 DIFF without PROOF -> exit 1 names case; BB2 SAME copied; BB3 DIFF with proof
  -> new sha line. Print markers BB1..BB3.

## Files this lane owns

`logic/bp/box_binding.lua` (new functions only), `tools/gate56.sh`, `tools/tick_cost.lua`, `tools/bytes_baseline.py`,
`tests/golden/generate.lua`, `tools/ckpt.lua`, `tools/first_stage.lua`, `tools/golden_profile.lua` (one call each +
RRC_TICK_COST hook in ckpt.lua), `tests/test_tick_cost.lua`, `tests/test_box_binding_offline.lua`, `tests/test_gate56.lua`,
`tests/test_bytes_baseline.py`, `tests/fixtures/r56/308/`.

## Integrator-proven (not yours; do not try)

Real gate rows on 14 + 14 sheets; bound main baselines; engine sample calibration.

## Commit, THEN check

Commit on `lane/308`. **Run the check as the very LAST action.**

## What done mean

- TC1, TC2, BO1, BO2, BO3, GT1, GT2, BB1, BB2, BB3 pass and print markers.
- Existing `test_box_binding`, `test_ckpt`, `test_golden_profile`, `test_slow_guard`, `test_force_turn_flip`, `test_material_cost` green.
- Game path unchanged: no file under `logic/` changed except `box_binding.lua`; no call of `apply_offline` from `logic/`.
- Diff only inside owned files; guards green.

```checks
{"name": "lane308-check", "command": "sh tools/lane_check_r56.sh 308", "expect_exit": 0, "expect_regex": "lane308-ok", "timeout_s": 3000}
```
