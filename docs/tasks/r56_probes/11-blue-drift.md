# Ticket 11: why blue-science-10s builds a different layout in game than offline

Session 2026-10-03 22:47-23:12 UTC, legalcopilot-dev, load 6.7-25. Code f3d2268 (origin/main) in own worktree
~/wt-rrc-speed11, plus local probe hooks that are never committed. Probe files: research/11-probe/ (p11.lua is a
copy of tests/game/p11.lua, test_p11.lua, hl.sh, bind_input.py, init.lua, logs/).

## Answer

The two runs do not get the same input. The runtime is not the cause: no `pairs` order or float difference was found.

- In game, generation.lua:1197-1219 probes the engine's fluid -> fluid box binding for every plan step on a scratch
  surface, before the search starts. `BoxBinding.fill` writes the result into `catalog.recipe[r].fluid_boxes`. This
  branch runs only when `rawget(_G, "game")` is set.
- Offline, every golden `prepared_input.json` has 0 bound recipes. That holds for all 19 cases; blue has 0 of 532
  recipes bound.
- search.lua:1150 `fluid_keepouts` turns that binding into route keepout tiles. Its own comment says: "Without a
  binding in the catalog the list is empty (offline goldens: no change)". So offline blue routes with no keepouts,
  and game blue routes with keepouts.
- route.lua:3787-3795 (`reserve_port_cells`) marks each keepout tile `_keep_flow`. route.lua:2600
  (`path_cell_free`) then refuses a pipe of any other fluid on that tile.

## Proof chain (offline lua5.2 `ckpt.lua save ... phase=hands` vs headless 2.0.77 `test_p11`, same probe hooks)

| Step | Offline (no binding) | Engine 2.0.77 | Offline + engine binding |
|---|---|---|---|
| Phases, groups, pack rejections, pack result before route (RB: 266 ents) | h=7b305b4a | h=7b305b4a | h=7b305b4a |
| 1st route search (petroleum-gas): path | 47 tiles h=69ab65cf, 1258 exp | 47 tiles h=4b77e84a, 1250 exp | 47 tiles h=4b77e84a |
| A* trace | equal through expansion 277 | expansion 277 (28,11): (28,10) refused by route.lua:2600 `_keep_flow` | = engine |
| 2nd water demand | appended | crossing-occupied x5, electronic-circuit NO_PATH, restart | = engine |
| 1st route result (RD) | 1372 ents h=4ac5733f | 1375 ents h=3818e0ae | 1375 ents h=3818e0ae |
| Probe events, route stage | 217 events, 82 diffs vs engine | 217 | 217/217 identical to engine |

- Input with binding added = the golden input plus tests/fixtures/box_binding_2.0.txt, using the rule in
  tools/turn_flip_bind.py (`11-probe/bind_input.py`, 42 recipe x machine pairs).
- The whole bound blue run, offline, to the end: wave r56-speed03 (the operator started a new wave), 23:19-23:21 UTC,
  load 11. Result: 6065 ticks / 1475 entities, ok=true, sha c7d1994f. Game is 6080 / 1475. The 15 extra ticks fall
  in the job wrapper band seen on the 11 matching sheets (+8..17, ticket 01). Without binding the offline run gives
  5309 / 1437.
- Run driver: 11-probe/drive_bound.sh. It needs the ticket 01 `ckpt.lua` patch (`--cpu-cap`, `RRC_GAME_TICK`, copied to
  11-probe/ckpt_from_t01.diff). Stock `ckpt.lua` ran the whole sheet in one chunk and hit `timeout 120` twice.
- The first route stage ends at tick 2110 in engine. Offline it ended at about 1940 (route 838 ticks vs engine 994,
  ticket 16). That gap is the start of the 771-tick difference.

## Consequences

- Every offline number on a sheet whose placed machines have bound fluid recipes measures a layout the player never
  gets. Ticket 01's statement that the other 11 sheets match compared entity counts only. Magenta and
  inserter-10s-stack1 "game" ticks came from windows resumed from OFFLINE state (ticket 01), so they carry the same
  blind spot. Magenta places foundries and chemical plants, so a magenta drift is likely. It is unmeasured.
- Ticket 19 (magenta grid 6 order-fragile on CAPACITY + FLUID_MIX, molten-iron / molten-copper) studies offline
  routing without keepouts. Its fluid findings may not hold in game.

## Fix size: one small lane, no logic change

Offline tools (generate.lua, ckpt.lua, golden_profile, first_stage, census, the lane_sim fixtures) apply the engine
binding when the catalog has none, through one shared loader. `BoxBinding.parse_fixture` already exists, used by
tests/test_box_binding.lua. The version is picked as 2.0 by default (the player's version) or 2.1. The two fixtures
differ on 10 lines (275 vs 273 BIND lines). Gate: the ticket 05 parity row, offline sha == in-game sha for blue.
Cost: new bytes baseline (layered + drawn) for every golden whose bytes move. The alternative is baking the binding
into the prepared_input.json files: it is simpler, but it goes stale when the binding fixture is re-probed, and it
pins one version.
