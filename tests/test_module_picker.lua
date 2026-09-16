--The module picker window: what it offers, single and double clicks, the tick, clear, stale cells, beacon slots, and every way it closes
local H = require "tests.harness"

local M = {}

--Gear on a 4-slot assembler; a 2-slot beacon taking speed and efficiency; a hidden speed module; an unlinked modded quality, legendary locked
local function picker_world(shape)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_module("speed-module", "speed", {speed = 0.2})
    world.add_module("efficiency-module", "efficiency", {consumption = -0.3})
    world.add_module("productivity-module", "productivity", {productivity = 0.1})
    world.add_module("hidden-module", "speed", {speed = 0.5})
    world.set_item_flags("hidden-module", {hidden = true})
    world.add_unlinked_quality("odd", 4)
    world.lock_quality("legendary")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, module_slots = 4})
    world.add_beacon({name = "beacon", module_slots = 2, allowed_module_categories = {"speed", "efficiency"}})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.init()
    M.Calculator = require "gui.calculator"
    M.ModulePicker = require "gui.module_picker"
    M.Sheet = require "gui.sheet"
    M.Utils = require "logic.utils"
    return world
end

local function find_all(element, predicate, found)
    found = found or {}
    if predicate(element) then found[#found + 1] = element end
    for _, child in ipairs(element.children) do find_all(child, predicate, found) end
    return found
end

local function gear_sheet()
    local report, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    return report, sheet_pane
end

local function machine_slots(root)
    return find_all(root, function(element) return element.name == "hxrrc_choose_module_button" end)
end

local function beacon_slots(root, group)
    return find_all(root, function(element) return element.name == "hxrrc_choose_beacon_module_button" and element.tags.group == group end)
end

local function state() return storage[1].module_picker end

local function frames()
    return find_all(game.players[1].gui.screen, function(element) return element.name == "hxrrc_module_picker" end)
end

local function module_buttons()
    return find_all(state().frame, function(element) return element.name == "hxrrc_picker_module_button" end)
end

local function quality_buttons()
    return find_all(state().frame, function(element) return element.name == "hxrrc_picker_quality_button" end)
end

local function by_tag(buttons, key, value)
    for _, button in ipairs(buttons) do
        if button.tags[key] == value then return button end
    end
end

local function click(element, tick)
    event_handlers.on_gui_click[element.name]({element = element, player_index = 1, tick = tick or 0, button = defines.mouse_button_type.left})
end

local function click_module(name, tick) click(by_tag(module_buttons(), "module", name), tick) end
local function click_quality(name, tick) click(by_tag(quality_buttons(), "quality", name), tick) end
local function confirm_button() return state().frame.picker_footer.hxrrc_picker_confirm_button end
local function clear_button() return state().frame.picker_footer.hxrrc_picker_clear_button end

local function stored(modules)
    local names = {}
    for _, module in ipairs(modules) do names[#names + 1] = module.name .. (module.quality and ("@" .. module.quality) or "") end
    return table.concat(names, ",")
end

local function gear_modules() return stored(storage[1].module_setups_by_recipe_name.gear.modules) end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N6a the grid lists exactly the slot's offered modules in order, and every unlocked quality by level", function()
        picker_world(shape)
        local _, sheet_pane = gear_sheet()
        H.equal(M.ModulePicker.open(machine_slots(sheet_pane)[1]), true, "opened")
        local names = {}
        for _, button in ipairs(module_buttons()) do names[#names + 1] = button.tags.module end
        H.equal(table.concat(names, ","), "efficiency-module,productivity-module,speed-module", "offered modules, hidden left out")
        H.equal(module_buttons()[1].sprite, "item/efficiency-module", "module sprite")
        local qualities = {}
        for _, button in ipairs(quality_buttons()) do qualities[#qualities + 1] = button.tags.quality end
        H.equal(table.concat(qualities, ","), "normal,uncommon,rare,epic,odd", "unlocked qualities by level, the unlinked one included, locked legendary left out")
        H.equal(#frames(), 1, "one window")
        H.equal(frames()[1].auto_center, true, "centred")
        H.equal(confirm_button().sprite, "utility/check_mark_green", "green tick")
        H.equal(confirm_button().style.name, "item_and_count_select_confirm", "tick style")
    end)

    H.test(shape .. " N6b N6g one click selects; a second click on it within 30 ticks fills the empty row and closes", function()
        picker_world(shape)
        local _, sheet_pane = gear_sheet()
        M.ModulePicker.open(machine_slots(sheet_pane)[3])
        storage.computation_stack = {}
        click_module("speed-module", 100)
        H.equal(state().selected_module, "speed-module", "selected")
        H.equal(by_tag(module_buttons(), "module", "speed-module").toggled, true, "shown pressed")
        H.equal(gear_modules(), "", "nothing stored on one click")
        click_module("speed-module", 130)
        H.equal(gear_modules(), "speed-module,speed-module,speed-module,speed-module", "double click stores through store_pick: the empty row fills")
        H.equal(state(), nil, "picker state gone")
        H.equal(#frames(), 0, "window closed")
        assert(#storage.computation_stack > 0, "recomputes")
    end)

    H.test(shape .. " N6c N6d a fast click on another module, or a slow second click, only selects", function()
        picker_world(shape)
        local _, sheet_pane = gear_sheet()
        M.ModulePicker.open(machine_slots(sheet_pane)[1])
        click_module("speed-module", 0)
        click_module("efficiency-module", 5)
        H.equal(state().selected_module, "efficiency-module", "selection moved")
        H.equal(gear_modules(), "", "nothing stored")
        click_module("efficiency-module", 36)
        H.equal(gear_modules(), "", "31 ticks later is not a double click")
        assert(state(), "still open")
    end)

    H.test(shape .. " N6e N6l the tick stores the selection and closes; only the selected module and quality are pressed", function()
        picker_world(shape)
        local _, sheet_pane = gear_sheet()
        M.ModulePicker.open(machine_slots(sheet_pane)[1])
        click_module("speed-module", 0)
        click_module("efficiency-module", 100)
        click_quality("rare", 200)
        local pressed = {}
        for _, button in ipairs(module_buttons()) do if button.toggled then pressed[#pressed + 1] = button.tags.module end end
        for _, button in ipairs(quality_buttons()) do if button.toggled then pressed[#pressed + 1] = button.tags.quality end end
        H.equal(table.concat(pressed, ","), "efficiency-module,rare", "only the selection is pressed")
        click(confirm_button(), 300)
        H.equal(gear_modules(), "efficiency-module@rare,efficiency-module@rare,efficiency-module@rare,efficiency-module@rare", "stored at the quality")
        H.equal(state(), nil, "closed")
    end)

    H.test(shape .. " N6f N6q clear removes a filled slot's module and shifts the rest left; on an empty slot it closes and changes nothing", function()
        picker_world(shape)
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}, {name = "efficiency-module"}}
        local _, sheet_pane = gear_sheet()
        M.ModulePicker.open(machine_slots(sheet_pane)[1])
        H.equal(state().selected_module, "speed-module", "the slot's module preselected")
        storage.computation_stack = {}
        click(clear_button())
        H.equal(gear_modules(), "efficiency-module", "removed, the rest shifted left")
        H.equal(state(), nil, "closed")
        assert(#storage.computation_stack > 0, "recomputes")

        _, sheet_pane = gear_sheet()
        M.ModulePicker.open(machine_slots(sheet_pane)[4])
        storage.computation_stack = {}
        click(clear_button())
        H.equal(gear_modules(), "efficiency-module", "empty slot: nothing changed")
        H.equal(state(), nil, "closed")
        H.equal(#storage.computation_stack, 0, "no recompute")
    end)

    H.test(shape .. " N6h a pick against a cell gone stale stores nothing and closes", function()
        picker_world(shape)
        local _, sheet_pane = gear_sheet()
        M.ModulePicker.open(machine_slots(sheet_pane)[1])
        click_module("speed-module", 0)
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "productivity-module"}} --changed elsewhere since the cell was built
        storage.computation_stack = {}
        click(confirm_button())
        H.equal(gear_modules(), "productivity-module", "stale cell refused")
        H.equal(state(), nil, "closed")
        H.equal(#storage.computation_stack, 0, "no recompute")
    end)

    H.test(shape .. " N6i a beacon slot's picker offers what beacon and machine accept and stores into its own group", function()
        picker_world(shape)
        storage[1].module_setups_by_recipe_name.gear.beacons = {
            {name = "beacon", count = 1, sharing = 1, modules = {}}, {name = "beacon", count = 1, sharing = 1, modules = {}}}
        local _, sheet_pane = gear_sheet()
        M.ModulePicker.open(beacon_slots(sheet_pane, 2)[1])
        local names = {}
        for _, button in ipairs(module_buttons()) do names[#names + 1] = button.tags.module end
        H.equal(table.concat(names, ","), "efficiency-module,speed-module", "beacon categories")
        click_module("speed-module", 0)
        click(confirm_button())
        local groups = storage[1].module_setups_by_recipe_name.gear.beacons
        H.equal(stored(groups[2].modules), "speed-module,speed-module", "group 2 filled")
        H.equal(stored(groups[1].modules), "", "group 1 untouched")
        H.equal(gear_modules(), "", "machine row untouched")
    end)

    H.test(shape .. " N6j N6k opening a second picker closes the first; a recompute closes the window", function()
        picker_world(shape)
        local _, sheet_pane = gear_sheet()
        local slots = machine_slots(sheet_pane)
        M.ModulePicker.open(slots[1])
        local first = state().frame
        M.ModulePicker.open(slots[2])
        H.equal(first.valid, false, "first window destroyed")
        H.equal(#frames(), 1, "one window")
        H.equal(state().button, slots[2], "for the second slot")
        M.Calculator.recompute_everything(1)
        H.equal(state(), nil, "state gone on recompute")
        H.equal(#frames(), 0, "window gone on recompute")
    end)

    H.test(shape .. " N6m N6n a quality double click with no module applies nothing; quality first, then module, then tick stores that quality", function()
        picker_world(shape)
        local _, sheet_pane = gear_sheet()
        M.ModulePicker.open(machine_slots(sheet_pane)[1])
        H.equal(state().selected_module, nil, "empty slot: nothing preselected")
        click_quality("rare", 0)
        click_quality("rare", 10)
        assert(state(), "still open")
        H.equal(state().selected_quality, "rare", "quality selected")
        H.equal(by_tag(quality_buttons(), "quality", "rare").toggled, true, "the double-clicked quality is shown pressed")
        H.equal(by_tag(quality_buttons(), "quality", "normal").toggled, false, "the previous quality is released")
        H.equal(gear_modules(), "", "nothing stored")
        click_module("speed-module", 100)
        H.equal(state().selected_quality, "rare", "quality kept after picking a module")
        click(confirm_button(), 200)
        H.equal(gear_modules(), "speed-module@rare,speed-module@rare,speed-module@rare,speed-module@rare", "stored at the quality chosen first")
    end)

    H.test(shape .. " N6o N6p computing an empty sheet, or deleting the picker's sheet, closes the picker", function()
        picker_world(shape)
        local _, sheet_pane = gear_sheet()
        local sheet_flow = sheet_pane.tabs[1].content
        M.ModulePicker.open(machine_slots(sheet_pane)[1])
        local row = sheet_flow.input_container.children[1]
        row.hxrrc_desired_item_button.elem_value = nil
        event_handlers.on_gui_elem_changed.hxrrc_desired_item_button({element = row.hxrrc_desired_item_button, player_index = 1})
        M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
        H.equal(state(), nil, "empty sheet computed: state gone")
        H.equal(#frames(), 0, "empty sheet computed: window gone")

        _, sheet_pane = gear_sheet()
        M.Sheet.new(sheet_pane)
        M.ModulePicker.open(machine_slots(sheet_pane.tabs[1].content)[1])
        sheet_pane.selected_tab_index = 1
        M.Sheet.delete_selected_sheet(sheet_pane)
        H.equal(state(), nil, "sheet deleted: state gone")
        H.equal(#frames(), 0, "sheet deleted: window gone")
    end)

    H.test(shape .. " N6r N4c N4d the tick with nothing selected keeps the window and changes nothing, for a hidden module, a hidden beacon module and an empty slot; clear then removes", function()
        picker_world(shape)
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "hidden-module"}}
        storage[1].module_setups_by_recipe_name.gear.beacons = {{name = "beacon", count = 1, sharing = 1, modules = {{name = "hidden-module"}}}}
        local _, sheet_pane = gear_sheet()
        for _, case in ipairs({
            {what = "hidden machine module", slot = function() return machine_slots(sheet_pane)[1] end},
            {what = "hidden beacon module", slot = function() return beacon_slots(sheet_pane, 1)[1] end},
            {what = "empty machine slot", slot = function() return machine_slots(sheet_pane)[2] end},
        }) do
            M.ModulePicker.open(case.slot())
            H.equal(state().selected_module, nil, case.what .. ": nothing preselected")
            for _, button in ipairs(module_buttons()) do
                assert(button.tags.module ~= "hidden-module", case.what .. ": hidden module not offered")
            end
            storage.computation_stack = {}
            local before = M.ModulePicker and state()
            click(confirm_button(), 50)
            H.equal(state(), before, case.what .. ": window and state kept")
            H.equal(#storage.computation_stack, 0, case.what .. ": no recompute")
            H.equal(gear_modules(), "hidden-module", case.what .. ": machine module kept")
            H.equal(stored(storage[1].module_setups_by_recipe_name.gear.beacons[1].modules), "hidden-module", case.what .. ": beacon module kept")
            M.ModulePicker.close(1, false)
        end
        H.near(M.Utils.recipe_effects(1, "gear").speed, 0.5 + 0.5 * 1.5, "hidden modules still count")

        M.ModulePicker.open(machine_slots(sheet_pane)[1])
        click(clear_button())
        H.equal(gear_modules(), "", "clear removes the hidden machine module")
        _, sheet_pane = gear_sheet()
        M.ModulePicker.open(beacon_slots(sheet_pane, 1)[1])
        click(clear_button())
        H.equal(stored(storage[1].module_setups_by_recipe_name.gear.beacons[1].modules), "", "clear removes the hidden beacon module")
        H.equal(#storage[1].module_setups_by_recipe_name.gear.beacons, 1, "the group stays")
        H.near(M.Utils.recipe_effects(1, "gear").speed, 0, "effects gone")
    end)
end

H.test("every literal hxrrc locale key the GUI and control code use exists in every language", function()
    local keys = {}
    for _, file in ipairs({"gui/calculator.lua", "gui/sheet.lua", "gui/report.lua", "gui/modulegui.lua", "gui/input_container.lua", "gui/module_picker.lua",
        "control.lua", "data.lua"}) do
        local source = io.open(file):read("*a")
        for key in source:gmatch('"hxrrc%.([%w_]+)"') do keys[key] = true end
    end
    H.equal(keys.module_picker_title, true, "scan finds the picker keys")
    for _, language in ipairs({"en", "cs", "ro"}) do
        local locale = "\n" .. io.open("locale/" .. language .. "/locale.cfg"):read("*a")
        for key, _ in pairs(keys) do
            if not locale:find("\n" .. key .. "=", 1, true) then error(language .. " locale lacks " .. key) end
        end
    end
end)

H.done("test_module_picker")
