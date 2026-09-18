--A reset restores one player's recipe setups while preserving sheets and rejecting pre-reset work.
local H = require "tests.harness"

local function setup_world(shape, player_indices)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, module_slots = 2})
    world.add_machine({name = "advanced-assembler", categories = {"crafting"}, speed = 2, module_slots = 2})
    world.add_module("speed-module", "speed", {speed = 0.2, consumption = 0.5})
    world.add_beacon({name = "beacon", module_slots = 2})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    for _, player_index in ipairs(player_indices or {1}) do
        world.add_player(player_index)
    end
    world.init()
    require "control"
    world.handlers.on_init()
    return world
end

local function set_target(sheet_flow, index, item, rate, unit, quality, player_index)
    local row = sheet_flow.input_container.children[index]
    row.rate_textfield.text = string.format("%.17g", rate)
    row.time_unit_dropdown.selected_index = unit == "/m" and 1 or 2
    row.hxrrc_desired_item_button.elem_value = {name = item, quality = quality}
    event_handlers.on_gui_elem_changed.hxrrc_desired_item_button({element = row.hxrrc_desired_item_button, player_index = player_index or sheet_flow.player_index})
end

local function sheet_state(sheet_flow)
    local leftovers
    for _, cell in ipairs(sheet_flow.hxrrc_sheet_controls.children) do
        if cell.name == "start_leftovers_dropdown_cell" then
            for _, child in ipairs(cell.children) do
                if child.name == "hxrrc_start_leftovers_dropdown" then leftovers = child.selected_index end
            end
        end
    end
    local state = {rows = {}, round_up = require("gui.sheet").round_up_checkbox_of(sheet_flow).state, leftovers = leftovers}
    for _, row in ipairs(sheet_flow.input_container.children) do
        local item = row.hxrrc_desired_item_button.elem_value
        state.rows[#state.rows + 1] = {
            rate = row.rate_textfield.text,
            unit = row.time_unit_dropdown.selected_index,
            item = item and item.name,
            quality = item and item.quality and item.quality.name,
        }
    end
    return state
end

local function setup_state(player_index)
    local player_storage = storage[player_index]
    local machine = player_storage.identifiers_of_chosen_crafting_machines_by_recipe_name.gear
    local setup = player_storage.module_setups_by_recipe_name.gear
    return {
        machine = machine and {name = machine.name, quality = machine.quality},
        modules = setup and setup.modules,
        beacons = setup and setup.beacons,
        recipes = player_storage.recipes_by_product_full_name["item/gear"] and player_storage.recipes_by_product_full_name["item/gear"].name,
        inverse = player_storage.product_full_names_by_recipe_name.gear,
        consumers = player_storage.consumer_product_full_names,
        burners = player_storage.burners_by_product_full_name,
        loops = player_storage.quality_loops_by_key,
    }
end

local function install_calculation_fixture(Jobs, commits, on_step)
    Jobs.register("calculation", {
        begin = function(context)
            return {remaining = context.remaining or 1, label = context.label or "reset"}
        end,
        step = function(job, budget)
            if on_step then on_step(job) end
            job.state.remaining = job.state.remaining - 1
            budget.ops = budget.ops - 1
            if job.state.remaining <= 0 then
                job.done = true
                job.ok = true
                job.result = {label = job.state.label}
            end
            return job
        end,
        publish = function(job)
            commits[#commits + 1] = job.result.label
        end,
    })
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " R1 reset restores setups and preserves every target row, tab, option and GUI handle", function()
        local world = setup_world(shape)
        local Sheet = require "gui.sheet"
        local Reset = require "logic.reset"
        local pane = storage[1].sheet_section.sheet_pane
        local calculator, sheet_section = storage[1].calculator, storage[1].sheet_section
        local first = pane.tabs[1].content
        set_target(first, 1, "gear", 12.5, "/s", "uncommon")
        set_target(first, 2, "raw", 30, "/m")
        Sheet.round_up_checkbox_of(first).state = true
        if shape == "2.0" then
            first.hxrrc_sheet_controls.start_leftovers_dropdown_cell.hxrrc_start_leftovers_dropdown.selected_index = 2
        end
        Sheet.new(pane)
        local second = pane.tabs[2].content
        set_target(second, 1, "gear", 7, "/m")
        pane.selected_tab_index = 2
        local before_first, before_second = sheet_state(first), sheet_state(second)
        local before_tab_count, before_selected = #pane.tabs, pane.selected_tab_index

        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "advanced-assembler", quality = "rare"}
        storage[1].module_setups_by_recipe_name.gear = {
            modules = {{name = "speed-module", quality = "rare"}},
            beacons = {{name = "beacon", quality = "rare", count = 3, sharing = 2, modules = {{name = "speed-module"}}}},
        }
        storage[1].consumer_product_full_names["item/raw"] = true
        storage[1].recipes_by_product_full_name["item/raw"] = prototypes.recipe.gear
        storage[1].product_full_names_by_recipe_name.gear = "item/raw"
        storage[1].burners_by_product_full_name["item/raw"] = {name = "burner", quality = "rare"}
        storage[1].quality_loops_by_key["gear@uncommon"] = {item = "gear", quality = "uncommon", recycle_recipe_name = "gear"}
        storage[1].blueprint_settings = {["sheet-keep"] = {round_up = true, infrastructure = "kept"}}

        local count = Reset.run(1)
        H.equal(count, 2, "both sheets were queued")
        H.equal(storage[1].calculator, calculator, "calculator handle survived")
        H.equal(storage[1].sheet_section, sheet_section, "sheet section handle survived")
        H.equal(#pane.tabs, before_tab_count, "tab count survived")
        H.equal(pane.selected_tab_index, before_selected, "selected tab survived")
        H.deep_equal(sheet_state(first), before_first, "first sheet targets and options survived")
        H.deep_equal(sheet_state(second), before_second, "second sheet targets survived")
        H.deep_equal(storage[1].blueprint_settings, {["sheet-keep"] = {round_up = true, infrastructure = "kept"}}, "blueprint settings survived")

        local after = setup_state(1)
        H.equal(after.machine.name, storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear.name, "machine was reset to the fresh default")
        H.deep_equal(after.modules, {}, "machine modules were reset")
        H.deep_equal(after.beacons, {}, "beacon groups were reset")
        H.equal(after.recipes, "gear", "automatic producer binding was restored")
        H.equal(after.inverse, "item/gear", "inverse binding was restored")
        H.deep_equal(after.consumers, {}, "consumer bindings were reset")
        H.deep_equal(after.burners, {}, "burner bindings were reset")
        H.deep_equal(after.loops, {}, "quality loops were reset")
    end)

    H.test(shape .. " R2 reset is scoped to one player and keeps the other player's setups, sheets and jobs", function()
        local world = setup_world(shape, {1, 2})
        local Reset = require "logic.reset"
        local Jobs = require "logic.jobs"
        local pane_two = storage[2].sheet_section.sheet_pane
        set_target(pane_two.tabs[1].content, 1, "gear", 9, "/s", nil, 2)
        storage[2].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "advanced-assembler"}
        storage[2].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}}
        storage[2].quality_loops_by_key.keep = {item = "gear", quality = "rare"}
        storage[2].sheet_revision = {["player-two-sheet"] = 4}
        Jobs.request_sheet(2, "player-two-sheet", {revisions = {sheet = 4, config = 0}, state = {keep = true}})
        local before_setup = setup_state(2)
        local before_sheet = sheet_state(pane_two.tabs[1].content)
        local before_job = storage[2].calc_jobs["player-two-sheet"]
        local before_revision = storage[2].config_revision

        Reset.run(1)

        H.deep_equal(setup_state(2), before_setup, "player two setup survived")
        H.deep_equal(sheet_state(pane_two.tabs[1].content), before_sheet, "player two sheet survived")
        H.deep_equal(storage[2].calc_jobs["player-two-sheet"].state, before_job.state, "player two job survived")
        H.equal(storage[2].config_revision, before_revision, "player two revision survived")
    end)

    H.test(shape .. " R3 reset during a running calculation prevents old work from committing", function()
        local world = setup_world(shape)
        local Reset = require "logic.reset"
        local Jobs = require "logic.jobs"
        local commits, reset_once = {}, false
        install_calculation_fixture(Jobs, commits, function(job)
            if not reset_once and job.state.label == "old" then
                reset_once = true
                Reset.run(job.player_index)
            end
        end)
        Jobs.OPS_PER_TICK = 1
        local sheet_id = storage[1].sheet_section.sheet_pane.tabs[1].content.tags.hxrrc_sheet_id
        storage[1].sheet_revision = {[sheet_id] = 0}
        Jobs.request_sheet(1, sheet_id, {kind = "calculation", sheet_id = sheet_id, label = "old", remaining = 1,
            revisions = {sheet = 0, config = 0}})

        H.run_ticks(world, 1)
        H.equal(#commits, 0, "pre-reset work did not commit")
        H.equal(storage[1].config_revision, 1, "reset advanced the configuration revision")
        H.run_ticks(world, 1)
        H.equal(#commits, 1, "the post-reset calculation committed")
        H.equal(commits[1], "reset", "only new work was published")
    end)

    H.test(shape .. " R4 a pending pipette paste cannot restore a cleared setup", function()
        local world = setup_world(shape)
        local Reset = require "logic.reset"
        local Pipette = require "gui.pipette"
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}}
        storage[1].pipette = {id = 7, kind = "machine", item = {name = "advanced-assembler"}, machine = {name = "advanced-assembler"}, setup = {modules = {{name = "speed-module"}}, beacons = {}}}
        storage[1].pipette_requests = {{clipboard_id = 7, tick = 0, kind = "machine", target = {}}}
        Reset.run(1)
        H.equal(storage[1].pipette, nil, "clipboard was dropped")
        H.equal(storage[1].pipette_requests, nil, "pending paste was dropped")
        Pipette.run_requests(1)
        H.deep_equal(storage[1].module_setups_by_recipe_name.gear.modules, {}, "the cleared setup stayed cleared")
    end)

    H.test(shape .. " R5 two resets in a row leave the same setup state and report completion", function()
        local world = setup_world(shape)
        local Reset = require "logic.reset"
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}}
        Reset.on_reset_clicked({player_index = 1})
        local first = setup_state(1)
        local first_revision = storage[1].config_revision
        Reset.run(1)
        H.deep_equal(setup_state(1), first, "second reset kept the first reset's state")
        H.equal(storage[1].config_revision, first_revision + 1, "each reset advanced the revision")
        H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.reset_setups_done", "completion was reported")
    end)

    H.test(shape .. " R6 empty and missing-prototype sheets reset without crashing", function()
        local world = setup_world(shape)
        local Reset = require "logic.reset"
        local Indexer = require "logic.indexer"
        local pane = storage[1].sheet_section.sheet_pane
        H.equal(Reset.run(1), 1, "an empty sheet was queued")
        world.remove_machine("assembler")
        world.remove_machine("advanced-assembler")
        Indexer.run()
        H.equal(Reset.run(1), 1, "a missing machine prototype did not crash reset")
        H.equal(storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear, nil, "missing machine has no stale choice")
        H.equal(#pane.tabs, 1, "the sheet still exists")
    end)
end

H.done("test_reset")
