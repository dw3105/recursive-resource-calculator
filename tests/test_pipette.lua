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

--N10: the pipette key over a machine button copies the machine and its whole setup

local function machine_button(sheet_flow, recipe_name)
    return find_all(sheet_flow, function(element) return element.name == "hxrrc_choose_crafting_machine_button" and element.tags.recipe_name == recipe_name end)[1]
end

local function clipboard() return storage[1].pipette end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N10a N10b N10c Q over a row's machine remembers the machine, its modules and beacon groups, and holds the placing item at its quality", function()
        local world = pipette_world(shape)
        world.set_placing_items("assembler", {{name = "raw", count = 1}}) --an item named unlike the entity
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler", quality = "rare"}
        storage[1].module_setups_by_recipe_name.gear = {modules = {{name = "speed-module"}, {name = "efficiency-module", quality = "uncommon"}},
            beacons = {{name = "beacon", count = 4, sharing = 2, modules = {{name = "speed-module"}}}}}
        local sheet_flow = sheet({{item = "gear"}})
        world.advance_tick(5)
        press(world, machine_button(sheet_flow, "gear"))
        local copied = clipboard()
        assert(copied, "remembered")
        H.equal(copied.kind, "machine", "kind")
        H.deep_equal(copied.machine, {name = "assembler", quality = "rare"}, "machine and quality")
        H.equal(stored(copied.setup.modules), "speed-module,efficiency-module@uncommon", "modules")
        H.equal(#copied.setup.beacons, 1, "beacon group")
        H.equal(copied.setup.beacons[1].count, 4, "beacon count")
        H.equal(copied.setup.beacons[1].sharing, 2, "beacon sharing")
        H.equal(stored(copied.setup.beacons[1].modules), "speed-module", "beacon modules")
        H.deep_equal(copied.item, {name = "raw", quality = "rare"}, "placing item, not the entity name")
        H.deep_equal(hand(), {name = "raw", quality = "rare", ghost = true}, "held as a ghost at the machine's quality")
        H.equal(copied.copied_tick, 5, "copy tick")
        H.equal(copied.own_notifications, 1, "one notification forgiven")
    end)

    H.test(shape .. " N10d a machine without placing items, or with an empty list, is refused with a flying text", function()
        for _, items in ipairs({false, {}}) do
            local world = pipette_world(shape)
            world.set_placing_items("assembler", items or nil)
            storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler"}
            local sheet_flow = sheet({{item = "gear"}})
            press(world, machine_button(sheet_flow, "gear"))
            H.equal(clipboard(), nil, "nothing remembered")
            H.equal(hand(), nil, "hand empty")
            H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.machine_has_no_item_error", "says why")
        end
    end)

    H.test(shape .. " N10e editing the row after the copy leaves the remembered setup as it was", function()
        local world = pipette_world(shape)
        storage[1].module_setups_by_recipe_name.gear = {modules = {{name = "speed-module"}},
            beacons = {{name = "beacon", count = 1, sharing = 1, modules = {{name = "speed-module"}}}}}
        local sheet_flow = sheet({{item = "gear"}})
        press(world, machine_button(sheet_flow, "gear"))
        local live = storage[1].module_setups_by_recipe_name.gear
        live.modules[1].name = "efficiency-module"
        live.modules[2] = {name = "productivity-module"}
        live.beacons[1].count = 9
        live.beacons[1].modules[1].quality = "rare"
        H.equal(stored(clipboard().setup.modules), "speed-module", "modules untouched")
        H.equal(clipboard().setup.beacons[1].count, 1, "beacon count untouched")
        H.equal(stored(clipboard().setup.beacons[1].modules), "speed-module", "beacon modules untouched")
    end)

    H.test(shape .. " N10f N10g Q over a loop stage's machine copies that stage; a tier the loop no longer crafts copies nothing", function()
        if shape ~= "2.0" then return end --quality loops are calculated on Factorio 2.0 only
        local world = pipette_world(shape)
        local key = M.QualityId.encode("X", "uncommon")
        local sheet_flow = sheet({{item = "X", quality = "uncommon"}})
        local loop = storage[1].quality_loops_by_key[key]
        loop.crafts.normal.machine = {name = "assembler"} --fast-assembler refuses quality modules
        loop.crafts.normal.setup.modules = {{name = "q"}, {name = "q"}}
        sheet_flow = sheet({{item = "X", quality = "uncommon"}})
        local rows = H.parse_report(sheet_flow.output_flow).loops[key]
        press(world, rows.tiers[1].craft.machine_button)
        assert(clipboard(), "stage copied")
        H.deep_equal(clipboard().machine, {name = rows.tiers[1].craft.machine.name, quality = rows.tiers[1].craft.machine.quality}, "the stage's machine")
        H.equal(stored(clipboard().setup.modules), "q,q", "stage modules")
        game.players[1].clear_cursor()
        storage[1].pipette = nil
        storage[1].quality_loops_by_key[key].start_quality = "uncommon" --the normal tier is no longer crafted
        press(world, rows.tiers[1].craft.machine_button)
        H.equal(clipboard(), nil, "tier outside the loop copies nothing")
        H.equal(hand(), nil, "hand empty")
    end)

    H.test(shape .. " N10h N10i a row whose stored machine, quality or setup changed underneath a valid button copies nothing", function()
        local world = pipette_world(shape)
        local chosen = storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name
        chosen.gear = {name = "assembler"}
        local sheet_flow = sheet({{item = "gear"}})
        local button = machine_button(sheet_flow, "gear")
        chosen.gear = {name = "fast-assembler"}
        press(world, button)
        H.equal(clipboard(), nil, "machine changed")
        chosen.gear = {name = "assembler", quality = "uncommon"}
        press(world, button)
        H.equal(clipboard(), nil, "quality changed")
        chosen.gear = {name = "assembler"}
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}}
        press(world, button)
        H.equal(clipboard(), nil, "setup changed")
        storage[1].module_setups_by_recipe_name.gear.modules = {}
        world.hold_item(1, "raw")
        press(world, button)
        H.equal(clipboard(), nil, "a full hand copies nothing")
        world.empty_hand(1)
        press(world, button)
        assert(clipboard(), "copies again once storage matches the button and the hand is empty")
    end)
end

--N11: a module in the hand pastes into the slot under the cursor

local function gear_modules() return stored(storage[1].module_setups_by_recipe_name.gear.modules) end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N11a N11b N11h a module ghost pastes into the slot under the cursor, fills an empty row, and queues a recompute", function()
        local world = pipette_world(shape)
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler"}
        local sheet_flow = sheet({{item = "gear"}})
        world.hold_ghost(1, "speed-module", "uncommon")
        press(world, slots(sheet_flow, "gear")[2])
        H.equal(gear_modules(), "speed-module@uncommon,speed-module@uncommon,speed-module@uncommon,speed-module@uncommon", "empty row filled")
        assert(#storage.computation_stack > 0, "recompute queued")
        H.deep_equal(hand(), {name = "speed-module", quality = "uncommon", ghost = true}, "the ghost stays in the hand for the next paste")
        sheet_flow = sheet({{item = "gear"}})
        world.hold_ghost(1, "efficiency-module")
        press(world, slots(sheet_flow, "gear")[3])
        H.equal(gear_modules(), "speed-module@uncommon,speed-module@uncommon,efficiency-module,speed-module@uncommon", "a filled slot is replaced")
    end)

    H.test(shape .. " N11c N11d a module the slot refuses is refused with a flying text; a beacon slot checks the beacon and the machine", function()
        local world = pipette_world(shape)
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "fast-assembler"}
        storage[1].module_setups_by_recipe_name.gear.beacons = {{name = "beacon", count = 1, sharing = 1, modules = {}}}
        local sheet_flow = sheet({{item = "gear"}})
        world.hold_ghost(1, "productivity-module")
        press(world, slots(sheet_flow, "gear")[1])
        H.equal(gear_modules(), "", "the fast assembler refuses productivity")
        H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.module_does_not_fit_error", "says why")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        local texts = #world.flying_texts
        world.hold_ghost(1, "raw")
        press(world, slots(sheet_flow, "gear")[1])
        H.equal(#world.flying_texts, texts, "a held item that is not a module is ignored, without a refusal text")
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler"} --takes quality modules
        sheet_flow = sheet({{item = "gear"}})
        world.hold_ghost(1, "q")
        texts = #world.flying_texts
        storage.computation_stack = {}
        press(world, beacon_slots(sheet_flow, "gear", 1)[1])
        H.equal(#storage[1].module_setups_by_recipe_name.gear.beacons[1].modules, 0, "the beacon refuses quality modules though the machine takes them")
        H.equal(#world.flying_texts, texts + 1, "refused with a text, not dropped silently by sanitizing")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler"}
        storage[1].module_setups_by_recipe_name.gear.beacons = {{name = "beacon", count = 1, sharing = 1, modules = {}}}
        world.add_beacon({name = "open-beacon", module_slots = 2})
        require("logic.indexer").run()
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "fast-assembler"}
        storage[1].module_setups_by_recipe_name.gear = {modules = {}, beacons = {{name = "open-beacon", count = 1, sharing = 1, modules = {}}}}
        sheet_flow = sheet({{item = "gear"}})
        local before = #world.flying_texts
        world.hold_ghost(1, "productivity-module")
        press(world, beacon_slots(sheet_flow, "gear", 1)[1])
        H.equal(#storage[1].module_setups_by_recipe_name.gear.beacons[1].modules, 0, "a beacon that takes productivity still checks the machine")
        H.equal(#world.flying_texts, before + 1, "and says why")
    end)

    H.test(shape .. " N11e N11f a stale cell changes nothing; a quality a mod removed pastes as normal", function()
        local world = pipette_world(shape)
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler"}
        local sheet_flow = sheet({{item = "gear"}})
        local slot = slots(sheet_flow, "gear")[1]
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "efficiency-module"}}
        world.hold_ghost(1, "speed-module")
        press(world, slot)
        H.equal(gear_modules(), "efficiency-module", "stale cell unchanged")
        H.equal(#storage.computation_stack, 0, "nothing queued")
        storage[1].module_setups_by_recipe_name.gear.modules = {}
        sheet_flow = sheet({{item = "gear"}})
        world.hold_ghost(1, "speed-module", "rare")
        world.remove_quality("rare")
        press(world, slots(sheet_flow, "gear")[1])
        H.equal(gear_modules(), "speed-module,speed-module,speed-module,speed-module", "pasted at normal")
    end)

    H.test(shape .. " N11g N11i a real rare or legendary module stack pastes with its quality and effects, and wins over a leftover ghost", function()
        local world = pipette_world(shape)
        world.set_quality_chain({{name = "normal", level = 0}, {name = "rare", level = 2}, {name = "legendary", level = 5}})
        world.add_module("speed-module", "speed", {speed = 0.2}, {rare = {speed = 0.32}, legendary = {speed = 0.5}})
        require("logic.indexer").run()
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler"}
        for _, case in ipairs({{"rare", 0.32}, {"legendary", 0.5}}) do
            storage[1].module_setups_by_recipe_name.gear.modules = {}
            local sheet_flow = sheet({{item = "gear"}})
            world.empty_hand(1)
            world.hold_ghost(1, "efficiency-module")
            world.hold_item(1, "speed-module", case[1], 10)
            press(world, slots(sheet_flow, "gear")[1])
            H.equal(gear_modules(), ("speed-module@" .. case[1] .. ","):rep(4):sub(1, -2), case[1] .. " stack pasted with its quality over the ghost")
            H.near(M.Utils.recipe_effects(1, "gear").speed, 4 * case[2], case[1] .. " effects")
        end
    end)
end

H.done("test_pipette")
