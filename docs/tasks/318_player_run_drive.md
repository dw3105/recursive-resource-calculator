# 318_player_run_drive: GUI driver replays a Case through handlers (tests/game/lib/player_drive.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-318`, branch `lane/318`,
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
comment, date 2026-10-05); commit it red first, then the code. Each new test prints its marker (e.g. `PD1`) at the
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

Every step already has a GUI handler (worktree read 2026-10-05). Tests click by calling handlers directly, like
`tests/game/test_gui.lua`: `event_handlers.on_gui_click[el.name]({element=el, player_index=1})`, item picks set
`elem_value` then fire `on_gui_elem_changed` (`tests/game/support.lua:41` `S.fill_row`). Today tests write recipes and
machines straight into storage (`S.bind`, `support.lua:52`; `test_gui.lua:88`): the Player run must NEVER do that.

| step | element | handler |
|---|---|---|
| item + rate | `hxrrc_desired_item_button`/`_fluid_button`, `rate_textfield`, `time_unit_dropdown` | `gui/input_container.lua:96-97` |
| recipe per row | `hxrrc_choose_recipe_button` (tags `product_full_name`, `consumer`) | `gui/calculator.lua:171` -> `gui/report.lua:1020` |
| machine | `hxrrc_choose_crafting_machine_button` (tags `recipe_name`) -> `hxrrc_picker_choice_button` (tags.choice) + `hxrrc_picker_confirm_button` | `gui/calculator.lua:140`, `gui/report.lua:1114`, `gui/module_picker.lua:261` |
| modules | `hxrrc_choose_module_button` (`tags.index`) -> choice, `hxrrc_picker_quality_button`, confirm | `gui/module_picker.lua:316`, `gui/modulegui.lua:257` |
| beacons | `hxrrc_choose_beacon_button` (add: `tags.value=nil`) -> picker; `hxrrc_beacon_count_textfield` (set `.text`, fire on_gui_confirmed); `hxrrc_choose_beacon_module_button` | `gui/calculator.lua:140,159,165`, `gui/modulegui.lua:330,388` |
| compute | `hxrrc_compute_button` | `gui/sheet.lua:392` |
| dialog | `hxrrc_generate_blueprint_button` | `gui/sheet.lua:408` -> `gui/blueprint_dialog.lua:293` |
| machinery | `hxrrc_blueprint_{roboport,pole,belt,inserter,long_inserter,pipe,underground_pipe}_button`, `hxrrc_blueprint_input_edge_dropdown`, `hxrrc_blueprint_output_edge_dropdown` | `gui/blueprint_dialog.lua:415-418` |
| generate | `hxrrc_blueprint_generate_button` | `gui/blueprint_dialog.lua:419` |

Traps (read): after each pick `Calculator.recompute_everything` (`gui/calculator.lua:107`) queues a recompute
(`control.lua:191`); the report is rebuilt and old elements go invalid: after each pick wait until
`storage[1].backlogged_computation_count == 0` and `calc_jobs` is empty, then find elements again. Picker repeat click
on the same choice does nil arithmetic (`gui/module_picker.lua:293`): pass `tick = game.tick`, hand empty. Picker shows
only unlocked qualities (`module_picker.lua:104`), dialog refuses locked (`blueprint_dialog.lua:184`): unlock each
quality the Case uses on the force first. Products with one recipe are bound at init (`logic/player_data.lua:25`): skip.
`round_up` / `start_leftovers` are sheet controls (`hxrrc_round_up_machines_checkbox`, `hxrrc_start_leftovers_dropdown`,
`gui/sheet.lua:433-434`); the dropdown does not exist on 2.1: set only where present. Live force research changes
calc and generation (`logic/bp/generation.lua:625-638` rebuilds the catalog from the live game): apply the Case's force
research levels (`environment.force.research` in prepared input) before setup.

## What to build

`tests/game/lib/player_drive.lua` (new), frozen API:
```lua
Drive.case_def(prepared_table) -> def          -- from a decoded prepared_input: targets (full_name, rate_per_second),
    -- columns (recipe_name, machine, setup.modules with quality, setup.beacons {name, count, modules}), settings,
    -- options (round_up, start_leftovers, edges), force research + qualities
Drive.vanilla_def(case) -> def                  -- "vanilla-2.1-red-science-1s" / "...green...": the binds and item of
    -- tests/game/test_capture.lua:8-16 at 1/s (copy the table; do not require test_capture)
Drive.setup(def, done)     -- prepare force, new sheet, every step via handlers, waits between steps (on_tick based,
    -- every wait bounded: 600 ticks per step, error names the stuck step); calls done(sheet) at the end
Drive.generate(sheet, def) -- opens dialog, sets machinery from def.settings + edges, clicks generate; caller waits
    -- storage[1].blueprint_job == nil
```
`tests/game/test_player_drive.lua` (new) + one line in `tests/game/index.lua`. In headless (`not RRC_OFFLINE`) and
offline alike it runs `Drive.setup` and then compares storage with the def. Prepared input comes from module
`tests.game.fixtures.<case_underscored>_prepared` (JSON string; staged by another lane — offline, read it yourself
in the test with `io.open` only when `RRC_OFFLINE`, else `require` at top level guarded by `pcall`).

## Tests (`tests/game/test_player_drive.lua`, offline via `tests/game/offline.lua`)

- PD1 `Drive.case_def` on red-1s, blue-10s, am2 prepared inputs: def rows == solver columns (count, recipe, machine,
  modules, beacons).
- PD2 after `Drive.setup` on red-1s: `storage[1].recipes_by_product_full_name` and chosen machines == def.
- PD3 after `Drive.setup` on blue-10s: modules and beacons (type, count, modules, quality) per recipe == def.
- PD4 red proof: a def with one beacon step dropped -> PD3-style compare reports that recipe (diff printed).
- PD5 no `S.bind`, no write to `storage[1].recipes_by_product_full_name` or
  `identifiers_of_chosen_crafting_machines_by_recipe_name` in `player_drive.lua` (text check).
If the offline mock lacks a GUI behaviour you need, STOP and report the first missing call (file:line in
`tests/harness.lua`); do not edit the harness.

## Files this lane owns

`tests/game/lib/player_drive.lua`, `tests/game/test_player_drive.lua`, `tests/game/index.lua`.

## Integrator-proven (not yours; do not try)

Headless replay of all 15 Cases, generation, build.

## Commit, THEN check

Commit on `lane/318`. **Run the check as the very LAST action.**

## What done mean

- PD1-PD5 pass and print markers; `tests/game/test_player_drive.lua` red on base.
- Offline `test_gui`, `test_generate`, `test_probe` green.
- Diff only inside owned files; guards green.

```checks
{"name": "lane318-check", "command": "sh tools/lane_check_pr.sh 318", "expect_exit": 0, "expect_regex": "lane318-ok", "timeout_s": 3000}
```
