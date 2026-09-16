--The pipette key over the calculator: copying modules and machine setups into the hand, pasting them, and how long a copied setup lives
local H = require "tests.harness"

local M = {}

--Gear and cog on a 4-slot assembler (also a 2-slot fast assembler, and a "press" that crafts only cog); a 2-slot beacon; X from A with X recycling
--into A, for loop stages. control.lua is loaded first, since it creates the handler tables the GUI modules register into.
local function pipette_world(shape)
    local world = H.new_world(shape)
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}})
    for _, item in ipairs({"raw", "gear", "cog", "A", "X"}) do world.add_item(item) end
    world.add_module("speed-module", "speed", {speed = 0.2})
    world.add_module("efficiency-module", "efficiency", {consumption = -0.3})
    world.add_module("productivity-module", "productivity", {productivity = 0.1})
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "assembler", categories = {"crafting", "pressing"}, speed = 1, module_slots = 4})
    world.add_machine({name = "fast-assembler", categories = {"crafting"}, speed = 2, module_slots = 2, allowed_module_categories = {"speed", "efficiency"}})
    world.add_machine({name = "press", categories = {"pressing"}, speed = 1, module_slots = 4})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, module_slots = 4})
    world.add_beacon({name = "beacon", module_slots = 2, allowed_module_categories = {"speed", "efficiency"}})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_recipe({name = "cog", category = "pressing", ingredients = {{name = "raw", amount = 1}}, products = {{name = "cog", amount = 1}}})
    world.add_recipe({name = "X", category = "crafting", ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-recycling", category = "recycling", energy = 0.5, hidden = true, ingredients = {{name = "X", amount = 1}},
        products = {{name = "A", amount = 1, p = 0.25}}})
    world.add_recipe({name = "A-mining", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    world.bind("item/gear", "gear")
    world.bind("item/cog", "cog")
    world.bind("item/X", "X")
    world.bind("item/A", "A-mining")
    M.Calculator = require "gui.calculator"
    M.Sheet = require "gui.sheet"
    M.Pipette = require "gui.pipette"
    M.QualityId = require "logic.quality_id"
    M.QualityLoops = require "logic.quality_loops"
    M.Utils = require "logic.utils"
    storage.computation_stack = {}
    return world
end

local function find_all(element, predicate, found)
    found = found or {}
    if predicate(element) then found[#found + 1] = element end
    for _, child in ipairs(element.children) do find_all(child, predicate, found) end
    return found
end

--Computes the player's first sheet for the targets and returns its sheet flow
local function sheet(targets)
    local sheet_flow = storage[1].sheet_section.sheet_pane.tabs[1].content
    local rows = sheet_flow.input_container.children
    for index, target in ipairs(targets) do
        local row = sheet_flow.input_container.children[index]
        row.rate_textfield.text = tostring(target.rate or 1)
        row.time_unit_dropdown.selected_index = 2
        row.hxrrc_desired_item_button.elem_value = {name = target.item, quality = target.quality}
        event_handlers.on_gui_elem_changed.hxrrc_desired_item_button({element = row.hxrrc_desired_item_button, player_index = 1})
    end
    local _ = rows
    M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
    storage.computation_stack = {}
    return sheet_flow
end

--The report cell controls of a recipe's row
local function recipe_of(element)
    local ancestor = element.parent
    while ancestor and not ancestor.tags.recipe_name do ancestor = ancestor.parent end
    return ancestor and ancestor.tags.recipe_name
end

local function slots(root, recipe_name, name)
    return find_all(root, function(element) return element.name == (name or "hxrrc_choose_module_button") and recipe_of(element) == recipe_name end)
end

local function beacon_slots(root, recipe_name, group)
    return find_all(root, function(element)
        return element.name == "hxrrc_choose_beacon_module_button" and element.tags.group == group and recipe_of(element) == recipe_name
    end)
end

local function press(world, element)
    H.press(world, "hxrrc_pipette", {element = element})
end

local function hand()
    return M.Pipette.held(game.players[1])
end

local function stored(modules)
    local names = {}
    for _, module in ipairs(modules) do names[#names + 1] = module.name .. (module.quality and ("@" .. module.quality) or "") end
    return table.concat(names, ",")
end

M.find_all, M.sheet, M.slots, M.beacon_slots, M.press, M.hand, M.stored, M.recipe_of = find_all, sheet, slots, beacon_slots, press, hand, stored, recipe_of

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N9a N9b Q with an empty hand over a filled slot puts that module, with its quality, in the hand as a ghost", function()
        local world = pipette_world(shape)
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module", quality = "rare"}, {name = "efficiency-module"}}
        local sheet_flow = sheet({{item = "gear"}})
        press(world, slots(sheet_flow, "gear")[1])
        H.deep_equal(hand(), {name = "speed-module", quality = "rare", ghost = true}, "rare speed module ghost")
        H.equal(game.players[1].cursor_stack.valid_for_read, false, "no real item created")
        game.players[1].clear_cursor()
        press(world, slots(sheet_flow, "gear")[2])
        H.deep_equal(hand(), {name = "efficiency-module", ghost = true}, "normal quality reads as none")
        H.equal(#storage.computation_stack, 0, "copying changes nothing stored")
    end)

    H.test(shape .. " N9c N9f Q over an empty slot, or over nothing, leaves the hand empty", function()
        local world = pipette_world(shape)
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}}
        local sheet_flow = sheet({{item = "gear"}})
        press(world, slots(sheet_flow, "gear")[3])
        H.equal(hand(), nil, "empty slot copies nothing")
        H.press(world, "hxrrc_pipette", {})
        H.equal(hand(), nil, "no element copies nothing")
        local label = find_all(sheet_flow, function(element) return element.type == "label" end)[1]
        press(world, label)
        H.equal(hand(), nil, "another element copies nothing")
    end)

    H.test(shape .. " N9d Q over a beacon slot copies that group's module", function()
        local world = pipette_world(shape)
        storage[1].module_setups_by_recipe_name.gear.beacons = {
            {name = "beacon", count = 1, sharing = 1, modules = {{name = "speed-module"}}},
            {name = "beacon", count = 1, sharing = 1, modules = {{name = "efficiency-module", quality = "uncommon"}}}}
        local sheet_flow = sheet({{item = "gear"}})
        press(world, beacon_slots(sheet_flow, "gear", 2)[1])
        H.deep_equal(hand(), {name = "efficiency-module", quality = "uncommon", ghost = true}, "second group's module")
    end)

    H.test(shape .. " N9e Q over a slot whose cell went stale copies nothing", function()
        local world = pipette_world(shape)
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}}
        local sheet_flow = sheet({{item = "gear"}})
        local slot = slots(sheet_flow, "gear")[1]
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "efficiency-module"}} --changed since the cell was built
        press(world, slot)
        H.equal(hand(), nil, "stale cell copies nothing")
    end)

    H.test(shape .. " N9g the hand reads a real item before a ghost, and both with quality names", function()
        local world = pipette_world(shape)
        world.hold_ghost(1, "efficiency-module", "uncommon")
        world.hold_item(1, "speed-module", "rare")
        H.deep_equal(hand(), {name = "speed-module", quality = "rare", real = true}, "real item first")
        world.hold_item(1, "speed-module")
        H.deep_equal(hand(), {name = "speed-module", real = true}, "a normal stack reads as none")
        local sheet_flow = sheet({{item = "gear"}})
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "productivity-module"}}
        sheet_flow = sheet({{item = "gear"}})
        world.empty_hand(1)
        world.hold_item(1, "speed-module")
        press(world, slots(sheet_flow, "gear")[1])
        H.deep_equal(hand(), {name = "speed-module", real = true}, "a full hand copies nothing")
        H.equal(game.players[1].cursor_ghost, nil, "no ghost written behind the real item")
    end)
end

H.done("test_pipette")
