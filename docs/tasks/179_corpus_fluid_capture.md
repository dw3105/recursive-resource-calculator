# 179 tests: test_corpus_setups fluid-byproduct-chain capture finishes

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-179`, branch
`lane/179`, base tag `round-25-fix2`, merge target `int/r25`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 35 minutes — do NOT stop early

Commit early, commit again, then run the checks LAST. Stopping with uncommitted work is a failed lane.

**NEVER run `tests/run.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full suite.** Run only
the single test files named here, one at a time, with `lua5.2 tests/<file>.lua` and `lua5.4 tests/<file>.lua`,
and the quick probe `sh tools/first_verdict.sh` (about 12 s).

## Explain very simply

The whole test suite must be green before this work merges to `main`. One old test file is still red. Find
the real cause, fix it, and prove the fix with that one file. A test that asserts the wrong thing is fixed in
the test with a comment naming the measurement; a real bug is fixed in the code. Never loosen an assertion
just to make it pass.

The machine buffer-zone rule (`logic/bp/buffer.lua`, read it) is new and correct: two different machines need
both rings of empty tiles between them; the same machine and recipe may share ring space in one row or column.

## The red rows

`tests/test_corpus_setups.lua` "fluid-byproduct-chain setup and pre-layout graph are truthful" (both shapes: 2
failures; 10 of 12 pass): `tests/test_corpus_setups.lua:56: capture stopped in phase pack after 700 ticks: tick
bound reached`. The file takes several minutes per interpreter.

Background measured 2026-09-23 on legalcopilot-dev: the game drives generation with 2000 ops per tick; since
round 23 `Pack.step` charges ops per origin tried (`PORT_ORIGIN_OPS = 16` in `logic/bp/pack.lua`), and packing
costs several seconds of CPU per layout, so a pack phase can need hundreds of ticks.

## What to build

1. Measure: how many ticks and how much CPU the fluid chain's pack phase needs (temporary counters). Find where
   the 700-tick bound lives (the capture helper) and what it is meant to prove.
2. Fix the cause, in this order of preference: (a) make `Pack.step` do less work for the same placements
   (for example index free cells, skip origins that cannot beat the current best; placements must be
   IDENTICAL, prove with the pack tests); (b) only if the test's bound is a test-only safety net that the
   product never uses, raise it in the test with a comment naming the measurement.
3. Both rows green on both interpreters; `tests/test_pack.lua`, `tests/test_pack_budget.lua`,
   `tests/test_pack_buffer.lua`, `tests/test_port_edges.lua` stay green; `sh tools/first_verdict.sh` stays
   `ok=true`.

## Traps

- **Determinism** and **no coroutines, no closures in saved state** (`logic/jobs.lua:3`).
- **Never touch** `logic/bp/buffer.lua`, `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
  `docs/**` except this task, and any file not listed under "Files this lane owns".

## Files this lane owns

`tests/test_corpus_setups.lua`, `logic/bp/pack.lua`

## Commit, THEN check

Commit on `lane/179` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "corpus-rows", "command": "git diff --name-only round-25-fix2 HEAD | grep -v '^docs/tasks/179' | grep -Ev '^(tests/test_corpus_setups\\.lua|logic/bp/pack\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_corpus_setups test_pack test_pack_budget test_pack_buffer test_port_edges; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $l $t; exit 1; }; done; done && echo corpus-rows-ok", "expect_exit": 0, "expect_regex": "corpus-rows-ok", "timeout_s": 2400}
{"name": "corpus-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc179-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc179-first.txt && echo corpus-probe-ok", "expect_exit": 0, "expect_regex": "corpus-probe-ok", "timeout_s": 300}
```

# bound: 2400s
