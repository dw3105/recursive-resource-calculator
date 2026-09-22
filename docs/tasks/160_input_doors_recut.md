# 160 doors re-cut: an input enters next to its machines, AND the blueprint still ships

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-160`, branch
`lane/160`, base tag `round-19-doors-base` (resolve with `git rev-parse round-19-doors-base`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## Re-cut because

Lane 159 built the right rule and **destroyed the product**. Measured on this host 2026-09-22, in its own
worktree, full generation on the player's sheet:

```
lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json
ok=False   stage=failed   records=1 {'BP_FAIL_GRID_LIMIT': 1}   entities=0
```

**No blueprint at all**, where the tree it branched from delivers one with `verdict=accepted`. The candidate
probe shows why: one furnace is never fed.

```
BP_V_PORT_UNREACHABLE  iron-plate:in:item/iron-ore:inserter:iron-plate:4:input:1
                       reason=no binding uses this port as a sink
BP_V_INSERTER_GEOMETRY m:inserter:iron-plate:4:input:1, empty ground
BP_V_TRANSFER_BROKEN   m:machine:iron-plate:4, item/iron-ore, cause=missing_belt
BP_V_TRANSPORT_UNUSED  m:inserter:iron-plate:4:input:1 at (17,42)
```

Candidate 1 went from **0 records to 4**. The ore enters near the first furnace and the branch to the
fourth, at port `(17,42)`, never gets laid.

**Its geometry win was real and must be kept.** Same worktree, 25-second probe, against the tree it branched
from:

| flow | before | lane 159 |
|---|---|---|
| `item/iron-ore` belts | 62 | **17** |
| `item/copper-ore` belts | 25 | **14** |
| belts, total | 274 | **243** |
| splitters | 9 | **7** |
| underground endpoints | 14 | **18** |
| transport entities | 297 | **268** |

So: belts down 31, transport down 29, **undergrounds UP 4**, and one machine starved.

## What is true

**The player's rule: an input enters as close as possible to the machines that consume it.**

`generated_perimeter_ports`, `logic/bp/search.lua:792-840`, hands each flow **the next free slot** from a
cursor that only moves forward, and never looks at where that flow's machines are. That is why copper ore
had to pass under iron ore.

**Lane 159's shape is worth keeping and is in `lane/159`**, unmerged: `terminal_consumers` finds the block
ports that sink a flow, `slot_cost` sums manhattan distance from a slot to them, networks are sorted by
tightest need first with a deterministic `key` tiebreak, and each copy takes the cheapest free slot.
`git show lane/159 -- logic/bp/search.lua` is the starting point. **Start from it, do not start over.**

## Traps, each measured

**Trap: the product must still ship. This is the bar lane 159 missed.** After the change, on the player's
sheet: candidate 1 stays at **0 records** with `ok=true`, and full generation still returns `ok=true` with
a non-empty `result.entities`. Measure both, report both numbers, and **if the change cannot hold them,
say so and leave the rule unimplemented rather than shipping a factory with a starved machine.**

**Trap: a nearer door is worthless if the branch to the furthest machine cannot be laid.** Four furnaces sit
at ports `(5,42) (9,42) (13,42) (17,42)`. A door beside the first leaves the run to `(17,42)` to be built,
and contract 28.8 says that branch is laid as a continuation through each port tile in turn. **Consider the
whole set of consumers, never just the nearest** — `slot_cost` already sums over all of them, so look first
at whether the ORDER of networks, or `terminals_for_demand`'s copy count, is what starved it.

**Trap: undergrounds went UP.** Shorter, denser runs meet each other more often. The player's factory has
**zero** undergrounds; 18 is worse than 14. Report the number. If the rule cannot hold it at or below 14,
say so plainly — `tests/test_route_waste.lua` RW3 and `tests/test_route_chain.lua` RC2/RC8 are already red
on this tree for exactly that waste, and this lane is the one meant to close them.

**Trap: determinism.** `coord_key` and `tests/test_route_budget.lua` both depend on the same input giving
the same layout. Every ordering decision needs an explicit, total tiebreak.

**Trap: a slot may be refused.** `perimeter_port_needs_route(port)` and `blocked[key]` skip slots that
cannot be routed to, and running out must still `return external, false` and fail by name.

**Trap: `terminals_for_demand` may ask for SEVERAL copies of one terminal.** All copies of one flow land
together, near that flow's machines, never scattered.

**Trap: in and out use different edges.** `slots["in"]` and `slots["out"]` are separate lists; the rule
applies to each on its own.

PRESERVE: `logic/bp/route.lua`, `logic/bp/validate.lua`, `logic/bp/groups.lua`, `logic/bp/serialize.lua`,
`logic/bp/pack.lua`, `tools/**`, `tests/**` except `tests/test_demand_terminals.lua`, `docs/**`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

## Files this lane owns

`logic/bp/search.lua`, `tests/test_demand_terminals.lua`.

## What to build

1. The rule, starting from `lane/159`'s code: every terminal takes the free edge slot nearest its own
   consumers, tightest need first, deterministic throughout.
2. **Whatever it takes to keep every machine fed.** That is the deliverable, not an optional extra.
3. One row in `tests/test_demand_terminals.lua`, **red at `round-19-doors-base`**: two flows whose machines
   sit in the opposite order to the loop's, asserting each door lands nearest its own consumers.
4. **Report, measured with the 25-second candidate probe, never the full sheet:** candidate 1's record
   count, belts per flow, underground endpoints, transport entities. Then **one** full generation to prove
   `ok=true` with entities.

## What done mean

```checks
{"name": "input-doors", "command": "git diff --name-only round-19-doors-base HEAD | grep -v '^docs/tasks/160' | grep -Ev '^(logic/bp/search\\.lua|tests/test_demand_terminals\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_demand_terminals.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_external_ports.lua 2>&1 | tail -1 | grep -q '14 passed, 0 failed' || exit 1; $l tests/test_route_budget.lua 2>&1 | tail -1 | grep -q '8 passed, 0 failed' || exit 1; $l tests/test_validate.lua 2>&1 | tail -1 | grep -q '44 passed, 0 failed' || exit 1; done && echo input-doors-ok", "expect_exit": 0, "expect_regex": "input-doors-ok", "timeout_s": 1800}
{"name": "the-product-still-ships", "command": "out=$(mktemp); lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output \"$out\" >/dev/null 2>&1; python3 -c \"import json,sys; r=json.load(open('$out')); e=(r.get('result') or {}).get('entities') or []; print('ok=%s entities=%d' % (r.get('ok'), len(e))); sys.exit(0 if r.get('ok') is True and len(e) > 0 else 1)\" && echo product-ships-ok", "expect_exit": 0, "expect_regex": "product-ships-ok", "timeout_s": 2400}
```

Re-cut because: lane 159 implemented the rule and took full generation from a delivered blueprint to
`ok=False stage=failed BP_FAIL_GRID_LIMIT` with 0 entities, starving `iron-plate:4` at port `(17,42)`.

# bound: 4000s

Reviewer ask: does every machine still get fed, and does full generation still return `ok=true` with a
non-empty entity list?
