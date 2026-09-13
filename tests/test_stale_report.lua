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

--Stores modules the way ModuleGUI does: names at positive indexes, counts at negative ones, summed effects
local function set_modules(recipe_name, modules)
    local preferences = storage[1].module_preferences_by_recipe_name[recipe_name]
    local effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0, quality = 0}
    for index, module in ipairs(modules) do
        preferences[index], preferences[-index] = module[1], module[2]
        for effect, value in pairs(prototypes.item[module[1]].module_effects) do
            effects[effect] = effects[effect] + module[2] * value
        end
    end
    preferences.effects = effects
end

local function find_all(element, predicate, found)
    found = found or {}
    if predicate(element) then found[#found + 1] = element end
    for _, child in ipairs(element.children) do find_all(child, predicate, found) end
    return found
end

--Module slots of a recipe's row, in order
local function module_slots(sheet_pane, recipe_name)
    local buttons = find_all(sheet_pane, function(element)
        return element.name == "hxrrc_choose_module_button" and element.parent.parent.tags.recipe_name == recipe_name
    end)
    local slots = {}
    for index, button in ipairs(buttons) do slots[index] = button.parent end
    return slots
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

local function fire_confirmed(element)
    event_handlers.on_gui_confirmed[element.name]({element = element, player_index = 1})
end

local function recompute(sheet_pane)
    require("gui.sheet").calculate(nil, sheet_pane, 1)
end

local function reconfigure()
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
end

local function assert_no_effects(recipe_name)
    for _, effect in ipairs(EFFECTS) do
        H.near(storage[1].module_preferences_by_recipe_name[recipe_name].effects[effect], 0, recipe_name .. " " .. effect)
    end
end

--F2a state: grow solved only thanks to a +10% module whose mod is then removed; recomputation fails and the old report stays
local function removed_module_state(shape)
    local world = stale_world(shape)
    set_modules("grow", {{"gone-productivity", 1}})
    local report, sheet_pane = H.run_sheet({{item = "catalyst", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    H.near(report.rows["item/catalyst"].machines, 10, "grow crafts with the module")
    local slot = module_slots(sheet_pane, "grow")[1]
    world.remove_module("gone-productivity")
    reconfigure()
    recompute(sheet_pane)
    H.equal(#world.flying_texts, 1, "recomputation failed")
    return world, sheet_pane, slot
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

--F2f state: gear's recipe removed and grow's module removed; recomputation fails and gear's module controls stay
local function removed_recipe_modules_state(shape)
    local world = stale_world(shape)
    set_modules("gear", {{"speed-module", 1}})
    set_modules("grow", {{"gone-productivity", 1}})
    local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}, {item = "catalyst", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    local slot = module_slots(sheet_pane, "gear")[1]
    world.remove_recipe("gear")
    world.remove_module("gone-productivity")
    reconfigure()
    recompute(sheet_pane)
    H.equal(#world.flying_texts, 1, "recomputation failed")
    H.equal(storage[1].module_preferences_by_recipe_name.gear, nil, "gear preferences removed with the recipe")
    return world, sheet_pane, slot
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " F2a a stale module count field refuses edits", function()
        local world, _, slot = removed_module_state(shape)
        local field = slot.hxrrc_module_count_textfield
        field.text = "3"
        fire_confirmed(field)
        H.equal(storage[1].module_preferences_by_recipe_name.grow[1], nil, "stored modules")
        assert_no_effects("grow")
        H.equal(#world.flying_texts, 1, "no recomputation")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(field.text, "1", "field restored to its count")
    end)

    H.test(shape .. " F2b a stale module button refuses emptying and replacing", function()
        local world, _, slot = removed_module_state(shape)
        local button = slot.hxrrc_choose_module_button
        button.elem_value = nil
        fire_elem_changed(button)
        button.elem_value = "speed-module"
        fire_elem_changed(button)
        H.equal(storage[1].module_preferences_by_recipe_name.grow[1], nil, "stored modules")
        assert_no_effects("grow")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(button.elem_value, nil, "button restored to empty, its module no longer exists")
        H.equal(#world.flying_texts, 1, "no recomputation")
    end)

    H.test(shape .. " F2c module controls on a current report still apply changes", function()
        stale_world(shape)
        local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        local preferences = storage[1].module_preferences_by_recipe_name.gear

        local slot = module_slots(sheet_pane, "gear")[1]
        slot.hxrrc_choose_module_button.elem_value = "speed-module"
        fire_elem_changed(slot.hxrrc_choose_module_button)
        H.equal(preferences[1], "speed-module", "added module")
        H.equal(preferences[-1], 1, "added count")
        H.near(preferences.effects.speed, 0.2, "speed after adding")
        assert(#storage.computation_stack > 0, "adding a module recomputes")
        H.equal(#module_slots(sheet_pane, "gear"), 2, "new empty slot")

        storage.computation_stack = {}
        slot.hxrrc_module_count_textfield.text = "3"
        fire_confirmed(slot.hxrrc_module_count_textfield)
        H.equal(preferences[-1], 3, "changed count")
        H.near(preferences.effects.speed, 0.6, "speed after count change")
        assert(#storage.computation_stack > 0, "changing a count recomputes")

        slot.hxrrc_choose_module_button.elem_value = "gone-productivity"
        fire_elem_changed(slot.hxrrc_choose_module_button)
        H.equal(preferences[1], "gone-productivity", "replaced module")
        H.near(preferences.effects.speed, 0, "speed after replacing")
        H.near(preferences.effects.productivity, 0.3, "productivity after replacing")

        slot.hxrrc_choose_module_button.elem_value = nil
        fire_elem_changed(slot.hxrrc_choose_module_button)
        H.equal(preferences[1], nil, "removed module")
        assert_no_effects("gear")
        H.equal(#module_slots(sheet_pane, "gear"), 1, "only the empty slot left")
    end)

    H.test(shape .. " F2d a stale slot showing another module with the same count refuses edits", function()
        stale_world(shape)
        set_modules("gear", {{"speed-module", 2}})
        local _, pane_a = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local _, pane_b = H.run_sheet({{item = "gear", rate = 2, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = pane_a}

        --replace in sheet A; sheet B is not rebuilt, the way a failed recomputation leaves it
        local slot_a = module_slots(pane_a, "gear")[1]
        slot_a.hxrrc_choose_module_button.elem_value = "gone-productivity"
        fire_elem_changed(slot_a.hxrrc_choose_module_button)
        local preferences = storage[1].module_preferences_by_recipe_name.gear
        H.equal(preferences[1], "gone-productivity", "replaced through sheet A")
        local queued = #storage.computation_stack

        local field_b = module_slots(pane_b, "gear")[1].hxrrc_module_count_textfield
        field_b.text = "5"
        fire_confirmed(field_b)
        H.equal(preferences[-1], 2, "count unchanged")
        H.near(preferences.effects.productivity, 0.2, "productivity unchanged")
        H.near(preferences.effects.speed, 0, "speed unchanged")
        H.equal(#storage.computation_stack, queued, "no recomputation from sheet B")
        H.equal(field_b.text, "2", "field restored")
    end)

    H.test(shape .. " F2e a stale machine button of a removed recipe refuses changes", function()
        local _, _, button = removed_recipe_machine_state(shape)
        local shown = button.elem_value.name
        button.elem_value = {name = shown == "fast-assembler" and "assembler" or "fast-assembler"}
        fire_elem_changed(button)
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(button.elem_value.name, shown, "button restored")
    end)

    H.test(shape .. " F2f a module count field of a removed recipe refuses edits", function()
        local world, _, slot = removed_recipe_modules_state(shape)
        local field = slot.hxrrc_module_count_textfield
        field.text = "4"
        fire_confirmed(field)
        H.equal(storage[1].module_preferences_by_recipe_name.gear, nil, "preferences not recreated")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(#world.flying_texts, 1, "no recomputation")
        H.equal(field.text, "1", "field restored")
    end)

    H.test(shape .. " F2g a module button of a removed recipe refuses changes", function()
        local world, _, slot = removed_recipe_modules_state(shape)
        local button = slot.hxrrc_choose_module_button
        button.elem_value = nil
        fire_elem_changed(button)
        H.equal(storage[1].module_preferences_by_recipe_name.gear, nil, "preferences not recreated")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        H.equal(#world.flying_texts, 1, "no recomputation")
        H.equal(button.elem_value, "speed-module", "button restored, its module still exists")
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
        local _, _, slot = removed_module_state(shape)
        H.refire_on_script_set = true
        slot.hxrrc_module_count_textfield.text = "3"
        H.equal(slot.hxrrc_module_count_textfield.text, "1", "field restored")
        slot.hxrrc_choose_module_button.elem_value = "speed-module"
        H.equal(slot.hxrrc_choose_module_button.elem_value, nil, "module button restored to empty")
        H.equal(storage[1].module_preferences_by_recipe_name.grow[1], nil, "stored modules")

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
        require("gui.report").new(output_flow, {}, {}, {["item/gone"] = 5, ["item/raw"] = 1}, 0, 0)
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
end

H.done("test_stale_report")
