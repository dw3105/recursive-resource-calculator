# 159 doors: an input enters next to the machines that consume it

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-159`, branch
`lane/159`, base tag `round-19-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**The player's rule, in their own words: an input enters as close as possible to the machines that consume
it.** Round 18's delivery breaks it, and that is why copper ore has to pass under iron ore.

Measured from the candidate's own ports 2026-09-22 on this host:

```
item/copper-ore   sinks at (1,24) (1,28)                 -- west side, mid height
item/iron-ore     sinks at (5,42) (9,42) (13,42) (17,42) -- along the bottom
```

Edge slots are handed out by `generated_perimeter_ports`, `logic/bp/search.lua:792-840`. It walks
`terminal_networks(state)` in whatever order that returns and gives each flow **the next free slot**:

```lua
local index = next_slot[role]
while index <= #slots[role] do
    local slot = slots[role][index]
    local key = perimeter_cell_key(slot.x, slot.y)
    if not occupied[key] and (not perimeter_port_needs_route(port) or not blocked[key]) then break end
    index = index + 1
end
next_slot[role] = index + 1
```

`next_slot` is a cursor that only ever moves forward. **Nothing looks at where that flow's machines are.**
So the flow processed first takes the nearest door and the other must cross it. The delivery pays for that
with **7 underground pairs against the player's 0**, and with belts: `item/iron-ore` 62,
`item/copper-ore` 25, 274 in total against the player's 84.

## Traps, each measured

**Trap: the goal is DISTANCE, never non-crossing.** Give each terminal the free slot nearest its own
consumers. Two runs that each go straight to their own machines have no reason to meet, so non-crossing
falls out on its own — and the belts shrink at the same time, which the crossing fix alone would not do.
A rule written as "avoid crossings" will pass a test and still leave the belts long.

**Trap: order matters, so serve the tightest need first.** A flow with one distant consumer and a flow with
four nearby ones are not symmetric. Decide the order, state it in the lane report, and make it
**deterministic** — the search's `coord_key` tiebreak and `tests/test_route_budget.lua` both depend on the
result being reproducible run to run.

**Trap: a slot may be refused.** `perimeter_port_needs_route(port)` and `blocked[key]` already skip slots
that cannot be routed to, and `generated_perimeter_ports` returns `external, false` when it runs out. Keep
both behaviours: **running out must still fail by name**, never silently reuse a slot.

**Trap: `terminals_for_demand` may ask for SEVERAL copies of one terminal** (`sizing_result.count`, used at
`local requested = sizing_result.count`). All copies of one flow should land together, near that flow's
machines, never scattered.

**Trap: in and out are separate slot lists.** `slots["in"]` and `slots["out"]` come from different edges
(`input_edge`, `output_edge`). The rule applies to each list on its own.

**Trap: do not touch the roboport lattice or the comparator.** Those are the spine's, in wave 2. This lane
changes only which flow gets which door.

PRESERVE: `logic/bp/route.lua`, `logic/bp/validate.lua`, `logic/bp/groups.lua`, `logic/bp/serialize.lua`,
`logic/bp/pack.lua`, `tools/**`, `tests/**` except `tests/test_demand_terminals.lua`, `docs/**`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

## Files this lane owns

`logic/bp/search.lua`, `tests/test_demand_terminals.lua`.

## What to build

1. **Give every terminal the free edge slot NEAREST its own consumers**, in `generated_perimeter_ports`.
   The consumers of a flow are the block ports that sink it; their tiles are already in `state.work`.
2. **One row in `tests/test_demand_terminals.lua`, red at base**: a fixture with two flows whose machines sit
   in the opposite order to the loop's, asserting each door lands nearest its own consumers. Today's cursor
   gives them each other's doors.
3. **Report the measured effect on the player's sheet**, before and after: underground pairs (**today 7**),
   belts per flow (**today `item/iron-ore` 62, `item/copper-ore` 25**) and total transport entities
   (**today 297**). Use the 25-second candidate probe, never the full sheet.

**An edit that changes none of those numbers is complexity shipped on a guess, and gets reverted.**

## What done mean

```checks
{"name": "input-doors", "command": "git diff --name-only round-19-base HEAD | grep -v '^docs/tasks/159' | grep -Ev '^(logic/bp/search\\.lua|tests/test_demand_terminals\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_demand_terminals.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_external_ports.lua 2>&1 | tail -1 | grep -q '14 passed, 0 failed' || exit 1; $l tests/test_route_budget.lua 2>&1 | tail -1 | grep -q '8 passed, 0 failed' || exit 1; $l tests/test_validate.lua 2>&1 | tail -1 | grep -q '44 passed, 0 failed' || exit 1; done && echo input-doors-ok", "expect_exit": 0, "expect_regex": "input-doors-ok", "timeout_s": 1800}
{"name": "red-at-base", "command": "set -e; base=$(mktemp -d); git worktree add -q --detach \"$base\" round-19-base; cp tests/test_demand_terminals.lua \"$base/tests/test_demand_terminals.lua\"; cd \"$base\"; fail=0; lua5.2 tests/test_demand_terminals.lua 2>&1 | tail -1 | grep -q ' 0 failed' && fail=1 || true; cd - >/dev/null; git worktree remove --force \"$base\"; [ \"$fail\" = 0 ] || { echo 'the new row is GREEN at round-19-base, where the cursor hands out doors in loop order; it proves nothing'; exit 1; }; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 1200}
```

Re-cut because: none

# bound: 4000s

Reviewer ask: does every terminal land nearest its OWN consumers, is the order deterministic, and did the
underground count on the player's sheet actually move from 7?
