# 147 route: one belt may carry two flows, and 28.8 still lays a continuation, never a fork

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-147`, branch
`lane/147`, base tag `round-16-wave4` (resolve with `git rev-parse round-16-wave4`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract `docs/feature-contracts.md` section 28, clauses 28.2 and 28.8. Ledger `docs/round-16-baseline.md`.
Frozen red list `docs/round-16-red-list.txt`.

One feature, `multi_flow_hands`, is built in three halves. Two halves read the shared switch:

```
logic/bp/groups.lua:22    local Flags = require "logic.bp.flags"
logic/bp/groups.lua:512   local multi_flow_hands = Flags.multi_flow_hands
logic/bp/validate.lua:15  local Flags = require "logic.bp.flags"
logic/bp/validate.lua:469 local multi_flow_hands = Flags.multi_flow_hands
```

**`logic/bp/route.lua` reads nothing.** `logic/bp/route.lua:652` is a literal `local multi_flow_hands = false`
and the file never requires `logic/bp/flags.lua`. Measured 2026-09-22 on this host: with the shared flag
forced on, `tests/test_route_chain.lua` is still `4 passed, 0 failed`, because route never saw the switch.
Route's half is completely untested today. That is this lane.

Wiring it makes three admission sites live:

```
logic/bp/route.lua:851  segment_allows            -- a belt with room takes a second flow
logic/bp/route.lua:943  splitter_cell_allowed     -- a foreign flow may claim a splitter's second tile
logic/bp/route.lua:989  merge_splitter_footprint  -- a foreign run may be absorbed
```

Measured consequence, `legalcopilot-dev` 2026-09-22, with the switch on:

```
tests/test_route_chain.lua:95   every binding has a directed same-flow chain: expected 0, got 2
tests/test_route_chain.lua:118  28.8 serves the column by continuation:      expected 0 splitters, got 4
```

Contract 28.8 was closed in wave 3 and says the branch is laid as a **continuation, never a fork**, measured
at 85 surface belts / 6 underground endpoints / **0 splitters** against a fork's 81/6/2. That rule must hold
whether a belt carries one flow or two. Two flows on one belt is 28.2 and is wanted; a splitter is not.

## Traps, each measured

**Trap: `LUA_INIT` reproduces the flipped world in seconds, with no edit and no worktree.** Use it for every
iteration instead of flipping `logic/bp/flags.lua`:

```sh
LUA_INIT='package.loaded["logic.bp.flags"]={multi_flow_hands=true}' lua5.2 tests/test_route_chain.lua
```

Works on `lua5.4` too (`LUA_INIT_5_4` is unset on this host). `tests/test_route_chain.lua` costs about **19 s**
per run. Budget accordingly; never run the census or the red list while iterating.

**Trap: `tests/test_feature_flags.lua:29-37` matches WHOLE SOURCE LINES.** After wiring, `route.lua` must
contain the exact lines `local Flags = require "logic.bp.flags"` and
`local multi_flow_hands = Flags.multi_flow_hands`, and must contain **no** whole line
`local multi_flow_hands = false` and **no** whole line `local multi_flow_hands = true`.

**Trap: the `_force_multi_flow_hands` seam in the other two modules can force ON but never OFF**, and that is
being fixed in the spine this session, NOT here. Route currently has no seam at all. Add one, and add it in
the tri-state shape so it never repeats the same defect:

```lua
local function multi_flow_hands_enabled(input)
    local forced = input and input._force_multi_flow_hands
    if forced ~= nil then return forced == true end
    return multi_flow_hands
end
```

`nil` means use the global, `true` forces on, `false` forces off. A seam that cannot force off makes every
"switch off" row silently read the global, which is exactly the defect that cost the last flip attempt.

**Trap: `segment_flow_count` has a fallback that leaks the two-flow ceiling.** `logic/bp/route.lua:1397-1403`
builds an explicit underground with a scalar `flow_id` and never calls `register_segment_flow`, so
`segment_flow_count` returns 1 through the `count == 0 and segment.flow_id ~= nil` arm at `:832`. A second
flow registered onto such a segment lands in a `flow_ids` table that does not contain the first, and the count
reports 1 where the truth is 2. Close it.

**Trap: `logic/bp/route.lua:1455` compares `segment.flow_id ~= demand.flow_id` raw** instead of using
`segment_has_flow`, so a segment whose scalar differs from a registered set member mis-sets `saw_fluid_mix`.
Close it. Pipes keep the single-flow rule — `:850` returns `"fluid_mix"` before the multi-flow test is ever
reached, and that ordering must not change.

**Trap: `share_trunk` at `logic/bp/route.lua:657` is a different switch** and is always `true`. It is
same-flow trunk sharing, closed in wave 3. Never confuse the two and never touch it.

**Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes**, so every `H.test` inside that loop counts
twice per interpreter. Both `lua5.2` and `lua5.4` must be green.

PRESERVE: `logic/bp/flags.lua`, `logic/bp/groups.lua`, `logic/bp/validate.lua`, `tests/harness.lua`,
`tests/test_feature_flags.lua`, `tests/test_hand_economy.lua`, `tests/test_physical_witness.lua`,
`tests/test_blueprint_physical_contract.lua`, `tests/test_census_codes_live.lua`, `tools/**`,
`docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`, `docs/feature-contracts.md`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/route.lua`, `tests/test_route_chain.lua`.

**Never flip `logic/bp/flags.lua`.** The spine flips it once, after this lane merges. This lane proves its
work with `LUA_INIT` and with its own `_force_multi_flow_hands` seam.

## What to build

**S1. Wire route to the one shared flag.** Replace the literal at `logic/bp/route.lua:652` with the same two
lines the other two modules carry, and add the tri-state seam above. Keep the existing comment block's
meaning; say in it that integration wired this on 2026-09-22.

**S2. Make 28.8 hold with two flows on one belt.** With the switch forced on, a second flow admitted onto a
trunk must still be served by a **continuation** — the belt runs straight through a served port tile into the
next sink's port tile — and must **never** build a splitter. Zero splitters, zero broken chains. The wave 3
trunk-seeding machinery (`route_chain_tiles`, `begin_search`'s seed loop) is the mechanism that already does
this for one flow; find why it stops applying when the trunk carries two, and fix that, rather than adding a
second mechanism beside it.

**Measure before editing.** Print the geometry with the switch forced on — which tiles carry two flows, which
demand reaches for a splitter, and at which tile the chain breaks — and record that one sentence in the lane
report. An edit that changes nothing measurable is complexity shipped on a guess and will be reverted.

**S3. Close the two latent gaps** named above: `:1397-1403` (explicit underground never registers its flow)
and `:1455` (raw scalar compare instead of `segment_has_flow`).

**S4. Prove it with `tests/test_route_chain.lua`.** Keep the four existing rows green unchanged with the
switch off. Add rows that drive the forced-on world through the new seam and assert, at minimum:

- **RC5** with the switch forced on, the frozen candidate routes with **0** splitters and **0** broken chains.
- **RC6** a belt carrying two flows is still witnessed for both: every binding has a directed chain over its
  own flow.
- **RC7** a third flow is refused onto a belt already carrying two. 28.2 says at most two, because a belt has
  two lanes.
- **RC8** the same geometry with the switch forced OFF is unchanged from today's measured numbers, so the
  seam really forces both ways.

Each row prints the counts it measured — surface belts, underground endpoints, splitters — so the next round
reads geometry from test output instead of rebuilding a probe.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them, so nine cheap
checks means nine trips to the back of a shared queue. Everything cheap is folded in with `&&`.

```checks
{"name": "route-flag-and-chain", "command": "grep -qx 'local Flags = require \"logic.bp.flags\"' logic/bp/route.lua && grep -qx 'local multi_flow_hands = Flags.multi_flow_hands' logic/bp/route.lua && ! grep -qx 'local multi_flow_hands = false' logic/bp/route.lua && ! grep -qx 'local multi_flow_hands = true' logic/bp/route.lua && sh tools/lane_rows.sh tests/test_route_chain.lua --min-cases 8 && for l in lua5.2 lua5.4; do $l tests/test_route_chain.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; LUA_INIT='package.loaded[\"logic.bp.flags\"]={multi_flow_hands=true}' $l tests/test_route_chain.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; $l tests/test_route.lua 2>&1 | tail -1 | grep -q '38 passed, 0 failed' || exit 1; $l tests/test_route_footprints.lua 2>&1 | tail -1 | grep -q '6 passed, 0 failed' || exit 1; $l tests/test_route_collision.lua 2>&1 | tail -1 | grep -q '8 passed, 0 failed' || exit 1; $l tests/test_route_network.lua 2>&1 | tail -1 | grep -q '14 passed, 0 failed' || exit 1; $l tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' || exit 1; done; echo route-flag-and-chain-ok", "expect_exit": 0, "expect_regex": "route-flag-and-chain-ok", "timeout_s": 1500}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-wave4 --manifest docs/tasks/147.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
