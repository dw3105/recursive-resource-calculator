# Contract: machine row blocks (round 26, 2026-09-23)

The player's rule: machines of one machine name and one recipe may share buffer-zone space in one row or one
column (`logic/bp/buffer.lua`). So a step with N >= 2 machines is built as ONE block, a **row**, and the packer
places it once. Every lane of round 26 codes against the shapes below; `tests/fixtures/row_block.lua` builds
one placed science row by hand in exactly these shapes.

## Geometry (block frame, `NORTH`; `EAST` is the same block turned 90 degrees clockwise)

- N machines of size w x h touch each other along x: machine i at `x = x0 + i * w`, all at the same y.
- One input hand per machine on the TOP face, one output hand per machine on the BOTTOM face, both in the
  same column offset `c` of their machine (for a 3-wide machine, the middle column `c = 1`).
  So all input pickup tiles lie on one straight line above the row and all output drop tiles on one line below.
- When the recipe has two item inputs, the input hand is a **paired hand** (`flow_ids = {A, B}`,
  `multi_flow_hands`, contract 28.1/28.3): it takes both items from the one input belt.

## Belt runs

`block.belt_runs` (block frame) and, after `Groups.materialize`, `placed.belt_runs` (world, rotated):

```lua
{
  role = "in" | "out",
  flows = {flow_id, ...},          -- 1 or 2 flows; 2 only for role "in"
  tiles = {{x = , y = }, ...},     -- in travel order; every hand's pickup (in) / drop (out) tile is one of them
  dir = <Grid direction of travel along the run>,
  head = {x = , y = } | nil,       -- role "in" only: the run's FIRST tile, one tile before the first pickup tile
  feeds = {                         -- role "in": one per flow, the tile beside the head that side-loads it
    {flow_id = , side_tile = {x = , y = }, travel_dir = <direction from side_tile into head>},
  },
  port = {x = , y = , travel_dir = } | nil, -- role "out": the tile after the run's last tile, where the flow leaves
  hand_ids = {inserter id, ...},    -- the hands this run serves, in run order
}
```

- **Lanes.** A belt travelling `dir` has a left and a right lane. A side-load from the left side of the head
  fills the left lane; from the right side, the right lane. With two flows, `feeds[1]` comes from the left side
  and `feeds[2]` from the right side, so the two flows ride different lanes past every hand.
- **Nothing feeds the head from behind** (the tile before the head, against `dir`, stays free of transport).

## Ports

A row block has ONE port per flow:
- role "in": one port per feed, at `feeds[k].side_tile`, `travel_dir = feeds[k].travel_dir`, `flow_id` of that
  feed. The router's demand for that flow ends there.
- role "out": one port at `port`, travel `port.travel_dir`. The router's demand for that flow starts there.

## Route input

`input.belt_runs` = the flat list of every placed block's `belt_runs` (world). The router lays each run as fixed
segments before any demand is searched and never lifts or re-routes them.

## Validator

Every paired input hand's pickup tile must carry each of its flows, on different lanes (`BP_V_LANE_MIX`
otherwise).
