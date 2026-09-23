# 161 route: a dive is fed straight, one pair where one reaches, and no belt ring

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-161`, branch
`lane/161`, base tag `round-21-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-21-base`.

## Explain very simply

A Factorio belt has two lanes. An **underground belt entrance fed straight from behind takes both lanes**.
A belt that TURNS into an entrance, or pushes into it from the side, is a **side-load**: the inlet blocks one
of the feeder's lanes. The player placed our blueprint on 2026-09-23 and one such run stalled, because its
items rode the blocked lane.

**The player's rule, verbatim, 2026-09-23:** "sideload of near lane is legitimate, but need to be used only
if there are no simpler solutions; sideload of far lane can be used to block far lane, but only to be used
if there are no simpler choices!" So a side-load is **never forbidden** and **always a last resort**: the
search takes it only when no straight feed exists.

An underground pair **jumps up to 4 tiles** (`underground-belt`, max distance 5). We surface and dive
again on the next tile, paying four entities where two reach.

A belt runs **one way only**. The router closed a **ring** — a run that feeds back into its own start — and
items circle forever.

## The oracle — judge by it, never by your own counts

`tools/transport_shape_probe.py <blueprint.txt> -v` counts the three shapes on BYTES. Measured on this host
2026-09-23:

```
round 20 delivered bytes     sideload=5 back_to_back=1 cycles=1
player's hand-built factory  sideload=0 back_to_back=0 cycles=0

SIDELOAD     (14,4) dir=12 -> (13,4) input dir=0
SIDELOAD     (6,9)  dir=4  -> (7,9)  input dir=0
SIDELOAD     (1,29) dir=4  -> (2,29) input dir=0
SIDELOAD     (11,9) dir=0  -> (11,8) input dir=12    a splitter's output tile
SIDELOAD     (9,21) dir=0  -> (9,20) input dir=4     a splitter's output tile
BACK_TO_BACK (14,1) -> (15,1) dir=4, one pair (12,1) -> (17,1) spans 5
CYCLE        len=14 first=(1,22)
```

The probe COUNTS side-loads and does not fail on them — it cannot see which lane items ride. It fails on
`back_to_back` and `cycles`.

`sh tools/round21_product.sh` runs full generation on the player's sheet, encodes, and runs the probe. It
prints `product-ok` only when generation is `ok=true` with entities AND `back_to_back=0 cycles=0`. It takes
about 200 s. At `round-21-base` it is RED on `product-fail: shapes`, and it reads `sideload=5`. **Report your
sideload count; it must fall.** Every side-load left must be one where no straight feed existed — name each
one and say why in your report.

## The three causes, each located

**1. A dive from a turn, priced as if it were free.** `logic/bp/route.lua`, `search_step`, the branch that begins

```lua
            elseif (not first or search.demand.source.perimeter) and current.mode ~= 2 then
```

calls `crossing_target` and enqueues a dive heading `direction` from `current`. The underground INPUT is
placed ON `current`, facing `direction`. The tile that feeds it is the tile the search came from, and the
search arrived heading `current.direction`. When `current.direction ~= direction` the input is fed from the
side. **All five side-loads above are exactly this**: the path turns on the dive tile. The two splitter
cases are the same shape one tile later — the body jump commits the tile after the splitter to the
trunk's heading, and the path then turns into a dive on the next tile.

The fix is a **price, never a refusal**: a dive whose `current.direction ~= direction` costs an extra
`SIDELOAD_UNDERGROUND_COST`, set ABOVE `SPLITTER_BODY_COST` (4) so any straight alternative — a longer
walk, a straight dive one tile on, a splitter — wins first. `8` is the suggested value; measure it. A dive
from a perimeter door on its first step is straight by construction.

**2. Stepping onto an existing underground endpoint.** `path_cell_free` lets a step enter a tile whose
`segment.underground` is true, from any side, as a merge, and the merge then walks on to the NEXT tile.
For an existing INPUT that is wrong physics: its items leave at the paired EXIT, never at the next tile, and
the search cannot follow the pair underneath. **Refuse a step onto an existing underground INPUT.** A side
step onto an existing underground OUTPUT is a real side-load whose items do continue forward from that
tile: allow it, at `SIDELOAD_UNDERGROUND_COST`.
Also: the belt the search lays on its LAST tile points somewhere. If the tile it points into holds an
underground endpoint that is not an input facing that same way, the final belt side-loads it: price that
arrival heading the same way.

**3. The dive stops at the first free tile.** `crossing_target` returns `nil` the moment one middle tile
is walkable (`if path_cell_free(...middle...) then return nil end`). Over `(13,1)` busy, `(14,1)` free,
`(15,1)` free, `(16,1)` busy it can never offer `(12,1) -> (17,1)`. The fix: scan every distance
`2..reach`, keep going past free middles, stop only at a middle holding an underground endpoint
(`work.underground_cells`), and return EVERY exit that is free and legal AND has at least one non-walkable
middle. `search_step` enqueues each one. Cost stays `2 + distance + 2`: the long pair costs 9, the two
short pairs plus the tile between cost 13, so the search takes one pair by itself. A dive whose middles are
ALL walkable stays refused — `tests/test_route_waste.lua` RW3 guards that and must stay green.

**4. The ring.** On round 20's bytes: copper-ore enters at `(0,25)`, runs south down `x=1` to `(1,29)`,
east, north up `x=2` diving under two inserters, west at `(2,22)` into `(1,22)`, and south again into the
first run. The second demand's search started from a seed ON the first run, and its last belt, on the
sink's port tile `(1,24)`, points into `(1,25)` — the first run — which leads back to where the second path
began. Refuse it at the search:

- when a step MERGES into a same-flow segment (`merge` in `search_step`), and
- when the search ARRIVES on the sink tile in heading `h`, for the tile ahead `sink + h`,

walk the same-flow chain from that tile (the helpers `route_chain_tiles` / `route_chain_reaches_tiles`
already walk a directed chain) and refuse the move if it reaches the tile this path started from. The start
is the root of `search.parent` from `current`. This is rare, so walking parents there is cheap enough.

**5. Prefer running THROUGH another same-flow sink's port tile.** Contract 28.8: a trunk extended through
the next sink's port tile serves that sink for free. Two equal-cost paths tie today and the wrong one can
win: from a door at `(0,24)` to `(1,28)`, east-then-south passes `(1,24)`'s port tile, south-then-east does
not. In `transition_cost`, price a step onto a tile that `work.port_cells` reserves for ANOTHER port of the
SAME flow (`reserved["flow:" .. flow_id]` and `reserved._port_owners` naming a port that is not this
demand's sink) below a plain free tile. `0.5` is the suggested price; measure it.

## Traps, each measured on this host

- **Determinism.** `tests/test_route_budget.lua` and `coord_key` depend on the same input giving the same
  layout. Every list you build (dive exits) is scanned in a fixed order.
- **Performance.** Offering more dive exits enlarges the frontier. Full generation on the player's sheet
  took 191 s at `round-20-delivered`. Report yours. Past 300 s, stop and report rather than ship.
- **Frozen geometry rows move.** `tests/test_route_collision.lua` RX1 and `tests/test_route_chain.lua` RC8
  freeze exact counts measured on a fixture. When your change moves them, re-freeze to the NEW measurement
  with a comment naming what moved and why — never loosen a ceiling you did not measure, never change a row
  to make it pass without printing the measurement next to it.
- **RC2 and RC8's `underground <= 6` is honestly red at base (8).** If your change brings it to 6 or below,
  good; say so. If not, leave it red.
- **A perimeter door may dive on its first step** (round 20, `search.demand.source.perimeter`). Its
  `current.direction` is the door's `travel_dir`, so rule 1 still holds.
- **Never touch** `logic/bp/search.lua`, `logic/bp/validate.lua`, `logic/bp/reason_codes.lua`,
  `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `tools/**`, any `tests/**` file except those listed
  below, `docs/**` except this task, `info.json`, `mod-description.md`, `.agent-lane.toml`.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route_underground_feed.lua` (new), and — only to re-freeze a measured
count as described above — `tests/test_route_collision.lua`, `tests/test_route_chain.lua`.

## What to build

1. Rules 1 to 5 above in `logic/bp/route.lua`, each with a short comment naming the measured shape it
   refuses, in the style of the comments already there.
2. `tests/test_route_underground_feed.lua`, driven through `Route.begin` / `Route.step` exactly as
   `tests/test_route_waste.lua` does, with at least these rows, each **red at `round-21-base`** and green
   after:
   - **UF1** a flow that must turn and then cross a foreign belt, with room to walk one tile straight
     before diving, dives STRAIGHT: assert, for every published underground input, that the tile directly
     behind it (opposite its direction) holds a belt or exit of the same flow facing the same way.
   - **UF1b** the last resort still works: same shape with NO room for a straight feed still routes, and
     does so with a side-fed dive. A side-load is priced, never forbidden.
   - **UF2** two foreign belts two free tiles apart across one flow's path are crossed by ONE pair.
   - **UF3** a flow feeding two sinks stacked on one column, door beside the middle of them, publishes no
     directed ring (walk successors from every transport tile; none returns to itself).
   - **UF4** negative control: a straight run into a dive stays legal and still dives.
3. Run the frozen fixture rows the file already has and re-freeze only what your measurement moved.

## Commit, THEN check

Commit your work on `lane/161` with a message that says what changed and what was measured. **Run the two
checks below as the very LAST action, after the final commit.** A lane that ends with uncommitted work is
a failed lane whatever it built.

## What done mean

```checks
{"name": "route-regress", "command": "git diff --name-only round-21-base HEAD | grep -v '^docs/tasks/161' | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_underground_feed\\.lua|tests/test_route_collision\\.lua|tests/test_route_chain\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_route_underground_feed.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo route-regress-ok", "expect_exit": 0, "expect_regex": "route-regress-ok", "timeout_s": 1800}
{"name": "route-product", "command": "sh tools/round21_product.sh", "expect_exit": 0, "expect_regex": "product-ok", "timeout_s": 1200}
```

# bound: 2400s

Reviewer ask: does the probe read `back_to_back=0 cycles=0` with fewer than 5 side-loads on the lane's own
generated bytes, is every remaining side-load one with no straight alternative, and did any frozen row move
without its measurement printed beside it?
