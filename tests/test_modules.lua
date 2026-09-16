--Module slots per machine: slot count, which modules fit, storing picks, machine changes, module quality, and the stale-report signature
local H = require "tests.harness"

--Gear on one machine; machine_spec and recipe_spec fields override the defaults
local function module_world(shape, machine_spec, recipe_spec)
    local world = H.new_world(shape)
    require "gui.calculator" --registers the event handlers the tests fire
    world.add_item("raw")
    world.add_item("gear")
    world.add_module("speed-module", "speed", {speed = 0.2, consumption = 0.5, quality = -0.1})
    world.add_module("speed-module-3", "speed", {speed = 0.5, consumption = 0.7, quality = -0.25}, {legendary = {speed = 1.25, consumption = 0.7, quality = -0.25}})
    world.add_module("productivity-module", "productivity", {productivity = 0.1, consumption = 0.4, pollution = 0.05, speed = -0.05})
    world.add_module("efficiency-module", "efficiency", {consumption = -0.3})
    world.add_module("quality-module", "quality", {quality = 0.1, speed = -0.05})
    local machine = {name = "assembler", categories = {"crafting"}, speed = 1}
    for key, value in pairs(machine_spec or {}) do machine[key] = value end
    world.add_machine(machine)
    local recipe = {name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}}
    for key, value in pairs(recipe_spec or {}) do recipe[key] = value end
    world.add_recipe(recipe)
    world.add_player(1)
    world.init()
    return world
end

local function find_all(element, name, found)
    found = found or {}
    if element.name == name then found[#found + 1] = element end
    for _, child in ipairs(element.children) do find_all(child, name, found) end
    return found
end

--Computes a gear sheet and makes it the player's sheet pane, so accepted changes can queue recomputations
local function gear_sheet(rate)
    local report, sheet_pane = H.run_sheet({{item = "gear", rate = rate or 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    return report, sheet_pane
end

local function slot_buttons(sheet_pane)
    return find_all(sheet_pane, "hxrrc_choose_module_button")
end

local function fire(element)
    event_handlers.on_gui_elem_changed[element.name]({element = element, player_index = 1})
end

local function pick(sheet_pane, index, value)
    H.pick_module(slot_buttons(sheet_pane)[index], value)
end

--Stored machine modules as "name@quality" in slot order
local function stored()
    local names = {}
    for _, module in ipairs(storage[1].module_setups_by_recipe_name.gear.modules) do
        names[#names + 1] = module.name .. (module.quality and ("@" .. module.quality) or "")
    end
    return table.concat(names, ",")
end

--The modules the picker window offers for a slot, sorted, the way a player sees them; the window is closed again
local function offered(button)
    local ModulePicker = require "gui.module_picker"
    assert(ModulePicker.open(button), "picker opens")
    local names = {}
    for _, element in ipairs(find_all(storage[1].module_picker.frame, "hxrrc_picker_module_button")) do names[#names + 1] = element.tags.module end
    ModulePicker.close(1, false)
    table.sort(names)
    return table.concat(names, ",")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " K1a a row shows exactly the machine's module slots", function()
        module_world(shape, {module_slots = 2})
        local _, sheet_pane = gear_sheet()
        H.equal(#slot_buttons(sheet_pane), 2, "slot buttons")
    end)

    H.test(shape .. " K1b slot count follows the chosen machine's quality, its own bonus overriding the quality's", function()
        for _, case in ipairs({
            {what = "legendary, quality bonus", spec = {module_slots = 2, quality_affects_module_slots = true}, quality = "legendary", slots = 7},
            {what = "legendary, own bonus 2", spec = {module_slots = 2, quality_affects_module_slots = true, module_slots_quality_bonus = {legendary = 2}}, quality = "legendary", slots = 4},
            {what = "legendary, own bonus 0", spec = {module_slots = 2, quality_affects_module_slots = true, module_slots_quality_bonus = {legendary = 0}}, quality = "legendary", slots = 2},
            {what = "normal", spec = {module_slots = 2, quality_affects_module_slots = true}, slots = 2},
        }) do
            module_world(shape, case.spec)
            storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler", quality = case.quality}
            local _, sheet_pane = gear_sheet()
            H.equal(#slot_buttons(sheet_pane), case.slots, case.what .. " slot buttons")
        end
    end)

    H.test(shape .. " K1c slots offer only modules both the machine and the recipe accept", function()
        module_world(shape, {allowed_module_categories = {"speed", "productivity", "efficiency"}}, {allowed_module_categories = {"speed", "efficiency", "quality"}})
        local _, sheet_pane = gear_sheet()
        H.equal(offered(slot_buttons(sheet_pane)[1]), "efficiency-module,speed-module,speed-module-3", "offered modules")
    end)

    H.test(shape .. " K1d a module is refused only for raising an effect the machine or the recipe disallows", function()
        local no_productivity = {"consumption", "speed", "pollution", "quality"}
        module_world(shape, {allowed_effects = no_productivity})
        local _, sheet_pane = gear_sheet()
        H.equal(offered(slot_buttons(sheet_pane)[1]), "efficiency-module,quality-module,speed-module,speed-module-3", "machine without productivity")

        module_world(shape, nil, {allowed_effects = no_productivity})
        _, sheet_pane = gear_sheet()
        H.equal(offered(slot_buttons(sheet_pane)[1]), "efficiency-module,quality-module,speed-module,speed-module-3", "recipe without productivity")

        module_world(shape, {allowed_effects = {"consumption", "speed", "pollution", "productivity"}})
        _, sheet_pane = gear_sheet()
        H.equal(offered(slot_buttons(sheet_pane)[1]), "efficiency-module,productivity-module,speed-module,speed-module-3",
            "machine without quality keeps modules that only lower quality")
    end)

    H.test(shape .. " K1e a machine that ignores module effects shows no slots", function()
        module_world(shape, {uses_module_effects = false})
        local _, sheet_pane = gear_sheet()
        H.equal(#slot_buttons(sheet_pane), 0, "slot buttons")
    end)

    H.test(shape .. " K2a picking into an empty row fills every slot with the module at its quality", function()
        module_world(shape)
        local _, sheet_pane = gear_sheet()
        pick(sheet_pane, 4, {name = "speed-module", quality = "rare"})
        H.equal(stored(), "speed-module@rare,speed-module@rare,speed-module@rare,speed-module@rare", "every slot filled")
        local buttons = slot_buttons(sheet_pane)
        H.equal(#buttons, 4, "rebuilt cell keeps every slot")
        for index, button in ipairs(buttons) do
            H.equal(H.slot_value(button) and H.slot_value(button).name, "speed-module", "slot " .. index .. " shows the module")
            H.equal(H.slot_value(button) and H.slot_value(button).quality, "rare", "slot " .. index .. " with its quality")
        end
        assert(#storage.computation_stack > 0, "picking recomputes")
    end)

    H.test(shape .. " K2b on a row already holding a module an empty slot appends, replacing keeps the position, emptying shifts left", function()
        module_world(shape)
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module", quality = "rare"}}
        local _, sheet_pane = gear_sheet()
        pick(sheet_pane, 4, {name = "efficiency-module"})
        H.equal(stored(), "speed-module@rare,efficiency-module", "picked into the last slot, appended after the last module")
        local buttons = slot_buttons(sheet_pane)
        H.equal(H.slot_value(buttons[2]) and H.slot_value(buttons[2]).name, "efficiency-module", "rebuilt cell shows it in the second slot")
        H.equal(H.slot_value(buttons[4]), nil, "last slot empty again")
        assert(#storage.computation_stack > 0, "picking recomputes")
        pick(sheet_pane, 1, {name = "productivity-module"})
        H.equal(stored(), "productivity-module,efficiency-module", "replaced in place")
        pick(sheet_pane, 1, nil)
        H.equal(stored(), "efficiency-module", "emptied slot shifts the rest left")
    end)

    H.test(shape .. " K3 changing machine drops modules the new machine refuses, then caps to its slots", function()
        local world = module_world(shape)
        world.add_machine({name = "limited", categories = {"crafting"}, speed = 1, module_slots = 2, allowed_effects = {"consumption", "speed", "pollution"}})
        require("logic.indexer").run()
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "productivity-module"}, {name = "speed-module"}, {name = "productivity-module"}, {name = "speed-module", quality = "rare"}}
        local _, sheet_pane = gear_sheet()
        local machine_button = find_all(sheet_pane, "hxrrc_choose_crafting_machine_button")[1]
        machine_button.elem_value = {name = "limited"}
        fire(machine_button)
        H.equal(stored(), "speed-module,speed-module@rare", "kept modules")
    end)

    H.test(shape .. " K4 legendary modules count with their quality's effects", function()
        module_world(shape)
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module-3", quality = "legendary"}, {name = "speed-module-3", quality = "legendary"}}
        local report = gear_sheet(10)
        H.near(report.rows["item/gear"].machines, 10 / 3.5, "machines at +250% speed")
        H.near(report.energy_mw, 0.21 * 10 / 3.5 * 2.4, "energy MW at +140% consumption")
    end)

    H.test(shape .. " K5 an explicit normal quality is stored as none, and a pick recomputes once when writes raise events", function()
        module_world(shape)
        local _, sheet_pane = gear_sheet()
        storage.computation_stack = {}
        H.refire_on_script_set = true
        H.pick_module(slot_buttons(sheet_pane)[1], {name = "speed-module", quality = "normal"})
        H.refire_on_script_set = false
        local module = storage[1].module_setups_by_recipe_name.gear.modules[1]
        H.equal(module and module.name, "speed-module", "stored module")
        H.equal(module and module.quality, nil, "normal quality stored as none")
        H.equal(#storage.computation_stack, 2, "one recomputation: the sheet, then centering")
    end)

    H.test(shape .. " K6 a modded module without an effects list fits, counts as no effects in slots and beacons, and crashes nothing", function()
        local world = module_world(shape)
        world.add_module("empty-module", "speed", nil) --2.1 marks module effects optional
        world.add_beacon({name = "beacon", allowed_module_categories = {"speed"}})
        require("logic.indexer").run()
        local setup = storage[1].module_setups_by_recipe_name.gear
        setup.modules = {{name = "empty-module"}}
        setup.beacons = {{name = "beacon", count = 1, sharing = 1, modules = {{name = "empty-module"}}}}

        local report, sheet_pane = gear_sheet(10)
        H.near(report.rows["item/gear"].machines, 10, "machines without effects")
        local offered_names = offered(slot_buttons(sheet_pane)[1])
        assert(offered_names:find("empty-module", 1, true), "module without effects not offered: " .. offered_names)
    end)
end

H.test("W3a signatures keep module lists, beacon groups, qualities and counts apart", function()
    H.new_world("2.0")
    local signature = require("logic.module_setup").signature
    local machine = {name = "machine"}
    local module = {name = "1", quality = "1"}
    local group = {name = "1", quality = "1", count = 1, sharing = 1, modules = {}}
    assert(signature({modules = {module, module, module, module}, beacons = {}}, machine) ~= signature({modules = {}, beacons = {group, group}}, machine),
        "four modules and two empty beacon groups share a signature")
    assert(signature({modules = {{name = "1"}}, beacons = {}}, machine) ~= signature({modules = {{name = "1", quality = "-"}}, beacons = {}}, machine),
        "no quality and quality '-' share a signature")
    local function counted(count) return {modules = {}, beacons = {{name = "b", count = count, sharing = 1, modules = {}}}} end
    assert(signature(counted(9998), machine) ~= signature(counted(9999), machine), "beacon counts 9998 and 9999 share a signature")
end)

--Reads a signature back into the setup and machine it was made from; errors on anything the format does not allow
local function decode(s)
    local position = 1
    local function tag(expected)
        assert(s:sub(position, position + #expected - 1) == expected, "expected tag " .. expected .. " at " .. position)
        position = position + #expected
    end
    local function size(delimiter)
        local last = assert(s:find(delimiter, position, true), "missing " .. delimiter .. " at " .. position)
        local token = s:sub(position, last - 1)
        assert(token:match("^%d+$"), "bad size at " .. position)
        position = last + 1
        return tonumber(token)
    end
    local function text()
        local length = size(":")
        local value = s:sub(position, position + length - 1)
        assert(#value == length, "truncated text at " .. position)
        position = position + length
        return value
    end
    local function quality()
        if s:sub(position, position) == "-" then
            position = position + 1
            return nil
        end
        return text()
    end
    local function modules()
        local list = {}
        for index = 1, size(";") do list[index] = {name = text(), quality = quality()} end
        return list
    end
    tag("M")
    local machine
    if s:sub(position, position) == "-" then
        position = position + 1
    else
        machine = {name = text(), quality = quality()}
    end
    tag("S")
    local setup = {modules = modules(), beacons = {}}
    tag("B")
    for index = 1, size(";") do
        tag("G")
        local group = {name = text(), quality = quality(), count = tonumber(text()), sharing = tonumber(text())}
        group.modules = modules()
        setup.beacons[index] = group
    end
    assert(position == #s + 1, "trailing bytes at " .. position)
    return setup, machine
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key, _ in pairs(b) do if a[key] == nil then return false end end
    return true
end

H.test("W3b every signature reads back into exactly the setup and machine it was made from", function()
    H.new_world("2.0")
    local signature = require("logic.module_setup").signature
    local function round_trip(setup, machine, what)
        local ok, decoded_setup, decoded_machine = pcall(decode, signature(setup, machine))
        assert(ok and same(decoded_setup, setup) and same(decoded_machine, machine), what .. ": " .. signature(setup, machine))
    end

    --every setup of names "1", qualities none or "1", up to 4 slot modules and up to 2 groups with count 1 or 2 and up to 1 module: 31 x 157 = 4867
    local module_lists, frontier = {{}}, {{}}
    for _ = 1, 4 do
        local next_frontier = {}
        for _, list in ipairs(frontier) do
            for _, quality in ipairs({false, "1"}) do
                local extended = {}
                for index, module in ipairs(list) do extended[index] = module end
                extended[#extended + 1] = {name = "1", quality = quality or nil}
                module_lists[#module_lists + 1] = extended
                next_frontier[#next_frontier + 1] = extended
            end
        end
        frontier = next_frontier
    end
    local groups = {}
    for _, quality in ipairs({false, "1"}) do
        for _, count in ipairs({1, 2}) do
            for _, modules in ipairs({{}, {{name = "1"}}, {{name = "1", quality = "1"}}}) do
                groups[#groups + 1] = {name = "1", quality = quality or nil, count = count, sharing = 1, modules = modules}
            end
        end
    end
    local group_lists = {{}}
    for _, first in ipairs(groups) do
        group_lists[#group_lists + 1] = {first}
        for _, second in ipairs(groups) do group_lists[#group_lists + 1] = {first, second} end
    end
    local total = 0
    for _, modules in ipairs(module_lists) do
        for _, beacons in ipairs(group_lists) do
            round_trip({modules = modules, beacons = beacons}, {name = "machine"}, "exhaustive setup")
            total = total + 1
        end
    end
    H.equal(total, 4867, "exhaustive setups")

    --random setups with names and qualities that look like the format's own tags and delimiters
    math.randomseed(20260913)
    local names = {"", "1", ":", "1:", "11", ";", "S", "B0;", "-", "G", "M1:"}
    local function random_quality() if math.random(3) == 1 then return nil end return names[math.random(#names)] end
    local function random_modules()
        local list = {}
        for index = 1, math.random(0, 4) do list[index] = {name = names[math.random(#names)], quality = random_quality()} end
        return list
    end
    for _ = 1, 2000 do
        local setup = {modules = random_modules(), beacons = {}}
        for index = 1, math.random(0, 3) do
            setup.beacons[index] = {name = names[math.random(#names)], quality = random_quality(), count = math.random(9999), sharing = math.random(9999), modules = random_modules()}
        end
        local machine = math.random(4) > 1 and {name = names[math.random(#names)], quality = random_quality()} or nil
        round_trip(setup, machine, "random setup")
    end
end)

--N4: pickers leave out hidden and parameter modules; a hidden module already stored keeps its slot and its effects

--Gear on an assembler taking only speed modules, beside a beacon taking only speed modules; speed-module is hidden, the others are not speed modules
local function hidden_world(shape)
    local world = module_world(shape, {allowed_module_categories = {"speed"}})
    world.add_module("parameter-module", "speed", {speed = 0.3})
    world.set_item_flags("parameter-module", {parameter = true})
    world.set_item_flags("speed-module-3", {hidden = true})
    world.set_item_flags("speed-module", {hidden = true})
    world.add_beacon({name = "speed-beacon", module_slots = 2, allowed_module_categories = {"speed"}})
    require("logic.indexer").run()
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N4a the offered list drops hidden and parameter modules and keeps the rest", function()
        module_world(shape)
        local ModuleSetup = require "logic.module_setup"
        local world_recipe = prototypes.recipe.gear
        local machine = prototypes.entity.assembler
        H.equal(table.concat(ModuleSetup.allowed_module_names({machine}, world_recipe), ","),
            "efficiency-module,productivity-module,quality-module,speed-module,speed-module-3", "all offered before flags")
        prototypes.item["speed-module"].hidden = true
        prototypes.item["efficiency-module"].parameter = true
        H.equal(table.concat(ModuleSetup.allowed_module_names({machine}, world_recipe), ","), "productivity-module,quality-module,speed-module-3",
            "hidden and parameter modules left out")
    end)

    H.test(shape .. " N4b N4c a hidden module stored on a machine survives sanitizing, keeps its effect and still has its slot", function()
        hidden_world(shape)
        local ModuleSetup = require "logic.module_setup"
        H.equal(#ModuleSetup.allowed_module_names({prototypes.entity.assembler}, prototypes.recipe.gear), 0, "nothing offered")
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}}
        ModuleSetup.sanitize(1, "gear")
        H.equal(stored(), "speed-module", "kept by sanitizing")
        local report, sheet_pane = gear_sheet()
        H.near(report.rows["item/gear"].machines, 1 / 1.2, "its speed still counts")
        local buttons = slot_buttons(sheet_pane)
        H.equal(#buttons, 4, "the machine's slots are shown")
        H.equal(H.slot_value(buttons[1]) and H.slot_value(buttons[1]).name, "speed-module", "the occupied slot shows the hidden module")
    end)

    H.test(shape .. " N4d a hidden module stored in a beacon group keeps that group's slots and the group itself", function()
        hidden_world(shape)
        local ModuleSetup = require "logic.module_setup"
        H.equal(#ModuleSetup.allowed_module_names({prototypes.entity["speed-beacon"], prototypes.entity.assembler}, prototypes.recipe.gear), 0, "nothing offered")
        storage[1].module_setups_by_recipe_name.gear.beacons = {{name = "speed-beacon", count = 1, sharing = 1, modules = {{name = "speed-module"}}}}
        ModuleSetup.sanitize(1, "gear")
        local _, sheet_pane = gear_sheet()
        local beacon_slots = find_all(sheet_pane, "hxrrc_choose_beacon_module_button")
        H.equal(#beacon_slots, 2, "the beacon's slots are shown")
        H.equal(H.slot_value(beacon_slots[1]) and H.slot_value(beacon_slots[1]).name, "speed-module", "occupied by the hidden module")
        H.equal(#storage[1].module_setups_by_recipe_name.gear.beacons, 1, "group kept")
    end)
end

--N5: a module picked into a row with no module fills every slot of that row; a row already holding one takes only the picked slot

local function names_of(modules)
    local names = {}
    for index, module in ipairs(modules) do names[index] = module.name .. (module.quality and ("@" .. module.quality) or "") end
    return table.concat(names, ",")
end

H.test("N5a N5b N5h N5j a pick into an empty row fills every slot from the first, at the picked quality, with separate tables", function()
    module_world("2.0")
    local ModuleSetup = require "logic.module_setup"
    local modules = {}
    H.equal(ModuleSetup.store_pick(modules, 4, {name = "speed-module", quality = "epic"}, 4), true, "changed")
    H.equal(names_of(modules), "speed-module@epic,speed-module@epic,speed-module@epic,speed-module@epic", "filled from slot 1")
    for first = 1, 4 do
        for second = first + 1, 4 do
            assert(modules[first] ~= modules[second], "slots " .. first .. " and " .. second .. " share a table")
        end
    end
    modules = {}
    ModuleSetup.store_pick(modules, 1, {name = "speed-module", quality = "normal"}, 2)
    H.equal(names_of(modules), "speed-module,speed-module", "normal stored as none, to the capacity given")
end)

H.test("N5c N5d N5e a row holding a module takes only the picked slot; replacing its only module does not refill; emptying fills nothing", function()
    module_world("2.0")
    local ModuleSetup = require "logic.module_setup"
    local modules = {{name = "speed-module"}}
    ModuleSetup.store_pick(modules, 3, {name = "efficiency-module"}, 4)
    H.equal(names_of(modules), "speed-module,efficiency-module", "appended, nothing else filled")
    modules = {{name = "speed-module"}}
    ModuleSetup.store_pick(modules, 1, {name = "efficiency-module"}, 4)
    H.equal(names_of(modules), "efficiency-module", "replaced the only module, no refill")
    modules = {{name = "speed-module"}, {name = "efficiency-module"}}
    H.equal(ModuleSetup.store_pick(modules, 1, nil, 4), true, "emptying changes")
    H.equal(names_of(modules), "efficiency-module", "shifted left, nothing filled")
end)

H.test("N5k emptying a slot that holds nothing changes nothing, in an empty row and past the last module of a partly filled one", function()
    module_world("2.0")
    local ModuleSetup = require "logic.module_setup"
    local empty = {}
    H.equal(ModuleSetup.store_pick(empty, 4, nil, 4), false, "empty row, last slot")
    H.equal(#empty, 0, "still empty")
    local partly = {{name = "speed-module"}}
    H.equal(ModuleSetup.store_pick(partly, 3, nil, 4), false, "partly filled row, empty slot")
    H.equal(names_of(partly), "speed-module", "unchanged")
end)

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N5i picking into an empty machine row through the report fills it, and machine count and effects follow", function()
        module_world(shape)
        local _, sheet_pane = gear_sheet()
        pick(sheet_pane, 2, {name = "speed-module"})
        H.equal(stored(), "speed-module,speed-module,speed-module,speed-module", "filled")
        local Utils = require "logic.utils"
        H.near(Utils.recipe_effects(1, "gear").speed, 0.8, "four speed modules")
        local report = gear_sheet()
        H.near(report.rows["item/gear"].machines, 1 / 1.8, "count follows every slot")
    end)

    H.test(shape .. " N5f N5g a pick into an empty beacon group fills that group only, to its beacon quality's slot count", function()
        local world = module_world(shape, {module_slots = 2}) --fewer machine slots than the rare beacon has, so the two capacities differ
        world.add_beacon({name = "beacon", quality_affects_module_slots = true, allowed_module_categories = {"speed"}})
        require("logic.indexer").run()
        storage[1].module_setups_by_recipe_name.gear.beacons = {
            {name = "beacon", quality = "rare", count = 1, sharing = 1, modules = {}},
            {name = "beacon", count = 1, sharing = 1, modules = {}}}
        local _, sheet_pane = gear_sheet()
        local first_group = {}
        for _, button in ipairs(find_all(sheet_pane, "hxrrc_choose_beacon_module_button")) do
            if button.tags.group == 1 then first_group[#first_group + 1] = button end
        end
        H.equal(#first_group, 4, "rare beacon: 2 slots + 2 for rare")
        H.pick_module(first_group[1], {name = "speed-module"})
        local groups = storage[1].module_setups_by_recipe_name.gear.beacons
        H.equal(names_of(groups[1].modules), "speed-module,speed-module,speed-module,speed-module", "rare group filled to 4")
        H.equal(#groups[2].modules, 0, "other group untouched")
        H.equal(#storage[1].module_setups_by_recipe_name.gear.modules, 0, "machine row untouched")
    end)
end

H.done("test_modules")
