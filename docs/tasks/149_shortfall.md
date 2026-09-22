# 149 shortfall: the finished science pack must reach the factory edge

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-149`, branch
`lane/149`, base tag `round-17-base` (resolve with `git rev-parse round-17-base`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Round 16 closed with the `multi_flow_hands` switch ON and both gates green, and **no blueprint delivered**.
`sh tools/deliver.sh player-red-science-1s` reports `ok=False`.

`state.ok` is a pure emptiness test on `work.errors` (`logic/bp/validate.lua:2117-2124`). **There is no
severity split. Every single record is fatal.** So one record is the difference between a blueprint and none.

Measured 2026-09-22 on this host, the FIRST candidate the search hands to the validator:

```
BP_V_ROUTE_DISCONTINUOUS   20
BP_V_TRANSPORT_UNUSED     257
BP_V_TARGET_SHORTFALL       1
ok=false
```

The 20 and the 257 are one cause — the validator cannot walk a splitter — and are being fixed in the spine
this session. **`BP_V_TARGET_SHORTFALL` is the record that will still be standing afterwards, and it is this
lane.** Its ids:

```
BP_V_TARGET_SHORTFALL ids=item/automation-science-pack,$external
```

The finished science pack does not reach the factory edge with its required rate.

**It is NOT a cascade of the walk failure.** `BP_V_TARGET_SHORTFALL` is emitted at
`logic/bp/validate.lua:1087` from `allocation_by_flow_sink`, which is built from **segment allocations**,
never from `transport_path`. Fixing the splitter walk will not touch it.

## Traps, each measured

**Trap: MEASURE BEFORE EDITING.** Two mechanisms fit today's evidence and nothing separates them yet:

1. A route demand was refused and turned into a shortfall by wave 3's `fail_demand`
   (`logic/bp/route.lua`), which sets `demand.unroutable` and `demand.remaining = 0`, so no allocation is
   ever recorded.
2. A route was laid and its allocation was never recorded against the `$external` sink — an `add_allocation`
   or `sink_key` mismatch.

Print which one, with the flow id, the required rate and the reached rate, **before** touching code. Round 16
shipped a fix on a guess and re-measured to find it had changed **nothing** — identical entity ids, identical
counts. It was reverted. An edit that changes nothing measurable is complexity shipped on a guess.

**Trap: the probe recipe is already in the tree, at `tools/route_chain_probe.sh:30-44`.** Slice
`tests/golden/generate.lua` at `local input_path,` with `awk` and append the probe body to the same chunk;
`JSON`, `sha256`, `read_file` and `captured_plan` stay in scope, and no file in the tree is edited. Drive
`Search` until `state.work.validate_candidate` is set. About **25 s** per candidate.

**Trap: `Validate.begin` needs the right field names.** Use
`Validate.begin{candidate = c, plan = state.work.plan_result, catalog = state.work.input.catalog}` — those are
what `logic/bp/search.lua:1480` passes. A wrong catalog crashes at `logic/bp/validate.lua:2005`, "attempt to
perform arithmetic on local 'capacity' (a nil value)".

**Trap: a shortfall may be CORRECT.** If the plan genuinely asks for more science pack than the layout can
carry, the honest answer is to fix the routing that under-delivers, never to silence the record. Never delete
or weaken the check at `logic/bp/validate.lua:1080-1090`.

**Trap: `logic/bp/validate.lua` is owned by the spine this session and is being edited RIGHT NOW.** Do not
touch it. If the fix genuinely belongs there, say so in the lane report and stop; do not edit it.

**Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes**, so every `H.test` inside that loop counts
twice per interpreter. Both `lua5.2` and `lua5.4` must be green.

PRESERVE: `logic/bp/validate.lua`, `logic/bp/groups.lua`, `logic/bp/flags.lua`, `logic/bp/search.lua`,
`tests/harness.lua`, `tools/**`, `docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`,
`docs/feature-contracts.md`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/route.lua`, `tests/test_route_chain.lua`.

## What to build

**S1. Name the mechanism in one sentence, with a flow and two rates.** Required versus reached, from the
validator's own `detail` table at `logic/bp/validate.lua:1087-1089`. Record it in the lane report.

**S2. Fix it in `logic/bp/route.lua`** so the first candidate reports `BP_V_TARGET_SHORTFALL` **0**.

**S3. Guard it in `tests/test_route_chain.lua`.** A row that fails if the science-pack flow stops being
allocated to its external sink. Keep the existing twelve rows green, both ways, both interpreters.

**S4. Report what it measured.** The candidate's code census before and after, as counts per code.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them, so nine cheap
checks means nine trips to the back of a shared queue. Everything cheap is folded in with `&&`.

```checks
{"name": "route-family-and-rows", "command": "git diff --name-only round-17-base HEAD | grep -v '^docs/tasks/149' | grep -vE '^(logic/bp/route\\.lua|tests/test_route_chain\\.lua)$' | ( ! grep . ) && sh tools/lane_rows.sh tests/test_route_chain.lua --min-cases 12 && for l in lua5.2 lua5.4; do $l tests/test_route_chain.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; $l tests/test_route.lua 2>&1 | tail -1 | grep -q '38 passed, 0 failed' || exit 1; $l tests/test_route_footprints.lua 2>&1 | tail -1 | grep -q '6 passed, 0 failed' || exit 1; $l tests/test_route_collision.lua 2>&1 | tail -1 | grep -q '8 passed, 0 failed' || exit 1; $l tests/test_route_network.lua 2>&1 | tail -1 | grep -q '14 passed, 0 failed' || exit 1; $l tests/test_route_layout_contract.lua 2>&1 | tail -1 | grep -q '12 passed, 0 failed' || exit 1; $l tests/test_underground_pairs.lua 2>&1 | tail -1 | grep -q '2 passed, 0 failed' || exit 1; $l tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' || exit 1; done; echo route-family-ok", "expect_exit": 0, "expect_regex": "route-family-ok", "timeout_s": 1500}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-17-base --manifest docs/tasks/149.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
