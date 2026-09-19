# 070 — Every placed port sits on a legal edge tile, and nothing overlaps

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-070`, branch `lane/070`, base tag `validator-rejection-base` (resolve with `git rev-parse validator-rejection-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`, `tests/test_pack.lua` and new `tests/test_port_edges.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority here. Never weaken a validator rule to make a layout pass. If you believe a validator rule is wrong, stop and report it with the smallest layout that shows it.
- `logic/bp/route.lua`, `logic/bp/search.lua`, `logic/bp/power.lua` and `logic/bp/serialize.lua` are frozen.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

The player's fixture now reaches validation on every candidate and every candidate is refused there. Measured on
this base, host `legalcopilot-dev`, 2026-09-19, 12 grid trials, 18930116 operations, no incumbent at all:

```text
BP_V_PORT_EDGE_WRONG        147
BP_V_COLLISION               33
BP_V_WIRE_ILLEGAL            28
BP_V_BEACON_COVERAGE_SHORT   21
BP_V_WIRE_DISCONNECTED        7
```

You own the first, the second and the fourth. Wires belong to another lane.

Run it yourself:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

The terminal failure carries `reason_details`, one entry per code with its count, so you can watch each number
fall. `BP_V_PORT_EDGE_WRONG` is `logic/bp/validate.lua`'s check that a port's attach tile is one tile outside the
block, on a real edge: `(attach_dx == -1 or attach_dx == w) and 0 <= attach_dy < h`, or the same with the axes
swapped, in the **placed** frame. `BP_V_COLLISION` is exact box overlap, not tile envelope overlap.
`BP_V_BEACON_COVERAGE_SHORT` means a machine receives fewer beacons of a group than the setup asks for.

Blocks are rotated by `Grid.place_member` and `Grid.place_port`. A port's `attach_dx`, `attach_dy` live in the
block's own unrotated frame, while the block's placed envelope is the rotated size. That disagreement has already
produced two defects on this branch. Establish which frame each rule is written in before changing arithmetic.

## What to build

Drive the three counts to zero, in this order, keeping the validator untouched.

1. **Port edges.** A port slot chosen by `logic/bp/pack.lua` and a port placed by `logic/bp/groups.lua` must
   satisfy the validator's own edge rule after rotation, for every direction.
2. **Collisions.** Members, inserters and beacons must not overlap each other or a reserved cell once placed and
   rotated, by exact box, in every direction.
3. **Beacon coverage.** A machine that needs `count_per_machine` beacons of a group must receive them in the
   placed layout, not only in the unplaced block.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout validator-rejection-base -- logic/bp/groups.lua logic/bp/pack.lua; out=$(cd \"$S\" && lua5.2 tests/test_port_edges.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.4 tests/test_groups.lua && lua5.2 tests/test_pack.lua && lua5.4 tests/test_pack.lua && lua5.2 tests/test_port_edges.lua && lua5.4 tests/test_port_edges.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "validator-untouched", "command": "git diff --name-only validator-rejection-base HEAD | grep -qE '^logic/bp/(validate|serialize|route|search|power)\\.lua$' && exit 1; echo validator-untouched", "expect_exit": 0, "expect_regex": "validator-untouched", "timeout_s": 120}
{"name": "no-port-edge-rejection", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_PORT_EDGE_WRONG' && exit 1; echo no-port-edge-rejection", "expect_exit": 0, "expect_regex": "no-port-edge-rejection", "timeout_s": 900}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base validator-rejection-base --manifest docs/tasks/070.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_port_edges.lua` must contain, at least: a placed block in each of the four directions whose every
port satisfies the validator's edge rule, checked by an independently written predicate, never by calling the
producer's helper; a placed block whose members and beacons do not overlap by exact box in each direction; and a
beacon group whose coverage survives placement.

## Files this lane owns

`logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_port_edges.lua`.

# bound: 1918s
