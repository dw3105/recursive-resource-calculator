--A report left on screen after a failed recomputation must not let its controls act on changed or missing data
local H = require "tests.harness"

local EFFECTS = {"consumption", "speed", "productivity", "pollution", "quality"}

local function stale_world(shape)
    local world = H.new_world(shape)
    require "gui.calculator" --registers the event handlers the tests fire
    for _, item in ipairs({"catalyst", "gear", "raw", "raw-extra"}) do world.add_item(item) end
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "grow", category = "crafting", ingredients = {{name = "catalyst", amount = 1}},
        products = {{name = "catalyst", amount = 1, ignored = 0}}})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_module("gone-productivity", "productivity", {productivity = 0.1})
    world.add_module("speed-module", "speed", {speed = 0.2})
    world.add_player(1)
    world.init()
    return world
end

--Stores machine modules the way the module cell does: a dense list in slot order
local function set_modules(recipe_name, module_names)
    local modules = {}
    for index, name in ipairs(module_names) do modules[index] = {name = name} end
    storage[1].module_setups_by_recipe_name[recipe_name].modules = modules
end

local function stored_names(recipe_name)
    local names = {}
    for _, module in ipairs(storage[1].module_setups_by_recipe_name[recipe_name].modules) do names[#names + 1] = module.name end
    return table.concat(names, ",")
end

local function find_all(element, predicate, found)
    found = found or {}
    if predicate(element) then found[#found + 1] = element end
    for _, child in ipairs(element.children) do find_all(child, predicate, found) end
    return found
end

--The recipe of the module cell holding an element: the nearest ancestor tagged with one
local function recipe_of(element)
    local ancestor = element.parent
    while ancestor and not ancestor.tags.recipe_name do ancestor = ancestor.parent end
    return ancestor and ancestor.tags.recipe_name
end

--Module slot buttons of a recipe's row, in order
local function module_buttons(sheet_pane, recipe_name)
    return find_all(sheet_pane, function(element)
        return element.name == "hxrrc_choose_module_button" and recipe_of(element) == recipe_name
    end)
end

local function machine_button(sheet_pane, product_full_name)
    local found = find_all(sheet_pane, function(element)
        if element.name ~= "hxrrc_choose_crafting_machine_button" then return false end
        local machine_cell = element.parent
        local item_cell = machine_cell.parent.children[machine_cell:get_index_in_parent() - 1]
        return item_cell.children[1].sprite == product_full_name
    end)
    return found[1]
end

local function fire_elem_changed(element)
    event_handlers.on_gui_elem_changed[element.name]({element = element, player_index = 1})
end

local function recompute(sheet_pane)
    require("gui.sheet").calculate(nil, sheet_pane, 1)
end

local function reconfigure()
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
end

local function assert_no_effects(recipe_name)
    local effects = require("logic.utils").recipe_effects(1, recipe_name)
    for _, effect in ipairs(EFFECTS) do
        H.near(effects[effect], 0, recipe_name .. " " .. effect)
    end
end

--F2a state: grow solved only thanks to a +10% module whose mod is then removed; recomputation fails and the old report stays
local function removed_module_state(shape)
    local world = stale_world(shape)
    set_modules("grow", {"gone-productivity"})
    local report, sheet_pane = H.run_sheet({{item = "catalyst", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    H.near(report.rows["item/catalyst"].machines, 10, "grow crafts with the module")
    local buttons = module_buttons(sheet_pane, "grow")
    world.remove_module("gone-productivity")
    reconfigure()
    recompute(sheet_pane)
    H.equal(#world.flying_texts, 1, "recomputation failed")
    return world, sheet_pane, buttons
end

--F2e state: a report whose recipe was then removed by a mod, never rebuilt
local function removed_recipe_machine_state(shape)
    local world = stale_world(shape)
    world.add_machine({name = "fast-assembler", categories = {"crafting"}, speed = 2})
    reconfigure()
    local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    local button = machine_button(sheet_pane, "item/gear")
    world.remove_recipe("gear")
    reconfigure()
    return world, sheet_pane, button
end

--F2f state: gear's recipe removed and grow's module removed; recomputation fails and gear's module slots stay
local function removed_recipe_modules_state(shape)
    local world = stale_world(shape)
    set_modules("gear", {"speed-module"})
    set_modules("grow", {"gone-productivity"})
    local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}, {item = "catalyst", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    local buttons = module_buttons(sheet_pane, "gear")
    world.remove_recipe("gear")
    world.remove_module("gone-productivity")
    reconfigure()
    recompute(sheet_pane)
    H.equal(#world.flying_texts, 1, "recomputation failed")
    H.equal(storage[1].module_setups_by_recipe_name.gear, nil, "gear setup removed with the recipe")
    return world, sheet_pane, buttons
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " F2a a stale empty module slot refuses a pick", function()
        local world, _, buttons = removed_module_state(shape)
        local button = buttons[2]
        button.elem_value = {name = "speed-module"}
        fire_elem_changed(button)
        H.equal(stored_names("grow"), "", "stored modules")
        assert_no_effects("grow")
        H.equal(#world.flying_texts, 1, "no recomputation")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(button.elem_value, nil, "slot restored to empty")
    end)

    H.test(shape .. " F2b a stale module slot refuses emptying and replacing", function()
        local world, _, buttons = removed_module_state(shape)
        local button = buttons[1]
        button.elem_value = nil
        fire_elem_changed(button)
        button.elem_value = {name = "speed-module"}
        fire_elem_changed(button)
        H.equal(stored_names("grow"), "", "stored modules")
        assert_no_effects("grow")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(button.elem_value, nil, "slot restored to empty, its module no longer exists")
        H.equal(#world.flying_texts, 1, "no recomputation")
    end)

    H.test(shape .. " F2c module slots on a current report still apply changes", function()
        stale_world(shape)
        local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        local Utils = require "logic.utils"
        local function pick(value)
            local button = module_buttons(sheet_pane, "gear")[1]
            button.elem_value = value
            fire_elem_changed(button)
        end

        pick({name = "speed-module"})
        H.equal(stored_names("gear"), "speed-module", "added module")
        H.near(Utils.recipe_effects(1, "gear").speed, 0.2, "speed after adding")
        assert(#storage.computation_stack > 0, "adding a module recomputes")
        H.equal(#module_buttons(sheet_pane, "gear"), 4, "every slot after rebuilding")

        storage.computation_stack = {}
        pick({name = "gone-productivity"})
        H.equal(stored_names("gear"), "gone-productivity", "replaced module")
        H.near(Utils.recipe_effects(1, "gear").speed, 0, "speed after replacing")
        H.near(Utils.recipe_effects(1, "gear").productivity, 0.1, "productivity after replacing")
        assert(#storage.computation_stack > 0, "replacing a module recomputes")

        pick(nil)
        H.equal(stored_names("gear"), "", "removed module")
        assert_no_effects("gear")
    end)

    H.test(shape .. " F2d a stale slot showing a module replaced through another sheet refuses edits", function()
        stale_world(shape)
        set_modules("gear", {"speed-module"})
        local _, pane_a = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local _, pane_b = H.run_sheet({{item = "gear", rate = 2, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = pane_a}

        --replace in sheet A; sheet B is not rebuilt, the way a failed recomputation leaves it
        local button_a = module_buttons(pane_a, "gear")[1]
        button_a.elem_value = {name = "gone-productivity"}
        fire_elem_changed(button_a)
        H.equal(stored_names("gear"), "gone-productivity", "replaced through sheet A")
        local queued = #storage.computation_stack

        local button_b = module_buttons(pane_b, "gear")[1]
        button_b.elem_value = nil
        fire_elem_changed(button_b)
        H.equal(stored_names("gear"), "gone-productivity", "module unchanged")
        H.near(require("logic.utils").recipe_effects(1, "gear").productivity, 0.1, "productivity unchanged")
        H.equal(#storage.computation_stack, queued, "no recomputation from sheet B")
        H.equal(button_b.elem_value and button_b.elem_value.name, "speed-module", "slot restored")
    end)

    H.test(shape .. " F2e a stale machine button of a removed recipe refuses changes", function()
        local _, _, button = removed_recipe_machine_state(shape)
        local shown = button.elem_value.name
        button.elem_value = {name = shown == "fast-assembler" and "assembler" or "fast-assembler"}
        fire_elem_changed(button)
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(button.elem_value.name, shown, "button restored")
    end)

    H.test(shape .. " F2f an empty module slot of a removed recipe refuses a pick", function()
        local world, _, buttons = removed_recipe_modules_state(shape)
        local button = buttons[2]
        button.elem_value = {name = "speed-module"}
        fire_elem_changed(button)
        H.equal(storage[1].module_setups_by_recipe_name.gear, nil, "setup not recreated")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(#world.flying_texts, 1, "no recomputation")
        H.equal(button.elem_value, nil, "slot restored to empty")
    end)

    H.test(shape .. " F2g a module slot of a removed recipe refuses changes", function()
        local world, _, buttons = removed_recipe_modules_state(shape)
        local button = buttons[1]
        button.elem_value = nil
        fire_elem_changed(button)
        H.equal(storage[1].module_setups_by_recipe_name.gear, nil, "setup not recreated")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(#world.flying_texts, 1, "no recomputation")
        H.equal(button.elem_value and button.elem_value.name, "speed-module", "slot restored, its module still exists")
    end)

    H.test(shape .. " F2h a target item removed by a mod is left out of the report", function()
        local world = stale_world(shape)
        local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}, {item = "raw-extra", rate = 2, unit = "/s"}})
        prototypes.item["raw-extra"] = nil
        recompute(sheet_pane)
        local report = H.parse_report(sheet_pane.tabs[1].content.output_flow)
        H.equal(report.rows["item/raw-extra"], nil, "row of removed item")
        H.near(report.rows["item/gear"].rate, 1, "gear row")
        H.near(report.rows["item/raw"].rate, 1, "raw row")
        H.equal(#world.flying_texts, 0, "no error message")
    end)

    H.test(shape .. " F2i refused changes restore once even if the restore raises the event again", function()
        local _, _, buttons = removed_module_state(shape)
        H.refire_on_script_set = true
        buttons[2].elem_value = {name = "speed-module"}
        H.equal(buttons[2].elem_value, nil, "empty slot restored")
        buttons[1].elem_value = {name = "speed-module"}
        H.equal(buttons[1].elem_value, nil, "slot of a removed module restored to empty")
        H.equal(stored_names("grow"), "", "stored modules")

        local _, _, button = removed_recipe_machine_state(shape)
        H.refire_on_script_set = true
        local shown = button.elem_value.name
        button.elem_value = {name = shown == "fast-assembler" and "assembler" or "fast-assembler"}
        H.equal(button.elem_value.name, shown, "machine button restored")
        H.equal(#storage.computation_stack, 0, "nothing queued")
    end)

    H.test(shape .. " F2j a machine quality removed by a mod falls back to normal", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speeds_by_quality = {normal = 1, legendary = 2.5}})
        world.add_recipe({name = "gear", category = "crafting", energy = 5, ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler", quality = "legendary"}
        world.remove_quality("legendary")
        reconfigure()
        local identifier = storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear
        H.equal(identifier.name, "assembler", "machine kept")
        H.equal(identifier.quality, nil, "removed quality dropped")
        local report = H.run_sheet({{item = "gear", rate = 2, unit = "/s"}})
        H.near(report.rows["item/gear"].machines, 2 * 5, "normal speed")
        H.equal(report.rows["item/gear"].machine.quality, nil, "button without quality")
    end)

    H.test(shape .. " F2k the input container leaves out a target whose item was removed", function()
        stale_world(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}, {item = "raw-extra", rate = 2, unit = "/s"}})
        prototypes.item["raw-extra"] = nil
        local rates = require("gui.input_container").get_desired_production_rates_by_full_item_name(sheet_flow.input_container)
        H.equal(rates["item/raw-extra"], nil, "removed target")
        H.near(rates["item/gear"], 1, "gear target")
    end)

    H.test(shape .. " F2l the report leaves out a row whose item was removed", function()
        stale_world(shape)
        local output_flow = H.gui_root({type = "flow", name = "output_flow"})
        require("gui.report").new(output_flow, {status = "ok", columns = {}, recipe_rates = {}, solved_rates = {}, reasons_by_column = {},
            unsolved_rates = {["item/gone"] = 5, ["item/raw"] = 1}}, 0, 0)
        local report = H.parse_report(output_flow)
        H.equal(report.rows["item/gone"], nil, "row of missing item")
        H.near(report.rows["item/raw"].rate, 1, "raw row")
    end)

    H.test(shape .. " F2m a refused machine change does not restore a quality that was removed", function()
        local world = stale_world(shape)
        world.add_machine({name = "fast-assembler", categories = {"crafting"}, speed = 2})
        reconfigure()
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler", quality = "legendary"}
        local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        local button = machine_button(sheet_pane, "item/gear")
        H.equal(button.elem_value.quality, "legendary", "button shows the chosen quality")
        world.remove_recipe("gear")
        world.remove_quality("legendary")
        reconfigure()

        button.elem_value = {name = "fast-assembler"}
        fire_elem_changed(button)
        H.equal(button.elem_value.name, "assembler", "button restored to its machine")
        H.equal(button.elem_value.quality, nil, "removed quality not restored")
        H.equal(#storage.computation_stack, 0, "nothing queued")
    end)

    H.test(shape .. " F2n a module cell left from an older version refuses changes and restores its module", function()
        stale_world(shape)
        local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        --the 1.1.14 cell: a flow tagged with the recipe, one flow per slot holding an item button and a count field
        local old_cell = H.gui_root({type = "flow", name = "old_cell", tags = {recipe_name = "gear"}})
        local old_slot = old_cell.add{type = "flow", tags = {module_name = "speed-module", count = 2}}
        local button = old_slot.add{type = "choose-elem-button", name = "hxrrc_choose_module_button", elem_type = "item", item = "speed-module"}
        old_slot.add{type = "textfield", name = "hxrrc_module_count_textfield", text = "2"}

        button.elem_value = nil
        fire_elem_changed(button)
        H.equal(button.elem_value, "speed-module", "old button restored to its module")
        H.equal(stored_names("gear"), "", "stored modules")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(event_handlers.on_gui_confirmed.hxrrc_module_count_textfield, nil, "old count field has no handler")
    end)

    H.test(shape .. " W4 after the product's recipe changes, module and beacon controls of the old recipe refuse edits", function()
        local world = H.new_world(shape)
        require "gui.calculator" --registers the event handlers the tests fire
        world.add_item("raw")
        world.add_item("gear")
        world.add_module("productivity-module", "productivity", {productivity = 0.1})
        world.add_module("speed-module", "speed", {speed = 0.2})
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_beacon({name = "beacon"})
        world.add_recipe({name = "a", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        --b gives back the gear it takes, so without productivity it cannot solve and a failed recomputation keeps the old report
        world.add_recipe({name = "b", category = "crafting", ingredients = {{name = "gear", amount = 1}}, products = {{name = "gear", amount = 1, ignored = 0}}})
        world.add_player(1)
        world.init()
        world.bind("item/gear", "a")
        storage[1].module_setups_by_recipe_name.a.beacons = {{name = "beacon", count = 1, sharing = 1, modules = {{name = "speed-module"}}}}
        local _, pane_a = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local _, pane_b = H.run_sheet({{item = "gear", rate = 2, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = pane_a}

        local function first(pane, name)
            return find_all(pane, function(element) return element.name == name end)[1]
        end
        --controls of sheet A as they were before its recomputation cleared them, and sheet B's, which is never rebuilt
        local controls = {}
        for _, pane in ipairs({pane_a, pane_b}) do
            controls[pane] = {}
            for _, name in ipairs({"hxrrc_choose_module_button", "hxrrc_beacon_count_textfield", "hxrrc_beacon_sharing_textfield",
                    "hxrrc_choose_beacon_module_button", "hxrrc_choose_beacon_button"}) do
                controls[pane][name] = first(pane, name)
            end
        end

        local recipe_button = find_all(pane_a, function(element) return element.name == "hxrrc_choose_recipe_button" end)[1]
        recipe_button.elem_value = "b"
        fire_elem_changed(recipe_button)
        recompute(pane_a)
        H.equal(#world.flying_texts, 1, "recipe b fails to solve")
        H.equal(storage[1].recipes_by_product_full_name["item/gear"].name, "b", "gear is now bound to b")
        storage.computation_stack = {}
        local function confirm(field, text)
            field.text = text
            event_handlers.on_gui_confirmed[field.name]({element = field, player_index = 1})
        end
        for _, pane in ipairs({pane_a, pane_b}) do
            local what = pane == pane_a and "sheet with the failed recomputation" or "sibling sheet"
            local function first(_, name) return controls[pane][name] end
            local slot = first(pane, "hxrrc_choose_module_button")
            slot.elem_value = {name = "productivity-module"}
            fire_elem_changed(slot)
            H.equal(slot.elem_value, nil, what .. ": module slot restored")
            local count = first(pane, "hxrrc_beacon_count_textfield")
            confirm(count, "2")
            H.equal(count.text, "1", what .. ": beacon count restored")
            local sharing = first(pane, "hxrrc_beacon_sharing_textfield")
            confirm(sharing, "3")
            H.equal(sharing.text, "1", what .. ": beacon sharing restored")
            local beacon_slot = first(pane, "hxrrc_choose_beacon_module_button")
            beacon_slot.elem_value = nil
            fire_elem_changed(beacon_slot)
            H.equal(beacon_slot.elem_value and beacon_slot.elem_value.name, "speed-module", what .. ": beacon slot restored")
            local beacon = first(pane, "hxrrc_choose_beacon_button")
            beacon.elem_value = nil
            fire_elem_changed(beacon)
            H.equal(beacon.elem_value and beacon.elem_value.name, "beacon", what .. ": beacon button restored")
        end

        local setups = storage[1].module_setups_by_recipe_name
        H.equal(#setups.a.modules, 0, "recipe a machine modules unchanged")
        H.equal(#setups.a.beacons, 1, "recipe a keeps its beacon group")
        H.equal(setups.a.beacons[1].count, 1, "recipe a beacon count unchanged")
        H.equal(setups.a.beacons[1].sharing, 1, "recipe a beacon sharing unchanged")
        H.equal(#setups.a.beacons[1].modules, 1, "recipe a beacon modules unchanged")
        H.equal(#setups.b.modules, 0, "recipe b machine modules unchanged")
        H.equal(#setups.b.beacons, 0, "recipe b beacon groups unchanged")
        H.equal(#storage.computation_stack, 0, "nothing queued")
    end)

    H.test(shape .. " W1 a machine change through one sheet makes another sheet's module slots stale", function()
        local world = stale_world(shape)
        world.add_machine({name = "fast-assembler", categories = {"crafting"}, speed = 2})
        reconfigure()
        local _, pane_a = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local _, pane_b = H.run_sheet({{item = "gear", rate = 2, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = pane_a}

        local button = machine_button(pane_a, "item/gear")
        button.elem_value = {name = button.elem_value.name == "fast-assembler" and "assembler" or "fast-assembler"}
        fire_elem_changed(button)
        local queued = #storage.computation_stack

        local slot_b = module_buttons(pane_b, "gear")[1]
        slot_b.elem_value = {name = "speed-module"}
        fire_elem_changed(slot_b)
        H.equal(stored_names("gear"), "", "stored modules")
        H.equal(#storage.computation_stack, queued, "no recomputation from sheet B")
        H.equal(slot_b.elem_value, nil, "slot restored")
    end)
end

H.done("test_stale_report")
