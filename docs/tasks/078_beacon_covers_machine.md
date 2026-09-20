# 078 — A placed beacon still covers the machine it was built for

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-078`, branch `lane/078`, base tag `last-two-codes-base` (resolve with `git rev-parse last-two-codes-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `tests/test_groups.lua` and new `tests/test_beacon_coverage.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/route.lua` has another owner right now. `logic/bp/pack.lua`, `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- **`tests/test_search.lua` and `tests/test_blueprint_pipeline.lua` must stay green.** Reserving tiles a block does not occupy was refused twice on this branch; it breaks small feasible plans.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_beacon_coverage.lua` first, before changing the module.**

Two codes remain on the player's fixture. Yours is the second, measured host `legalcopilot-dev`, 2026-09-20:

```text
BP_V_BEACON_COVERAGE_SHORT  21
BP_V_PORT_EDGE_WRONG        21
```

Every instance names a machine that should receive one beacon and receives none:

```text
BEACONSHORT machine=m:machine:cable:1   group=beacon required=1 got=0
BEACONSHORT machine=m:machine:cable:2   group=beacon required=1 got=0
BEACONSHORT machine=m:machine:circuit:1 group=beacon required=1 got=0
```

Those three machines are the beacon-sharing steps of the fixture: `cable` and `circuit` share one block, each
asks for one beacon of group `beacon`, and the placed layout gives them zero. `logic/bp/validate.lua` judges this
on the **placed** layout, from the beacon's supply area against the machine's own rectangle, after rotation.
`logic/bp/groups.lua` computes `beacon_coverage` on the unplaced block with its own `covers` predicate. Establish
which of the two disagrees, and in which rotation, before changing arithmetic.

Run it yourself and read the `DETAIL` lines:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

## What to build

Drive `BP_V_BEACON_COVERAGE_SHORT` to zero, with no tile reserved that a block does not occupy. Leave
`BP_V_PORT_EDGE_WRONG` alone; it has another owner and its count will move under you.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout last-two-codes-base -- logic/bp/groups.lua; out=$(cd \"$S\" && lua5.2 tests/test_beacon_coverage.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.4 tests/test_groups.lua && lua5.2 tests/test_beacon_coverage.lua && lua5.4 tests/test_beacon_coverage.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "search-and-pipeline-stay-green", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_pack.lua && lua5.2 tests/test_port_edges.lua && lua5.2 tests/test_placement_boxes.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "no-beacon-short", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_BEACON_COVERAGE_SHORT' && exit 1; echo no-beacon-short", "expect_exit": 0, "expect_regex": "no-beacon-short", "timeout_s": 900}
{"name": "fixture-still-terminates", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 900}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base last-two-codes-base --manifest docs/tasks/078.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_beacon_coverage.lua` checks a placed block with an independently written supply-area predicate, never
the producer's `covers`: a machine that asks for one beacon receives one in each of the four directions, a shared
beacon covers both machines that ask for it, and a beacon just out of range covers neither.

## Files this lane owns

`logic/bp/groups.lua`, `tests/test_groups.lua`, `tests/test_beacon_coverage.lua`.

# bound: 1918s
