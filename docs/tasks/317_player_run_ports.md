# 317_player_run_ports: port finder in Lua from blueprint geometry (tests/game/lib/ports.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-317`, branch `lane/317`,
base tag `player-run-base` (the commit that holds this task file), merge target `int/player-run`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until every check below passes. Commit early, commit again, run the check LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/game_test.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/golden_profile.lua`, `tools/ckpt.lua save`, `tests/golden/generate.lua`, `factorio`, any `*_delivers.lua`, or any
full suite, census, whole golden sheet or headless run of any kind.** Single test files only:
`timeout 100 lua5.2 tests/<file>.lua` or `timeout 100 lua5.2 tests/game/offline.lua tests/game/<file>.lua` (lua5.2 ONLY,
never lua5.4), each under 60 s. Never use `coroutine` or `math.random`. `require` only at file top level (headless
Factorio refuses runtime require). **No game item or entity name in `logic/`** (this lane touches no `logic/`).
Deterministic: fixed order, ties broken by id string. Every new test must FAIL on the base code (say so in its header
comment, date 2026-10-05); commit it red first, then the code. Each new test prints its marker (e.g. `PF1`) at the
end of its passing case.

Read `CONTEXT.md` first (**Player run**, **Metered feed**, **Sheet sim**, **Port feed**, **Case**).

## What is true (explain very simply)

Player asked (2026-10-05) for a **Player run** per golden: GUI clicks like a player, generate, blueprint in hand,
build it, feed exactly calc input rate, measure output, pass when each output R = measured / calc rate is
0.98 <= R <= 1.1. The integrator joins three lanes into `tests/game/test_player_run.lua`. This lane builds one part.
Cases (15): player-am2-chain-repaired, player-blue-science-10s, player-green-science-1s, player-inserter-10s,
player-inserter-10s-bulk, player-inserter-10s-stack1, player-red-green-science-10s, player-red-science-10s,
player-red-science-10s-bulk, player-red-science-10s-stack1, player-red-science-1s, player-red-science-1s-bulk,
player-red-science-1s-foundry, vanilla-2.1-red-science-1s, vanilla-2.1-green-science-1s. Magenta is skipped, never
touched.

Today (worktree read 2026-10-05): `tools/sheet_ports.py` (335 lines) finds feed and sink tiles of a delivered sheet
by starting from port inserters' internal `port_id` (`:138-143`). Blueprint bytes carry NO `port_id` (no entity tags
in `logic/`), so the Player run, which builds a fresh in-game blueprint, cannot use it. It needs the same answer from
geometry alone. 2.1 has no `LuaEntity.fluidbox` network API (`tests/game/lib/lab.lua:247`): work only on entity
name, position, direction, type fields (`belt_to_ground_type` for undergrounds, `recipe` for machines).

## What to build

1. `tools/sheet_entities.py` (new): `tools/sheet_entities.py <case>` decodes `tests/fixtures/sheets/<case>.bp.txt`
   (reuse decode from `tools/blueprint_audit.py`) and writes `tests/fixtures/sheets/<case>.entities.json` = list of
   `{name, x, y, direction, type?, recipe?}` in blueprint coordinates, plus `"bbox"` as in ports.json. Commit for all 15
   Cases (magenta: none).
2. `tests/game/lib/ports.lua` (new), frozen API:
   ```lua
   Ports.find{entities = list, bbox = {l,t,r,b}, ingredients = fn(recipe_name) -> {{name, kind="item"|"fluid"}},
              inputs = {[full_name]=true}, outputs = {[full_name]=true},
              hand_reach = fn(name) -> 1|2, sizes = fn(name) -> w,h}
     -> {feeds = {{tile={x,y}, item=name} | {tile={x,y}, fluid=name}}, sinks = {{tile={x,y}, item=name}}, problems = {}}
   ```
   Entities are plain tables (`name, position={x,y}, direction, type, recipe, belt_to_ground_type`), so the same code
   runs on decoded fixtures offline and on `surface.find_entities` results in game (the integrator adapts). Directions are
   2.0 16-way (0 N, 4 E, 8 S, 12 W). An inserter's `direction` points at its PICKUP (reach 2 for long-handed).
   - Input feed: walk belt / underground / splitter chains; a chain head nobody feeds that touches the bbox edge is a
     feed tile. Item = the solid ingredients of recipes of machines that hands picking from this chain feed, intersected
     with `inputs`; more than one item -> problem `TWO_ITEMS <tile>`.
   - Output sink: from each hand dropping onto a chain, walk downstream to the chain end touching the bbox edge; item =
     the machine's recipe product intersected with `outputs`.
   - Fluid feed: each pipe / pipe-to-ground network touching the bbox edge (tile on edge, open end facing out) is fed
     with the fluid ingredient of the machines it reaches, intersected with `inputs`. Tile = the edge pipe tile.
   Match tiles exactly the way `sheet_ports.py` does (`tile = floor(position)`), so results compare 1:1.

## Tests (`tests/test_ports_find.lua`, new)

- PF1 for every Case with an entities fixture: `Ports.find` feeds (tile + item/fluid) == `ports.json` `feeds` as sets.
  Ingredients/products: player Cases from `tests/golden/cases/<case>/prepared_input.json` `catalog` recipes; vanilla
  Cases from a small table in the test (vanilla 2.1 recipes for red and green science chains).
- PF2 same for sinks == `ports.json` `sinks`.
- PF3 fluid feeds of player-blue-science-10s (water, crude-oil) and player-am2-chain-repaired (molten-iron) found.
- PF4 red proof: remove the one hand picking from a red-1s input chain -> that feed's item cannot be named -> problem
  reported (not silently dropped).
- PF5 no `port_id` read anywhere in `ports.lua` (text check).

## Files this lane owns

`tests/game/lib/ports.lua`, `tools/sheet_entities.py`, `tests/fixtures/sheets/*.entities.json`, `tests/test_ports_find.lua`.

## Integrator-proven (not yours; do not try)

Same finder on built LuaEntities in headless Factorio.

## Commit, THEN check

Commit on `lane/317`. **Run the check as the very LAST action.**

## What done mean

- PF1-PF5 pass and print markers; `tests/test_ports_find.lua` red on base.
- 15 entities fixtures committed; `ports.lua` reads only name/position/direction/type/recipe/belt_to_ground_type.
- Diff only inside owned files; guards green.

```checks
{"name": "lane317-check", "command": "sh tools/lane_check_pr.sh 317", "expect_exit": 0, "expect_regex": "lane317-ok", "timeout_s": 3000}
```
