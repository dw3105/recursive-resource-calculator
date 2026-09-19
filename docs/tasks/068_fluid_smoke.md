# 068 — A fluid chain and a beacon-powered chain each have a smoke case

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-068`, branch `lane/068`, base tag `power-semantics-base` (resolve with `git rev-parse power-semantics-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own new `docs/tasks/068_fluid_smoke.lua`, new `docs/tasks/068_beacon_power_smoke.lua` and new `tests/test_smoke_chains.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/` is frozen in this lane. Never edit a module. You write cases and the test that runs them.
- `docs/tasks/058_reproducer.lua` is frozen. Read it, copy its shape, never edit it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Measured on this base, host `legalcopilot-dev`, 2026-09-19: `docs/tasks/058_reproducer.lua` is described as a
five-step sheet, but the routing input it produces carries **three calculated steps and no fluid flow at all**:

```text
grid 54x54  blocks 2  flows 5  ports 9  perimeter_ports 3
flows: item/cable, item/circuit, item/gear, item/machine, item/plate
steps: cable, circuit, machine
```

`plate` and `gear` arrive from outside, `machine` leaves outside, and the foundry and `molten-iron` it defines
never reach layout. So the one integration case the project leans on proves nothing about fluids, and nothing
about a beacon that needs its own power.

## What to build

Two new cases in the shape of `docs/tasks/058_reproducer.lua`, each **asserting its own graph before layout**:

1. `docs/tasks/068_fluid_smoke.lua` — a chain whose calculated steps include a fluid producer and a fluid
   consumer. Assert the step names and assert the flow list contains the fluid flows by full name, before
   generation starts. Small: two or three steps, one fluid, one item output.
2. `docs/tasks/068_beacon_power_smoke.lua` — a chain with a beacon far enough from its machines that the beacon
   needs a pole of its own. Assert the beacon exists in the plan before generation starts.

Each case prints one line `SMOKE <name> state=<state> stage=<stage> codes=<codes>` and asserts the terminal
state it expects **today**, with a comment naming the state it must reach when layout works. A case that fails
today is recorded as a positive case with its current failure, never relabelled a rejection.

`tests/test_smoke_chains.lua` runs both cases inside the harness and asserts their graph assertions hold. Keep
each case inside 60 seconds on this host.

## What done mean

```checks
{"name": "smoke-tests", "command": "lua5.2 tests/test_smoke_chains.lua && lua5.4 tests/test_smoke_chains.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "fluid-case-has-fluid", "command": "timeout 120 lua5.2 docs/tasks/068_fluid_smoke.lua 2>&1 | grep -E 'SMOKE|fluid/'", "expect_exit": 0, "expect_regex": "fluid/", "timeout_s": 200}
{"name": "beacon-case-has-beacon", "command": "timeout 120 lua5.2 docs/tasks/068_beacon_power_smoke.lua 2>&1 | grep -E 'SMOKE|beacon'", "expect_exit": 0, "expect_regex": "beacon", "timeout_s": 200}
{"name": "logic-untouched", "command": "git diff --name-only power-semantics-base HEAD | grep -q '^logic/' && exit 1; echo logic-untouched", "expect_exit": 0, "expect_regex": "logic-untouched", "timeout_s": 120}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base power-semantics-base --manifest docs/tasks/068.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

## Files this lane owns

`docs/tasks/068_fluid_smoke.lua`, `docs/tasks/068_beacon_power_smoke.lua`, `tests/test_smoke_chains.lua`.

# bound: 1918s
