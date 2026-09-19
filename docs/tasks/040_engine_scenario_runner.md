# 040 — the companion runs a factory, not a proxy

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-040`, branch `lane/040`, base = `feat/round-8-blueprints`, tag `recovery-base` (resolve it with `git rev-parse recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Stream B of the recovery plan. Nobody on this host has Factorio, so your proof is the state machine and its unit
tests; the physical run is the user's, and it must be one documented command.

## What is true

**PRESERVE:**
- You own `tests/golden/engine/mod/` (every file), new `tests/test_engine_scenario.lua`, new `docs/engine-evidence/runner.md`. Everything else is frozen; if you need a change elsewhere, stop and report.
- Never edit `logic/engine_test_api.lua`: lane 039 owns it and is rewriting it now. Code against the frozen interface in `docs/feature-contracts.md` §17.
- `require` runs only while `control.lua` is parsed — that rule holds inside the companion mod too. 1.1.39 shipped that crash.
- `prototypes`, `game`, `settings` and prototype lists are **userdata**; ask `rawget(_G, "prototypes")`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- `tests/golden/engine/mod/control.lua` forwards remote calls and accepts an observation handed to it. It never builds a factory, never supplies inputs, never drains outputs and never samples a rate. An observation written that way measures nothing.
- The candidate exposes `rrc-engine-test` with `build_id`, `start_generation`, `generation_status`, `cancel_generation`, `preflight`, `export`, `canonical` (`docs/feature-contracts.md` §14, §17).
- Evidence schema v1 is already fixed: an observation carries `schema_version`, `case_id`, `outcome_kind` of `production` | `rejection` | `export`, `candidate_sha` from `build_id()`, `runner_revision`, engine version, active mods, force research, surface, and exactly one outcome block. The receipt is written on this host by `tools/evidence_receipt.py`.
- `tests/golden/engine/mod/info.json` names Factorio 2.0 only. COMP-01 needs both branches; packaging scripts belong to stream C, the manifest convention belongs to you.

## What to build

1. A tick-driven scenario controller: set up the declared environment and sheet, call `start_generation`, poll `generation_status` over ticks, build the returned blueprint with its recipes, modules, qualities and wires, supply every input port, provide power, drain every declared output and byproduct, warm up, sample, then write the observation.
2. Drive supply and drain **at the perimeter only**. Never insert an ingredient into a machine and never remove a product from one: that bypasses the belts and inserters under test. Record what was actually accepted and what actually left.
3. Measure with engine ticks. Bound every timeout. Make cancellation and cleanup reliable, and say in the document exactly what each timing measures.
4. Refuse before any work when `build_id().packaged` is false or `candidate_sha` differs from the case's expected SHA. Write a `production`, `rejection` or `export` observation with that outcome's fields and no other.
5. `tests/test_engine_scenario.lua`: state transitions, timeout, identity mismatch, a failed build, cancellation, warm-up and sample boundaries, and the rate arithmetic. These are cheap harness cases; they never claim physical throughput.
6. `docs/engine-evidence/runner.md`: the one command the user runs, what it prints, where the game writes the observation, and what to send back.
7. The companion must be packageable for 2.0 and 2.1: keep branch-dependent facts in one place.

## What done mean

```checks
{"name": "scenario-tests", "command": "lua5.2 tests/test_engine_scenario.lua && lua5.4 tests/test_engine_scenario.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "no-runtime-require", "command": "lua5.2 tests/test_no_runtime_require.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 300}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base recovery-base --manifest docs/tasks/040.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the state-machine cases red before the controller exists and green after.
- `git diff --stat recovery-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `tests/golden/engine/mod/`
- `tests/test_engine_scenario.lua`
- `docs/engine-evidence/runner.md`

Touch nothing else.

# bound: 2400s

Reviewer ask: does the companion build, supply, drain and sample, and refuse a development build before doing any of it?
