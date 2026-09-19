# 072 — Nothing overlaps, every machine keeps its beacons, every port keeps its edge

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-072`, branch `lane/072`, base tag `validator-rejection-2-base` (resolve with `git rev-parse validator-rejection-2-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_port_edges.lua` and new `tests/test_placement_contract.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass. If a validator rule looks wrong, stop and report it with the smallest layout that shows it.
- `logic/bp/route.lua` has another owner right now. `logic/bp/search.lua`, `logic/bp/power.lua` and `logic/bp/serialize.lua` are frozen.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

The player's fixture reaches validation and every candidate is refused there. Measured on this base, host
`legalcopilot-dev`, 2026-09-19, twelve grid trials:

```text
BP_V_COLLISION              30
BP_V_BEACON_COVERAGE_SHORT  21
BP_V_PORT_EDGE_WRONG        21
BP_V_UNDERGROUND_UNPAIRED    6
```

You own the first three. The last belongs to another lane.

Run it yourself:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

The terminal failure prints `reason_details`, one entry per code with its count, so each number is visible as it
falls. A previous lane took `BP_V_PORT_EDGE_WRONG` from 147 to 21 and `BP_V_COLLISION` from 33 to 30, so what
remains is a different case from the one already fixed, never a repeat of it. Find the case before changing
arithmetic.

`BP_V_COLLISION` is exact collision-box overlap, not tile-envelope overlap. `BP_V_BEACON_COVERAGE_SHORT` means a
machine receives fewer beacons of a group than its setup asks for, judged on the **placed** layout.
`BP_V_PORT_EDGE_WRONG` is the validator's own edge rule in the placed frame: `(attach_dx == -1 or attach_dx == w)
and 0 <= attach_dy < h`, or the same with the axes swapped.

## What to build

Drive all three counts to zero with the validator untouched.

1. Find which entity pairs collide and in which rotation. Beacons, inserters and machines each have their own
   rectangle; a rotated block's envelope is not one of them.
2. Beacon coverage must hold after placement and rotation, not only in the unplaced block.
3. The residual port-edge cases: name the rotation and the block shape that still breaks, and fix that shape.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout validator-rejection-2-base -- logic/bp/groups.lua logic/bp/pack.lua; out=$(cd \"$S\" && lua5.2 tests/test_placement_contract.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.4 tests/test_groups.lua && lua5.2 tests/test_pack.lua && lua5.4 tests/test_pack.lua && lua5.2 tests/test_port_edges.lua && lua5.4 tests/test_port_edges.lua && lua5.2 tests/test_placement_contract.lua && lua5.4 tests/test_placement_contract.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "validator-untouched", "command": "git diff --name-only validator-rejection-2-base HEAD | grep -qE '^logic/bp/(validate|serialize|route|search|power)\\.lua$' && exit 1; echo validator-untouched", "expect_exit": 0, "expect_regex": "validator-untouched", "timeout_s": 120}
{"name": "three-codes-gone", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_COLLISION|BP_V_BEACON_COVERAGE_SHORT|BP_V_PORT_EDGE_WRONG' && exit 1; echo three-codes-gone", "expect_exit": 0, "expect_regex": "three-codes-gone", "timeout_s": 900}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base validator-rejection-2-base --manifest docs/tasks/072.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_placement_contract.lua` must check a placed block with an independently written predicate, never the
producer's helper: no two entity boxes overlap in any of the four directions; every machine keeps its required
beacon count; every port satisfies the edge rule.

## Files this lane owns

`logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_port_edges.lua`, `tests/test_placement_contract.lua`.

# bound: 1918s
