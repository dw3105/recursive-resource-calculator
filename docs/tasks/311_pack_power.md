# 311_pack_power: pack reject charged by real work; power pcov + pfast, consumer loop charge, publish split (pack.lua, power.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-311`, branch `lane/311`,
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
2026-10-04); commit it red first, then the code. Each new test prints its marker (e.g. `PR1`) at the end of its
passing case.

Read `CONTEXT.md` first (**Block**, **Layered pack**, **Tick cost**) and `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`.
Evidence and the in-memory probe patches this lane ports: `docs/tasks/r56_probes/` (p06.lua, power_prof.lua, split.lua, 17-pack-spikes.md, 06-cpu-levers.md).

## Slice rule (frozen, every lane that slices)

A sliced call keeps a cursor in its work table, charges `budget.ops` at least 1 per unit of real work (named per
item below), returns when `budget.ops <= 0`, and resumes on the next call with the same result. A slice never
changes iteration order: final result byte-identical to the one-shot call. Game gives 2000 ops per tick
(`logic/jobs.lua:28`; never change it — the integrator raises it to 4000 after all lanes merge).

## What is true (explain very simply)

- `layered_legal` (`logic/bp/pack.lua:718`) rejects a spot charged 1 op while scanning every placed buffer zone
  (`buffer_zones_fit` `:101`); loop `:771`. Pack ticks 36-282 ms (ticket 17).
- Power consumer loop (`logic/bp/power.lua:1016`) charges 4 ops per round however many consumers; publish finish
  (`:988`) runs up to 2000 ops of work as one 154 ms tick.
- `p06.lua` levers pcov + pfast (power coverage cache, fast pole scan): power instr -23..-31%, red-green power span
  -39..-47%, bytes same (ticket 06).

## What to build

1. Pack: charge ops by buffer zones scanned in a reject (unit = one zone), so a reject scan resumes.
2. Power: port pcov + pfast from `p06.lua`; consumer loop charges 1 op per consumer; publish finish spread over
   ticks per Slice rule.

## Tests

- `tests/test_pack_reject_charge.lua`: PR1 a reject that scans N zones charges >= N ops; PR2 placements on
  `tests/fixtures/r56/blue_bound_pack.json` at 2000 ops == base.
- `tests/test_power_fast.lua`: PF1 power result on `tests/fixtures/r56/blue_bound_power.json` +
  `tests/fixtures/power_r10s_drawn_state.lua.gz` == base; PF2 consumer loop 1 op per consumer; PF3 publish finish
  resumed over several calls == one-shot.

## Files this lane owns

`logic/bp/pack.lua`, `logic/bp/power.lua`, `tests/test_pack_reject_charge.lua`, `tests/test_power_fast.lua`,
`tests/fixtures/r56/311/`.

## Integrator-proven (not yours; do not try)

Pack + power worst tick rows on all 14 sheets; power CPU per sheet.

## Commit, THEN check

Commit on `lane/311`. **Run the check as the very LAST action.**

## What done mean

- PR1, PR2, PF1, PF2, PF3 pass and print markers; red on base.
- Every pack and power test listed in `tools/lane_check_r56.sh` (R311) green.
- Diff only inside owned files; guards green.

```checks
{"name": "lane311-check", "command": "sh tools/lane_check_r56.sh 311", "expect_exit": 0, "expect_regex": "lane311-ok", "timeout_s": 3000}
```
