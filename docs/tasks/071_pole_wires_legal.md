# 071 — Every wire a pole gets is legal, and the network is one piece

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-071`, branch `lane/071`, base tag `validator-rejection-base` (resolve with `git rev-parse validator-rejection-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/power.lua`, `tests/test_power.lua`, `tests/test_power_semantics.lua`, `tests/test_power_budget.lua` and new `tests/test_power_wires.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority here. Never weaken a validator rule to make a layout pass. If you believe a validator rule is wrong, stop and report it with the smallest layout that shows it.
- `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/route.lua`, `logic/bp/search.lua` and `logic/bp/serialize.lua` are frozen.
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

You own `BP_V_WIRE_ILLEGAL` and `BP_V_WIRE_DISCONNECTED`. The other three belong to another lane, and their
candidates will change under you; judge your own codes, never the totals.

Run it yourself:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

The terminal failure carries `reason_details`, one entry per code with its count.

`logic/bp/validate.lua` checks each wire edge before it checks connectivity. An edge is legal only when both
endpoints exist, both connectors are copper power connectors, the connector kinds are compatible, and the centre
distance is at most the smaller of the two poles' `get_max_wire_distance` **at each pole's own quality**. An edge
failing any of those is `BP_V_WIRE_ILLEGAL`. The electrical graph is then built from surviving edges only, and
must be one component over all poles, which is `BP_V_WIRE_DISCONNECTED`.

The pole stage recently became resumable, and it emits both poles and the wire edges between them. A component
frontier is maintained rather than rebuilt. Check whether the edges it emits still measure reach the way the
validator does, in world centres and at each pole's own quality, and whether an edge survives the pruning pass
that removes a redundant pole.

## What to build

Drive both counts to zero, with the validator untouched.

1. Emit only edges the validator would accept: copper connectors, compatible kinds, and centre distance inside
   the smaller quality-aware reach.
2. Keep the surviving edge set connected over every placed pole. Removing a redundant pole must never orphan one.
3. Report failure to connect within the bound as failure to find a layout within limits, never as proof that none
   exists.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout validator-rejection-base -- logic/bp/power.lua; out=$(cd \"$S\" && lua5.2 tests/test_power_wires.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_power.lua && lua5.4 tests/test_power.lua && lua5.2 tests/test_power_semantics.lua && lua5.4 tests/test_power_semantics.lua && lua5.2 tests/test_power_budget.lua && lua5.4 tests/test_power_budget.lua && lua5.2 tests/test_power_wires.lua && lua5.4 tests/test_power_wires.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "validator-untouched", "command": "git diff --name-only validator-rejection-base HEAD | grep -qE '^logic/bp/(validate|serialize|route|search|groups|pack)\\.lua$' && exit 1; echo validator-untouched", "expect_exit": 0, "expect_regex": "validator-untouched", "timeout_s": 120}
{"name": "no-wire-rejection", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_WIRE_(ILLEGAL|DISCONNECTED)' && exit 1; echo no-wire-rejection", "expect_exit": 0, "expect_regex": "no-wire-rejection", "timeout_s": 900}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base validator-rejection-base --manifest docs/tasks/071.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_power_wires.lua` must contain, at least: an edge exactly at the reach boundary, which stays legal; an
edge one unit beyond it, which is never emitted; two poles of different qualities whose reaches differ, measured
at each pole's own quality; a pruning pass that must not orphan a pole; and a genuinely unconnectable set, which
terminates with a bounded failure.

## Files this lane owns

`logic/bp/power.lua`, `tests/test_power.lua`, `tests/test_power_semantics.lua`, `tests/test_power_budget.lua`, `tests/test_power_wires.lua`.

# bound: 1918s
