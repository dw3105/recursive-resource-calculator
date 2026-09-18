# 003 — prototypes as plain data, at the right quality

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-003`, branch `lane/003`, base = `feat/round-8-blueprints`, tag `wave-0-spine` (resolve it with `git rev-parse wave-0-spine`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/catalog.lua` and `tests/test_catalog.lua` only.
- Read prototypes here so that nothing downstream has to: every geometry, routing, power and serialization module takes your output and touches no engine object.
- Never read a quality-dependent value as a constant. Reach, supply area, crafting speed and module slots come from the prototype's own accessor at the selected quality.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/catalog.lua` carries the shape at the top and the stubs `Catalog.build(player_index, options)` and `Catalog.for_export(player_index, referenced)`.
- `docs/api/2.0.77.members.json` and `docs/api/2.1.19.members.json` are the pinned member surface. `tests/test_api_shapes.lua` fails the suite if the harness serves a member the engine does not have; if you need a member that is mocked but absent from those files, stop and report.
- Real names, checked against those files: `logistic_radius`, `construction_radius`, `connection_distance`, `max_underground_distance`, `belt_speed`, `inserter_pickup_position`, `inserter_drop_position`, `collision_box`, `collision_mask`, `tile_width`, `tile_height`, `flags`, `fluidbox_prototypes`, and the methods `get_supply_area_distance(quality)`, `get_max_wire_distance(quality)`, `get_crafting_speed(quality)`, `get_max_energy_usage(quality)`.
- A runtime pipe connection carries `positions` (one MapPosition per cardinal orientation), `direction`, `connection_type` (`normal`, `underground`, `linked`), `flow_direction`, and its own `max_underground_distance`. There is no singular `position` at runtime; that is the data stage. Factorio 2.1 adds `alt_direction` and `alt_position`.
- `LuaFluidBoxPrototype` has `volume` on 2.0.77 and not on 2.1.19. Branch on `Utils.IS_2_1` (`logic/utils.lua:15`), never by probing a member: a LuaObject throws on an unknown one.
- `logic/utils.lua` already holds the adapters worth reusing: `Utils.id_name`, `Utils.recipe_categories`, `Utils.product_probability`, `Utils.setup_effects`, `Utils.effect_multiplier`, `Utils.product_amount`, `Utils.net_amounts_by_full_name`, `Utils.crafting_machines_for`.
- `logic/indexer.lua` already caches recipes by product and by ingredient, machines by category, pollution per machine, module and beacon names; read those rather than walking every prototype again.
- The harness builds infrastructure with `world.add_default_infrastructure()` and the individual builders `add_transport_belt`, `add_underground_belt`, `add_splitter`, `add_inserter`, `add_pipe`, `add_pipe_to_ground`, `add_electric_pole`, `add_roboport`, plus `world.fluid_box{...}` and `world.set_fluid_boxes(machine, boxes)`.

## What to build

1. `Catalog.build` projects, as plain data, every entity, item, fluid, quality, module, beacon and piece of infrastructure the request names: both geometry models (the integer tile footprint and the exact collision box with its mask), module slots at the selected quality, energy and pollution, beacon supply area, profile and counter rule, and the fluid boxes with their rotated runtime connections.
2. The belt family, pipe family, inserter, pole and roboport entries described in the file header, each at its selected quality.
3. A prototype that no longer resolves becomes a diagnostic entry `{code, subject, detail}` in the second return value. Nothing crashes, and nothing is guessed.
4. `Catalog.for_export` projects only what a calculation actually referenced: the debug export carries a bounded dependency snapshot, never every prototype in the game.
5. Red-first cases in `tests/test_catalog.lua`: a machine's tile footprint and its exact collision box are both present and are not the same number; a pole's supply area and wire reach differ between normal and legendary; a roboport's radii and connection distance come from the prototype; a belt's items per second follow from `belt_speed`; an underground belt carries its own max distance; a pipe-to-ground's underground connection is the one that faces away from its exposed connection, with its own max distance; a machine's fluid box gives four positions per connection; on 2.1 a fluid box has no `volume` and the catalog still builds; a missing prototype yields a diagnostic rather than an error; nothing in a built catalog is a LuaObject (walk it, `type(v) ~= "userdata"`).
6. Planted breach, pasted red then reverted: read the pole's supply area at normal quality regardless of the selected quality, and the quality case must go red.

## What done mean

```checks
{"name": "catalog-tests", "command": "lua5.2 tests/test_catalog.lua && lua5.4 tests/test_catalog.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-0-spine --manifest docs/tasks/003.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout 4569c48ca39995d321f26ec11403fb273e7a194a -- logic/catalog.lua; out=$(cd \"$S\" && lua5.2 tests/test_catalog.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-0-spine HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree
the proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green
every check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/catalog.lua`
- `tests/test_catalog.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: does every quality-dependent value come from its accessor at the selected quality, and does a catalog hold no engine object at all?
