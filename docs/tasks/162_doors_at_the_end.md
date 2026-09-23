# 162 doors: a door sits at the END of its consumers, never the middle

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-162`, branch
`lane/162`, base tag `round-21-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-21-base`.

## Explain very simply

Items enter the factory through a **door** on the grid edge. A belt runs **one way only**. If the door
sits BETWEEN two machines that eat from it, one belt cannot reach both — it would have to go up AND down.
On round 20's blueprint the router then drew a **ring**: the player placed it on 2026-09-23 and called it
"this abomination".

So a door must sit where ONE one-way run from it can pass every consumer in turn: at an **end** of the row
of consumers, never in its middle.

## Measured on this host, 2026-09-23

`item/copper-ore` consumers are the port tiles `(1,24)` and `(1,28)`. Door slots are the left edge,
`x = 0`. Today's `slot_cost`, `logic/bp/search.lua` (`local function slot_cost(slot, consumers)`), sums the
straight distance from the slot to each consumer:

```
slot (0,24)  1+0 + 1+4 = 6
slot (0,25)  1+1 + 1+3 = 6      <- chosen; the door that was shipped
slot (0,26)  1+2 + 1+2 = 6
slot (0,28)  1+4 + 1+0 = 6
```

Every slot from `y=24` to `y=28` ties, and the tiebreak picked `(0,25)` — between the two consumers. The
delivered bytes then carry a 14-tile ring. `tools/transport_shape_probe.py` reads `cycles=1` on them.

## What is true

**A door's cost is the length of ONE one-way run from it through ALL its consumers.** Walk from the slot to
the nearest unvisited consumer, then from there to the next nearest unvisited one, until all are visited
(nearest-next tour), and sum the legs. With that cost:

```
slot (0,24)  1  + 4 = 5         <- an end
slot (0,25)  2  + 4 = 6
slot (0,26)  3  + 4 = 7
slot (0,28)  1  + 4 = 5         <- the other end
```

and a door lands at an END. Four iron furnaces on one row `(5,42) (9,42) (13,42) (17,42)` with the door at
`(0,42)` cost `5 + 4 + 4 + 4 = 17` — still the end of the row, as round 20 shipped.

## Traps, each measured on this host

- **Determinism.** Every tie needs an explicit total order. Use the nearest consumer by distance, then by
  `y`, then by `x`, and between equal slot costs keep the existing lower-index rule. `coord_key` and
  `tests/test_route_budget.lua` depend on the same input giving the same layout.
- **The network order uses the same cost.** `generated_perimeter_ports` computes `network.need` from
  `slot_cost` too, to serve the tightest network first. Keep one cost function; do not fork it.
- **`terminals_for_demand` may ask for several copies of one terminal.** Each copy takes the cheapest free
  slot under the same cost.
- **In and out are separate edges.** `slots["in"]` and `slots["out"]` are separate lists; the rule applies
  to each on its own. An OUTPUT door's "consumers" are its producers: the same tour applies.
- **The product must still ship.** `sh tools/round21_product.sh` must end `product-ok`. Round 19's first
  door patch starved a furnace and shipped nothing; that must not happen again.
- **Never touch** `logic/bp/route.lua`, `logic/bp/validate.lua`, `logic/bp/reason_codes.lua`,
  `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `tools/**`, any `tests/**` file except
  `tests/test_demand_terminals.lua`, `docs/**` except this task, `info.json`, `mod-description.md`,
  `.agent-lane.toml`.

## Files this lane owns

`logic/bp/search.lua`, `tests/test_demand_terminals.lua`.

## What to build

1. `slot_cost` becomes the nearest-next tour length above, deterministic as above, with a short comment
   naming the `(0,25)` measurement.
2. Two rows in `tests/test_demand_terminals.lua`, each **red at `round-21-base`**, in the style of the
   existing `DT nearest generated door follows its own sink` row:
   - **DT-END1** two consumers stacked on one column beside the input edge, `y = 24` and `y = 28`: the
     door lands at `y <= 24` or `y >= 28`, never between.
   - **DT-END2** negative control: consumers in one row along the input edge's normal still get the door
     at the near end of that row.
3. Report, measured: which slot `item/copper-ore` and `item/iron-ore` get on the player's sheet, and the
   `sh tools/round21_product.sh` output lines.

`sh tools/round21_product.sh` also judges ROUTE shapes this lane does not own. **If it fails only on
`back_to_back` while `cycles=0`, report that — back-to-back is another file's defect — and say so in your
commit message.** The check below therefore demands `ok=true` with entities and `cycles=0`, not the whole
product line.

## Commit, THEN check

Commit your work on `lane/162` with a message that says what changed and what was measured. **Run the two
checks below as the very LAST action, after the final commit.** A lane that ends with uncommitted work is a
failed lane whatever it built.

## What done mean

```checks
{"name": "doors-regress", "command": "git diff --name-only round-21-base HEAD | grep -v '^docs/tasks/162' | grep -Ev '^(logic/bp/search\\.lua|tests/test_demand_terminals\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_demand_terminals.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo doors-regress-ok", "expect_exit": 0, "expect_regex": "doors-regress-ok", "timeout_s": 1800}
{"name": "doors-no-ring", "command": "sh tools/round21_product.sh > /tmp/rrc162-product.txt 2>&1; cat /tmp/rrc162-product.txt; grep -q '^ok=True entities=' /tmp/rrc162-product.txt && grep -q ' cycles=0$' /tmp/rrc162-product.txt && echo doors-no-ring-ok", "expect_exit": 0, "expect_regex": "doors-no-ring-ok", "timeout_s": 1200}
```

# bound: 2400s

Reviewer ask: does `item/copper-ore`'s door sit at an end of its two furnaces, does the product still ship,
and is every tie broken by a stated total order?
