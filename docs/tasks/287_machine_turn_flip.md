# 287_machine_turn_flip: machines in a Block Turn and Flip so fluid boxes face their pipe partner

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-287`, branch `lane/287`,
base tag `round-51-base`, merge target `int/r51`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet
or headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY); headless test files only offline:
`timeout 90 lua5.2 tests/game/offline.lua tests/game/<file>.lua`. Never use `coroutine` or `math.random`. `require`
only at file top level. **No game item or entity name in `logic/`.** Every new test must FAIL on the base code where
this task says "red on base" (say so in its header comment); commit it red first.

## Explain very simply

Read `CONTEXT.md` section "Layout" first (Block, Row, Turn, Flip).

A Flip mirrors a machine: its fluid boxes move to the other side without a Turn. Blueprint field `mirror = true`.
Engine truth, measured headless 2026-09-30 on 2.0.77 AND 2.1.20 (identical rows):
`tests/fixtures/flip_fluidboxes_2.0.txt`, `..._2.1.txt` (made by `tests/game/test_flip_fluidboxes.lua`).
Row `CONN <machine> dir=<d> edir=<d> mirror=<b> ... box=<i> ... pos=<x,y> target=<x,y>`: `pos` = connection tile
inside machine edge, `target` = pipe tile outside, both relative to machine centre. ONE rule fits every row, both
versions: **mirror x in the machine's own (north) frame, then rotate clockwise by dir; each box keeps its index.**
Example foundry box 1: north `pos=-1,2`; mirrored `1,2`. am2/am3: Flip changes nothing (symmetric boxes). The engine
accepted `mirroring = true` on every machine in both versions.

Measured 2026-09-30 (`docs/tasks/r51_probes/p_mdir*.lua`): setting `machine.dir` inside `build_block` today already
gives valid foundry layouts for dir 4/8/12 (validate fluid check passes). So Turn inside a Block works; this lane
adds Flip, the rebuild API and the choice.

Frozen contracts (top comments; keep signatures, replace bodies): `logic/bp/orient.lua` `Orient.choose`,
`logic/bp/groups.lua` `Groups.reorient(groups_state, block, orient)`. Caller (another lane) passes
`groups_state = ` the Groups stage state that built the Block (`groups_state.work.input` has `catalog`, and the
build inputs), `partner_dir[port_id]` = WORLD direction 0/4/8/12 toward that fluid port's partner, `turn` = the Block
Turn pack will prefer (machine world facing = block-frame facing rotated by `turn`).

Engine trap found 2026-09-30: a crafting machine created WITHOUT a recipe ignores `direction` (stays north).
`tests/game/lib/lab.lua` `Lab.build` (:88-95) creates first, sets recipe after -> headless builds turned fluid
machines facing north. Fix: pass `recipe` in the `create_entity` spec.

Today's geometry sites: `groups.lua` `fluid_connection` (:112-166, picks box/connection), `fluid_pipe_tile`
(:758-770, rotates `positions[1]` by `machine.dir`), port facts (:1158-1170, :2351-2381, :2682-2686); machine table
(:1491-1509) has no `dir`/`mirror`; `route.lua` `rotate_connection` (:247-265); `validate.lua`
`fluid_connection_cells` (:2102-2149, uses `positions[floor(dir/4)+1]`, ignores mirror); `serialize.lua:427` copies
`mirror` when an entity has it; `catalog.lua` fluid box capture (:373-408, `positions` = 4 entries per cardinal dir).

## What to build

1. `logic/bp/grid.lua`: `Grid.fluid_connection(connection, dir, mirror) -> x, y, direction`: base = `positions[1]`
   (or legacy `position`) and `direction` of the connection in north frame; mirror: x -> -x and direction EAST<->WEST;
   then `Grid.rotate_vector` / `Grid.rotate_dir` by `dir`. With `mirror` false it must equal today's per-site results.
2. Use it at all three sites: groups `fluid_pipe_tile` (+ `machine.mirror`), route `rotate_connection` (+ entity or
   port `mirror`), validate `fluid_connection_cells` (+ `entity.mirror`). Flag-free today: no machine has `mirror`,
   so every existing layout keeps its bytes.
3. `logic/catalog.lua`: per crafting machine entity `can_flip = true` when: type is "assembling-machine" (2.0 and
   2.1), `use_mirroring` read through `pcall` is not `false`, and mirroring moves at least one fluid box connection
   (mirrored (x, direction) set differs from original for some box). Otherwise nil.
4. `logic/bp/groups.lua`:
   - machines carry `dir` and `mirror` from an optional `orient` given to `build_block`; store on the Block what a
     rebuild needs (plain data, no functions; checkpoints save it).
   - materialize copies `mirror` to the machine entity (so serialize writes `"mirror": true`).
   - `Groups.reorient(groups_state, block, orient)`: `{dir = 0, mirror = false}` -> the Block unchanged (same table);
     else rebuild with every machine at `orient`; same Block id and same port ids; return nil when `orient.mirror`
     and the machine has no `can_flip`, or when any fluid pipe tile falls inside a machine, beacon, inserter or belt
     tile of the Block.
5. `logic/bp/orient.lua` `Orient.choose`: candidates in order (0,false), (0,true), (4,false), (4,true), (8,..),
   (12,..); skip mirror when machine lacks `can_flip`. For each fluid port with `partner_dir`, facing = connection
   direction from `Grid.fluid_connection` for the box/connection the port uses (store box/connection index on the
   port at build if missing), rotated by `turn`. Score per port: 2 facing == partner_dir, 1 perpendicular, 0
   opposite. Max total wins; ties -> earlier candidate. No fluid ports -> `{dir = 0, mirror = false}`.
6. `tests/game/lib/lab.lua` `Lab.build`: `recipe = e.recipe` in the create spec for crafting machines (keep the later
   `set_recipe` for quality); after create, `pcall` set `ent.mirroring = true` when `e.mirror`. Comment the engine
   trap with date.
7. Twins exist already (STEP 0, integrator): `tests/twins/transport/fluid_flipped_ok.lua` (flipped foundry, pipe
   on MIRRORED box 1 target) and `fluid_flipped_bad.lua` (pipe on UNmirrored target). Never edit them. On base,
   `fluid_flipped_bad` is RED (validator ignores `mirror`, calls it ok) and `fluid_flipped_ok` passes only by
   accident (its pipe lands where unflipped box 2 sits). After your fix the validator must bind molten-iron to
   box 1 at its FLIPPED tile: ok -> no codes, bad -> `BP_V_FLUID_DISCONNECTED`. If the validator accepts any input
   box for a one-fluid recipe, find where (`validate.lua` fluid check around :2102-2149, :2418, :2512) and bind the
   box the recipe's fluid ordinal picks (same rule as groups `fluid_connection`).
8. Tests (headers: FG1-FG4, OR1-OR4, CF1 red on round-51-base):
   - `tests/test_flip_geometry.lua`: FG1 parse both fixture files; for every machine and box: build connection from
     its dir=0 mirror=false row (positions for 4 dirs from the 4 mirror=false rows); `Grid.fluid_connection` equals
     `pos` and target direction (target - pos) of every row (all dirs, both mirrors). FG2 twin `fluid_flipped_ok`
     validator verdict ok, `fluid_flipped_bad` gives `BP_V_FLUID_DISCONNECTED` (use `tests/twins/lib/twin.lua`).
     FG3 route `rotate_connection` of a mirrored machine port equals helper. FG4 serialize writes `"mirror": true`
     for a mirrored machine and omits it otherwise.
   - `tests/test_orient.lua`: OR1 foundry Block, partner west, turn 0 -> choice whose facing is west; OR2 machine
     without `can_flip` never gets mirror; OR3 `Groups.reorient` keeps Block id and every port id; OR4 blocked pipe
     tile -> nil.
   - `tests/test_catalog.lua` add CF1: mock foundry-like prototype with asymmetric boxes -> `can_flip`; symmetric
     am3-like -> nil.
9. Keep green (one at a time, `timeout 90`): `test_groups`, `test_fluid_box`, `test_groups_fluid_row`,
   `test_red_green_fluid_ports`, `test_groups_hand_off_pipe`, `test_red1s_foundry_delivers`,
   `test_blueprint_physical_contract`, `test_validate_ptg_sides`, `test_twins`, `test_catalog`, `test_grid`,
   `test_route`, `test_flip_geometry`, `test_orient`, `test_no_item_names`, `test_no_runtime_require`,
   `test_locale_keys`; offline `tests/game/test_twins.lua`.

## Files this lane owns

logic/bp/grid.lua, logic/bp/groups.lua, logic/bp/orient.lua, logic/catalog.lua, logic/bp/route.lua,
logic/bp/validate.lua, logic/bp/serialize.lua, tests/game/lib/lab.lua, tests/test_flip_geometry.lua, tests/test_orient.lua,
tests/test_catalog.lua, docs/tasks/287_machine_turn_flip.md. In route.lua and validate.lua touch only the
fluid-connection code named above. Never touch anything else.

## Commit, THEN check

Commit on `lane/287`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane287-tests", "command": "git diff --name-only round-51-base HEAD | grep -Ev '^(logic/bp/grid\\.lua|logic/bp/groups\\.lua|logic/bp/orient\\.lua|logic/catalog\\.lua|logic/bp/route\\.lua|logic/bp/validate\\.lua|logic/bp/serialize\\.lua|tests/game/lib/lab\\.lua|tests/test_flip_geometry\\.lua|tests/test_orient\\.lua|tests/test_catalog\\.lua|docs/tasks/287_machine_turn_flip\\.md)$' | ( ! grep . ) && for t in test_groups test_fluid_box test_groups_fluid_row test_red_green_fluid_ports test_groups_hand_off_pipe test_red1s_foundry_delivers test_blueprint_physical_contract test_validate_ptg_sides test_twins test_catalog test_grid test_route test_flip_geometry test_orient test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && timeout 300 lua5.2 tests/game/offline.lua tests/game/test_twins.lua 2>&1 | tail -1 | grep -q ' 0 failed' && echo lane287-tests-ok", "expect_exit": 0, "expect_regex": "lane287-tests-ok", "timeout_s": 3000}
{"name": "lane287-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_flip_geometry.lua; timeout 120 lua5.2 tests/test_orient.lua; timeout 120 lua5.2 tests/test_catalog.lua) 2>&1); for c in FG1 FG2 FG3 FG4 OR1 OR2 OR3 OR4 CF1; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -c ' 0 failed' | grep -q '^3$' && echo lane287-ok", "expect_exit": 0, "expect_regex": "lane287-ok", "timeout_s": 300}
```

# bound: 5400s
