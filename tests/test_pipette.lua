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
    world.add_recipe({name = "cog", category = "pressing", ingredients = {{name = "raw", amount = 1}}, products = {{name = "cog", amount = 1}},
        allowed_effects = {"consumption", "speed", "pollution"}}) --refuses productivity
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
    M.ModulePicker = require "gui.module_picker"
    M.Report = require "gui.report"
    M.ModuleGUI = require "gui.modulegui"
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

--P3: a left click on a slot with a module in the hand pastes it instead of opening the picker

local function slot_click(button, mouse_button)
    event_handlers.on_gui_click[button.name]({element = button, player_index = 1, tick = 0, button = mouse_button or defines.mouse_button_type.left})
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " P3a P3b P3f a click with a module ghost or a rare real stack pastes and opens no picker; a right click still clears", function()
        local world = pipette_world(shape)
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler"}
        local sheet_flow = sheet({{item = "gear"}})
        world.hold_ghost(1, "speed-module")
        slot_click(slots(sheet_flow, "gear")[3])
        H.equal(stored(storage[1].module_setups_by_recipe_name.gear.modules), "speed-module,speed-module,speed-module,speed-module", "P3a: empty row filled")
        H.equal(storage[1].module_picker, nil, "P3a: no picker")
        assert(#storage.computation_stack > 0, "P3a: recompute queued")
        world.empty_hand(1)
        world.hold_item(1, "efficiency-module", "rare", 5)
        sheet_flow = sheet({{item = "gear"}})
        slot_click(slots(sheet_flow, "gear")[2])
        H.equal(stored(storage[1].module_setups_by_recipe_name.gear.modules), "speed-module,efficiency-module@rare,speed-module,speed-module", "P3b: rare stack stored at rare")
        H.equal(storage[1].module_picker, nil, "P3b: no picker")
        sheet_flow = sheet({{item = "gear"}})
        slot_click(slots(sheet_flow, "gear")[1], defines.mouse_button_type.right)
        H.equal(stored(storage[1].module_setups_by_recipe_name.gear.modules), "efficiency-module@rare,speed-module,speed-module", "P3f: right click clears, no paste")
    end)

    H.test(shape .. " P3c P3d P3e a refused module says why and opens nothing; a non-module in the hand opens nothing; an empty hand opens the picker", function()
        local world = pipette_world(shape)
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "fast-assembler"}
        local sheet_flow = sheet({{item = "gear"}})
        world.hold_ghost(1, "productivity-module")
        slot_click(slots(sheet_flow, "gear")[1])
        H.equal(stored(storage[1].module_setups_by_recipe_name.gear.modules), "", "P3c: refused")
        H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.module_does_not_fit_error", "P3c: says why")
        H.equal(storage[1].module_picker, nil, "P3c: no picker")
        H.equal(#storage.computation_stack, 0, "P3c: nothing queued")
        world.empty_hand(1)
        world.hold_ghost(1, "assembler")
        slot_click(slots(sheet_flow, "gear")[1])
        H.equal(storage[1].module_picker, nil, "P3d: a machine ghost opens no picker")
        H.equal(stored(storage[1].module_setups_by_recipe_name.gear.modules), "", "P3d: nothing stored")
        world.empty_hand(1)
        slot_click(slots(sheet_flow, "gear")[1])
        assert(storage[1].module_picker, "P3e: an empty hand opens the picker")
    end)

    H.test(shape .. " Q1a the hand reads as names: a normal ghost gives a string name and no quality; a rare real stack gives its quality name", function()
        local world = pipette_world(shape)
        world.hold_ghost(1, "speed-module")
        local held = M.Pipette.held(game.players[1])
        H.deep_equal(held, {name = "speed-module", ghost = true}, "Q1a: normal ghost")
        H.equal(type(held.name), "string", "Q1a: ghost name is a string")
        world.empty_hand(1)
        world.hold_item(1, "efficiency-module", "rare", 3)
        held = M.Pipette.held(game.players[1])
        H.deep_equal(held, {name = "efficiency-module", quality = "rare", real = true}, "Q1a: rare stack")
        H.equal(type(held.quality), "string", "Q1a: stack quality is a string")
        world.empty_hand(1)
        world.hold_item(1, "efficiency-module", nil, 3)
        H.equal(M.Pipette.held(game.players[1]).quality, nil, "Q1a: normal stack quality is nil")
    end)
end

--N12: a machine ghost pastes the remembered setup, written one tick after the press

--Q over a button at the current tick, then on_tick at the next tick: the drain runs every request recorded before it
local function paste(world, button)
    press(world, button)
    world.advance_tick()
    world.handlers.events[defines.events.on_tick]({tick = world.tick})
end

local function chosen() return storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name end
local function setups() return storage[1].module_setups_by_recipe_name end

--A clipboard of an assembler at the quality with modules and a beacon group, copied from the gear row; returns the sheet flow of gear, cog and X
local function copied_assembler(world, quality, modules)
    chosen().gear = {name = "assembler", quality = quality}
    setups().gear = {modules = modules or {{name = "speed-module"}, {name = "efficiency-module"}},
        beacons = {{name = "beacon", count = 2, sharing = 1, modules = {{name = "speed-module"}}}}}
    chosen().cog = {name = "press"}
    chosen().X = {name = "fast-assembler"}
    local sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
    press(world, machine_button(sheet_flow, "gear"))
    world.flush_cursor_events()
    world.advance_tick()
    assert(clipboard(), "copied")
    return sheet_flow
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N12a N12c N12h a machine ghost pastes the machine at its quality and the setup onto another row, again onto a third", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world, "uncommon")
        paste(world, machine_button(sheet_flow, "cog"))
        H.deep_equal(chosen().cog, {name = "assembler", quality = "uncommon"}, "machine and quality pasted")
        H.equal(stored(setups().cog.modules), "speed-module,efficiency-module", "modules pasted")
        H.equal(#setups().cog.beacons, 1, "beacon group pasted")
        assert(#storage.computation_stack > 0, "recompute queued")
        paste(world, machine_button(sheet_flow, "X"))
        H.deep_equal(chosen().X, {name = "assembler", quality = "uncommon"}, "second paste")
        assert(clipboard(), "clipboard kept for more pastes")
    end)

    H.test(shape .. " N12b modules the target recipe refuses are left out, with a flying text", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world, nil, {{name = "productivity-module"}, {name = "speed-module"}})
        paste(world, machine_button(sheet_flow, "cog"))
        H.equal(stored(setups().cog.modules), "speed-module", "productivity left out")
        H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.pasted_setup_partly_refused", "says so")
    end)

    H.test(shape .. " N12d a machine that cannot craft the target recipe is refused with a flying text", function()
        local world = pipette_world(shape)
        chosen().cog = {name = "press"}
        chosen().gear = {name = "assembler"}
        local sheet_flow = sheet({{item = "gear"}, {item = "cog"}})
        press(world, machine_button(sheet_flow, "cog"))
        world.advance_tick()
        paste(world, machine_button(sheet_flow, "gear"))
        H.deep_equal(chosen().gear, {name = "assembler"}, "gear keeps its machine")
        H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.machine_cannot_craft_error", "says why")
    end)

    H.test(shape .. " N12e N12f a paste onto a loop stage sets that stage's machine and setup; a stale stage changes nothing", function()
        if shape ~= "2.0" then return end --quality loops are calculated on Factorio 2.0 only
        local world = pipette_world(shape)
        local key = M.QualityId.encode("X", "uncommon")
        local sheet_flow = copied_assembler(world, "rare", {{name = "q"}})
        local loop_flow = sheet({{item = "X", quality = "uncommon"}})
        local rows = H.parse_report(loop_flow.output_flow).loops[key]
        paste(world, rows.tiers[1].craft.machine_button)
        local normal = storage[1].quality_loops_by_key[key].crafts.normal
        H.deep_equal(normal.machine, {name = "assembler", quality = "rare"}, "stage machine")
        H.equal(stored(normal.setup.modules), "q", "stage modules")
        local _ = sheet_flow
        loop_flow = sheet({{item = "X", quality = "uncommon"}})
        rows = H.parse_report(loop_flow.output_flow).loops[key]
        local button = rows.tiers[2].craft.machine_button
        local before = M.QualityLoops._deep_copy(storage[1].quality_loops_by_key[key].crafts.uncommon)
        storage[1].quality_loops_by_key[key].crafts.uncommon.setup.modules = {{name = "speed-module"}}
        before.setup.modules = {{name = "speed-module"}}
        paste(world, button)
        H.deep_equal(storage[1].quality_loops_by_key[key].crafts.uncommon, before, "stale stage unchanged")
    end)

    H.test(shape .. " N12g pasted setups share no table with the clipboard or with each other", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world, nil, {{name = "speed-module"}})
        paste(world, machine_button(sheet_flow, "cog"))
        paste(world, machine_button(sheet_flow, "X"))
        local tables = {clipboard = clipboard(), cog = {machine = chosen().cog, setup = setups().cog}, X = {machine = chosen().X, setup = setups().X}}
        local seen = {}
        for owner, entry in pairs(tables) do
            local parts = {entry.machine, entry.setup, entry.setup.modules, entry.setup.beacons}
            for _, module in ipairs(entry.setup.modules) do parts[#parts + 1] = module end
            for _, group in ipairs(entry.setup.beacons) do
                parts[#parts + 1] = group
                parts[#parts + 1] = group.modules
                for _, module in ipairs(group.modules) do parts[#parts + 1] = module end
            end
            for _, part in ipairs(parts) do
                assert(not seen[part], owner .. " shares a table with " .. tostring(seen[part]))
                seen[part] = owner
            end
        end
        setups().cog.modules[1].name = "efficiency-module"
        H.equal(stored(clipboard().setup.modules), "speed-module", "clipboard unchanged by editing a pasted row")
        H.equal(stored(setups().X.modules), "speed-module", "other row unchanged")
    end)

    H.test(shape .. " N12i N12j a paste onto another sheet works; the drain writes no button, and the rebuilt report shows the pasted machine", function()
        local world = pipette_world(shape)
        copied_assembler(world, "uncommon")
        local sheet_pane = storage[1].sheet_section.sheet_pane
        M.Sheet.new(sheet_pane)
        local second = sheet_pane.tabs[2].content
        local row = second.input_container.children[1]
        row.rate_textfield.text = "1"
        row.hxrrc_desired_item_button.elem_value = {name = "cog"}
        event_handlers.on_gui_elem_changed.hxrrc_desired_item_button({element = row.hxrrc_desired_item_button, player_index = 1})
        M.Sheet.calculate(second.hxrrc_compute_button)
        storage.computation_stack = {}
        local button = machine_button(second, "cog")
        local tags_before, sprite_before = button.tags, button.sprite
        paste(world, button)
        H.deep_equal(chosen().cog, {name = "assembler", quality = "uncommon"}, "pasted from the first sheet's copy")
        H.deep_equal(button.tags, tags_before, "button tags untouched by the drain")
        H.equal(button.sprite, sprite_before, "button sprite untouched by the drain")
        M.Sheet.calculate(second.hxrrc_compute_button)
        local rebuilt = machine_button(second, "cog")
        H.equal(rebuilt.sprite, "entity/assembler", "rebuilt report shows it")
        H.equal(rebuilt.tags.quality, "uncommon", "rebuilt report shows its quality")
    end)

    H.test(shape .. " N12k N12l a real item held with the ghost refuses and drops the clipboard; a row whose machine changed underneath keeps its storage", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        local cog_button = machine_button(sheet_flow, "cog")
        chosen().cog = {name = "assembler", quality = "rare"} --changed since the button was built
        paste(world, cog_button)
        H.deep_equal(chosen().cog, {name = "assembler", quality = "rare"}, "stale row keeps the newer machine")
        world.hold_item(1, "raw")
        paste(world, machine_button(sheet_flow, "X"))
        H.deep_equal(chosen().X, {name = "fast-assembler"}, "nothing pasted with a real item held")
        H.equal(clipboard(), nil, "clipboard dropped")
    end)

    H.test(shape .. " N12n N12o N12p N12q N12r nothing is written in the pressing tick; a target gone stale meanwhile is skipped; a rebuilt report is not; pastes in consecutive ticks all land; a newer copy voids an older request", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        press(world, machine_button(sheet_flow, "cog"))
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        H.deep_equal(chosen().cog, {name = "press"}, "N12n: not in the pressing tick")
        world.advance_tick()
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        H.equal(chosen().cog.name, "assembler", "N12n: the next tick writes")

        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        press(world, machine_button(sheet_flow, "X"))
        chosen().X = {name = "assembler", quality = "rare"}
        world.advance_tick()
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        H.deep_equal(chosen().X, {name = "assembler", quality = "rare"}, "N12o: stale target skipped")

        chosen().X = {name = "fast-assembler"}
        setups().X = {modules = {}, beacons = {}}
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        press(world, machine_button(sheet_flow, "X"))
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}}) --the report is rebuilt: the pressed button is gone
        world.advance_tick()
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        H.equal(chosen().X.name, "assembler", "N12p: written from the tags snapshot")

        chosen().cog, chosen().X = {name = "press"}, {name = "fast-assembler"}
        setups().cog, setups().X = {modules = {}, beacons = {}}, {modules = {}, beacons = {}}
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        local written = 0
        for _, recipe_name in ipairs({"cog", "X"}) do
            local button = machine_button(sheet_flow, recipe_name)
            press(world, button)
            world.advance_tick()
            world.handlers.events[defines.events.on_tick]({tick = world.tick})
            if chosen()[recipe_name].name == "assembler" then written = written + 1 end
        end
        H.equal(written, 2, "N12q: consecutive pastes all land")
        H.equal(storage[1].pipette_requests, nil, "N12q: drained requests are not kept")
        assert(clipboard(), "N12q: clipboard kept")

        chosen().X = {name = "fast-assembler"}
        setups().X = {modules = {}, beacons = {}}
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        press(world, machine_button(sheet_flow, "X"))
        game.players[1].clear_cursor()
        chosen().gear = {name = "assembler"}
        press(world, machine_button(sheet_flow, "gear")) --empty hand: a new copy, new id
        world.advance_tick()
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        H.deep_equal(chosen().X, {name = "fast-assembler"}, "N12r: the older request's clipboard is gone")
    end)

    H.test(shape .. " N12s (defensive) a request whose clipboard is still there but whose hand no longer matches writes nothing", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        world.advance_tick()
        local snapshot = {machine = M.QualityLoops._deep_copy(chosen().cog), setup = M.QualityLoops._deep_copy(setups().cog)}
        press(world, machine_button(sheet_flow, "cog"))
        world.suppress_next_cursor_event(1)
        world.empty_hand(1)
        assert(clipboard(), "clipboard still there")
        world.advance_tick()
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        H.deep_equal({machine = chosen().cog, setup = setups().cog}, snapshot, "nothing written")
    end)
end

--N13: a copied machine setup lives only while its own ghost stays in the hand, untouched

local function drain(world)
    world.handlers.events[defines.events.on_tick]({tick = world.tick})
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N12m the rev-4 order: clear and reselect the same ghost, press before their notifications arrive; the destination is unchanged", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        world.advance_tick()
        local snapshot = {machine = M.QualityLoops._deep_copy(chosen().cog), setup = M.QualityLoops._deep_copy(setups().cog)}
        world.empty_hand(1)
        world.hold_ghost(1, clipboard().item.name, clipboard().item.quality)
        press(world, machine_button(sheet_flow, "cog"))
        world.flush_cursor_events()
        world.advance_tick()
        world.handlers.events[defines.events.on_tick]({tick = world.tick})
        H.deep_equal({machine = chosen().cog, setup = setups().cog}, snapshot, "destination unchanged")
        H.equal(clipboard(), nil, "clipboard gone")
    end)


    H.test(shape .. " N13a N13b N13c after its copy tick, clearing the hand, another quality of the machine, or a real item drops the clipboard", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        world.empty_hand(1)
        world.flush_cursor_events()
        H.equal(clipboard(), nil, "N13a: cleared hand")

        chosen().gear = {name = "assembler"}
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        press(world, machine_button(sheet_flow, "gear"))
        world.flush_cursor_events()
        world.advance_tick()
        local item = clipboard().item.name
        world.hold_ghost(1, item, "rare") --not flushed: only the Q-top quality comparison can see it
        local before = M.QualityLoops._deep_copy(chosen().cog)
        paste(world, machine_button(sheet_flow, "cog"))
        H.deep_equal(chosen().cog, before, "N13b: nothing pasted")
        H.equal(clipboard(), nil, "N13b: dropped by the quality comparison")

        world.empty_hand(1)
        world.flush_cursor_events()
        press(world, machine_button(sheet_flow, "gear"))
        world.flush_cursor_events()
        world.advance_tick()
        world.empty_hand(1)
        world.hold_item(1, clipboard().item.name, clipboard().item.quality) --a real item of the very machine copied
        H.press(world, "hxrrc_pipette", {}) --before any notification: only the held-ghost check can drop it
        H.equal(clipboard(), nil, "N13c: real item")
    end)

    H.test(shape .. " N13d N13e N13g a configuration change drops the clipboard and pending pastes; a removed player takes theirs; closing the calculator keeps it", function()
        local world = pipette_world(shape)
        copied_assembler(world)
        M.Calculator.toggle(game.players[1])
        M.Calculator.toggle(game.players[1])
        assert(clipboard(), "N13g: kept across closing and opening the calculator")
        storage[1].pipette_requests = {{clipboard_id = clipboard().id, tick = world.tick, target = {}}}
        world.handlers.on_configuration_changed({mod_changes = {}})
        H.equal(clipboard(), nil, "N13d: configuration change drops it")
        H.equal(storage[1].pipette_requests, nil, "N13d: and pending pastes")
        storage[1].pipette_requests = {{clipboard_id = 1, tick = world.tick, target = {}}}
        require("logic.player_data_updater").reinitialize(1)
        H.equal(storage[1].pipette_requests, nil, "N13d: reinitializing the player drops pending pastes itself")
        world.empty_hand(1)
        world.flush_cursor_events()
        copied_assembler(world)
        world.handlers.events[defines.events.on_player_removed]({player_index = 1})
        H.equal(storage[1], nil, "N13e: removed with the player")
    end)

    H.test(shape .. " N13f a machine a mod removed cannot be pasted", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        chosen().gear = {name = "fast-assembler"}
        world.remove_machine("assembler")
        world.advance_tick()
        paste(world, machine_button(sheet_flow, "cog"))
        H.deep_equal(chosen().cog, {name = "press"}, "nothing pasted")
    end)

    H.test(shape .. " N13i N13j pastes in later ticks keep the clipboard; Q over the world with a changed hand drops it without any notification", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        paste(world, machine_button(sheet_flow, "cog"))
        paste(world, machine_button(sheet_flow, "X"))
        H.equal(chosen().cog.name, "assembler", "first paste")
        H.equal(chosen().X.name, "assembler", "second paste")
        assert(clipboard(), "N13i: kept")
        world.suppress_next_cursor_event(1)
        world.empty_hand(1)
        H.press(world, "hxrrc_pipette", {})
        H.equal(clipboard(), nil, "N13j: dropped at the top of the press")
    end)

    H.test(shape .. " N13k N13l N13m flushes between writes, a suppressed own notification, and a retired allowance never paste a put-down setup", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        local item, quality = clipboard().item.name, clipboard().item.quality
        world.empty_hand(1)
        world.flush_cursor_events()
        world.hold_ghost(1, item, quality)
        world.flush_cursor_events()
        paste(world, machine_button(sheet_flow, "cog"))
        H.deep_equal(chosen().cog, {name = "press"}, "N13k: nothing pasted")

        chosen().gear = {name = "assembler"}
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        world.empty_hand(1)
        world.flush_cursor_events()
        world.advance_tick()
        world.suppress_next_cursor_event(1)
        press(world, machine_button(sheet_flow, "gear"))
        world.advance_tick()
        paste(world, machine_button(sheet_flow, "cog"))
        H.equal(chosen().cog.name, "assembler", "N13l: with no own notification the paste still works")
        world.advance_tick()
        world.empty_hand(1)
        world.hold_ghost(1, item, quality)
        world.flush_cursor_events()
        chosen().X = {name = "fast-assembler"}
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        paste(world, machine_button(sheet_flow, "X"))
        H.deep_equal(chosen().X, {name = "fast-assembler"}, "N13l: put down and picked up again: nothing pasted")

        chosen().gear = {name = "assembler"}
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        world.empty_hand(1)
        world.flush_cursor_events()
        world.suppress_next_cursor_event(1)
        press(world, machine_button(sheet_flow, "gear"))
        assert(clipboard(), "copied without an own notification")
        world.advance_tick()
        world.hold_ghost(1, item, quality) --same ghost, a later tick: one external notification
        world.flush_cursor_events()
        H.equal(clipboard(), nil, "N13m: the unused allowance expired with its tick")
    end)

    H.test(shape .. " N13n N13o merged notifications: at a later tick they drop the clipboard; in the copy's own tick they cannot be told apart (A1)", function()
        local world = pipette_world(shape)
        world.merge_cursor_events = true
        local sheet_flow = copied_assembler(world)
        local item, quality = clipboard().item.name, clipboard().item.quality
        world.empty_hand(1)
        world.hold_ghost(1, item, quality)
        world.flush_cursor_events()
        H.equal(clipboard(), nil, "N13n: later-tick merged notification drops it")

        chosen().gear = {name = "assembler"}
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        world.empty_hand(1)
        world.flush_cursor_events()
        world.advance_tick()
        press(world, machine_button(sheet_flow, "gear"))
        world.empty_hand(1)
        world.hold_ghost(1, item, quality)
        world.flush_cursor_events()
        --negative capability: the one delivery model the rule cannot handle, pinned so a change to it is noticed; G10f observes the engine
        assert(clipboard(), "N13o: copy-tick merge of copy, clear and identical reselect keeps the clipboard (documented residual A1)")
    end)

    H.test(shape .. " N13p a second notification in the copy tick, with the same ghost still in hand, drops the clipboard", function()
        local world = pipette_world(shape)
        chosen().gear = {name = "assembler"}
        local sheet_flow = sheet({{item = "gear"}})
        world.advance_tick()
        press(world, machine_button(sheet_flow, "gear"))
        local item, quality = clipboard().item.name, clipboard().item.quality
        world.hold_ghost(1, item, quality) --rewritten to the same ghost in the same tick
        world.flush_cursor_events()
        H.equal(clipboard(), nil, "only one notification is forgiven")
    end)
end

--N13b (amendment B): the pipette key copies and pastes beacon groups the same way

local function beacon_buttons(root, recipe_name)
    return find_all(root, function(element) return element.name == "hxrrc_choose_beacon_button" and recipe_of(element) == recipe_name end)
end

--gear with a group of 3 uncommon beacons shared by 2, holding a rare speed module and an efficiency module; cog and X with their own setups
local function copied_beacon_group(world)
    chosen().gear, chosen().cog, chosen().X = {name = "assembler"}, {name = "assembler"}, {name = "assembler"}
    setups().gear = {modules = {}, beacons = {{name = "beacon", quality = "uncommon", count = 3, sharing = 2,
        modules = {{name = "speed-module", quality = "rare"}, {name = "efficiency-module"}}}}}
    setups().cog = {modules = {}, beacons = {{name = "beacon", count = 1, sharing = 1, modules = {}}}}
    setups().X = {modules = {}, beacons = {}}
    local sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
    press(world, beacon_buttons(sheet_flow, "gear")[1])
    world.flush_cursor_events()
    world.advance_tick()
    return sheet_flow
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " N13q N13r Q over a beacon group copies the whole group and holds the beacon's placing item", function()
        local world = pipette_world(shape)
        world.set_placing_items("beacon", {{name = "raw", count = 1}})
        copied_beacon_group(world)
        local copied = clipboard()
        assert(copied, "copied")
        H.equal(copied.kind, "beacon", "kind")
        H.deep_equal(copied.group, {name = "beacon", quality = "uncommon", count = 3, sharing = 2,
            modules = {{name = "speed-module", quality = "rare"}, {name = "efficiency-module"}}}, "whole group")
        H.deep_equal(hand(), {name = "raw", quality = "uncommon", ghost = true}, "placing item at the beacon's quality")
        setups().gear.beacons[1].modules[1].name = "efficiency-module"
        H.equal(copied.group.modules[1].name, "speed-module", "a copy, not the live group")
    end)

    H.test(shape .. " N13s N13t a beacon ghost replaces the group under the key, or adds one at the add button, one tick later", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_beacon_group(world)
        paste(world, beacon_buttons(sheet_flow, "cog")[1])
        H.deep_equal(setups().cog.beacons, {clipboard().group}, "cog's group replaced")
        assert(setups().cog.beacons[1] ~= clipboard().group and setups().cog.beacons[1].modules ~= clipboard().group.modules, "fresh tables")
        local add = beacon_buttons(sheet_flow, "X")
        H.equal(#add, 1, "X shows only the add button")
        paste(world, add[1])
        H.equal(#setups().X.beacons, 1, "a group added")
        H.equal(setups().X.beacons[1].count, 3, "with its count")
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}}) --rebuilt: cog now shows its group and the add button
        local cog_buttons = beacon_buttons(sheet_flow, "cog")
        H.equal(#cog_buttons, 2, "group button and add button")
        paste(world, cog_buttons[2])
        H.equal(#setups().cog.beacons, 2, "added after the existing group, which stays")
    end)

    H.test(shape .. " N13u modules the target machine or recipe refuse are left out, with a flying text", function()
        local world = pipette_world(shape)
        world.add_beacon({name = "open-beacon", module_slots = 2, allowed_effects = {"consumption", "speed", "productivity", "pollution"}})
        require("logic.indexer").run()
        chosen().gear, chosen().cog = {name = "assembler"}, {name = "assembler"}
        setups().gear = {modules = {}, beacons = {{name = "open-beacon", count = 1, sharing = 1, modules = {{name = "productivity-module"}, {name = "speed-module"}}}}}
        setups().cog = {modules = {}, beacons = {}}
        local sheet_flow = sheet({{item = "gear"}, {item = "cog"}})
        press(world, beacon_buttons(sheet_flow, "gear")[1])
        world.flush_cursor_events()
        world.advance_tick()
        paste(world, beacon_buttons(sheet_flow, "cog")[1])
        H.equal(stored(setups().cog.beacons[1].modules), "speed-module", "cog refuses productivity")
        H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.pasted_setup_partly_refused", "says so")
    end)

    H.test(shape .. " N13v N13w kinds never cross; a stale group copies nothing", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_beacon_group(world)
        local before = M.QualityLoops._deep_copy(chosen().cog)
        paste(world, machine_button(sheet_flow, "cog"))
        H.deep_equal(chosen().cog, before, "a beacon ghost over a machine button pastes nothing")
        H.equal(storage[1].pipette_requests, nil, "no request")
        world.empty_hand(1)
        world.flush_cursor_events()
        press(world, machine_button(sheet_flow, "gear"))
        world.flush_cursor_events()
        world.advance_tick()
        local groups = M.QualityLoops._deep_copy(setups().cog.beacons)
        paste(world, beacon_buttons(sheet_flow, "cog")[1])
        H.deep_equal(setups().cog.beacons, groups, "a machine ghost over a beacon button pastes nothing")

        world.empty_hand(1)
        world.flush_cursor_events()
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}, {item = "X"}})
        local button = beacon_buttons(sheet_flow, "gear")[1]
        setups().gear.beacons[1].name = "beacon"
        setups().gear.beacons[1].quality = nil --the group changed since the button was built
        press(world, button)
        H.equal(clipboard(), nil, "stale group copies nothing")
    end)

    H.test(shape .. " N13x the rev-4 order with a beacon clipboard: clear and reselect, press before the notifications; the destination is unchanged", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_beacon_group(world)
        drain(world)
        world.advance_tick()
        local snapshot = M.QualityLoops._deep_copy(setups().cog.beacons)
        local item, quality = clipboard().item.name, clipboard().item.quality
        world.empty_hand(1)
        world.hold_ghost(1, item, quality)
        press(world, beacon_buttons(sheet_flow, "cog")[1])
        world.flush_cursor_events()
        world.advance_tick()
        drain(world)
        H.deep_equal(setups().cog.beacons, snapshot, "destination unchanged")
        H.equal(clipboard(), nil, "clipboard gone")
    end)
end

--P5: machine buttons are sprite-buttons that open the machine picker, so the pipette key reaches the mod over them

local function left_click(button, tick)
    event_handlers.on_gui_click[button.name]({element = button, player_index = 1, tick = tick or 0, button = defines.mouse_button_type.left})
end

local function picker() return storage[1].module_picker end

local function offered_choices()
    local names = {}
    for _, flow in ipairs(picker().frame.picker_scroll.picker_grid.children) do names[#names + 1] = flow.children[1].tags.choice end
    table.sort(names)
    return table.concat(names, ",")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " P5a P5b a row's machine is a sprite-button; a left click opens the machine picker offering the machines that craft the recipe, preselected", function()
        pipette_world(shape)
        chosen().gear = {name = "assembler", quality = "rare"}
        local sheet_flow = sheet({{item = "gear"}})
        local button = machine_button(sheet_flow, "gear")
        H.equal(button.type, "sprite-button", "P5a: sprite-button")
        H.equal(button.sprite, "entity/assembler", "P5a: machine sprite")
        H.equal(button.quality.name, "rare", "P5a: machine quality")
        H.equal(button.tags.name, "assembler", "P5a: tags name")
        assert(button.tags.signature, "P5a: tags signature")
        H.equal(button.tooltip[4][1], "hxrrc.choose_machine_button_tooltip_2", "P5a: tooltip says what a click does")
        left_click(button)
        H.equal(picker().kind, "machine", "P5b: machine picker")
        H.equal(picker().frame.caption[1], "hxrrc.machine_picker_title", "P5b: title")
        H.equal(offered_choices(), "assembler,fast-assembler", "P5b: only machines crafting gear")
        H.equal(picker().selected_choice, "assembler", "P5b: stored machine preselected")
        H.equal(picker().selected_quality, "rare", "P5b: stored quality preselected")
        H.equal(#find_all(picker().frame, function(element) return element.name == "hxrrc_picker_clear_button" end), 0, "P5b: a machine cannot be emptied")
    end)

    H.test(shape .. " P5c P5d a picked machine is stored with its setup fitted; a machine that cannot craft is never offered nor stored", function()
        pipette_world(shape)
        chosen().gear = {name = "assembler"}
        setups().gear = {modules = {{name = "productivity-module"}, {name = "speed-module"}, {name = "speed-module"}}, beacons = {}}
        local sheet_flow = sheet({{item = "gear"}})
        H.pick_choice(machine_button(sheet_flow, "gear"), {name = "fast-assembler", quality = "rare"})
        H.deep_equal(chosen().gear, {name = "fast-assembler", quality = "rare"}, "P5c: machine and quality stored")
        H.equal(stored(setups().gear.modules), "speed-module,speed-module", "P5c: refused productivity dropped")
        assert(#storage.computation_stack > 0, "P5c: recompute queued")
        sheet_flow = sheet({{item = "gear"}})
        H.equal(M.Report.pick_machine(machine_button(sheet_flow, "gear"), {name = "press"}), false, "P5d: press cannot craft gear")
        H.equal(chosen().gear.name, "fast-assembler", "P5d: nothing stored")
    end)

    H.test(shape .. " P5e a loop stage's machine button picks that stage's machine", function()
        if shape ~= "2.0" then return end --quality loops are calculated on Factorio 2.0 only
        pipette_world(shape)
        local key = M.QualityId.encode("X", "uncommon")
        local sheet_flow = sheet({{item = "X", quality = "uncommon"}})
        local rows = H.parse_report(sheet_flow.output_flow).loops[key]
        local button = rows.tiers[1].craft.machine_button
        H.equal(button.type, "sprite-button", "stage button is a sprite-button")
        H.pick_choice(button, {name = "assembler", quality = "uncommon"})
        H.deep_equal(storage[1].quality_loops_by_key[key].crafts.normal.machine, {name = "assembler", quality = "uncommon"}, "stage machine stored")
    end)

    H.test(shape .. " P5f P5g P5h a stale row opens no picker and a picker gone stale stores nothing; double click and Enter apply; a right click does nothing", function()
        local world = pipette_world(shape)
        chosen().gear = {name = "assembler"}
        local sheet_flow = sheet({{item = "gear"}})
        local button = machine_button(sheet_flow, "gear")
        left_click(button)
        chosen().gear = {name = "assembler", quality = "uncommon"} --changed while the picker is open
        event_handlers.on_gui_click.hxrrc_picker_confirm_button({element = picker().frame.picker_footer.hxrrc_picker_confirm_button, player_index = 1, tick = 0})
        H.deep_equal(chosen().gear, {name = "assembler", quality = "uncommon"}, "P5f: a picker gone stale stores nothing")
        left_click(button)
        H.equal(picker(), nil, "P5f: a stale button opens no picker")

        sheet_flow = sheet({{item = "gear"}})
        button = machine_button(sheet_flow, "gear")
        event_handlers.on_gui_click[button.name]({element = button, player_index = 1, tick = 0, button = defines.mouse_button_type.right})
        H.equal(picker(), nil, "P5h: right click opens nothing")
        H.deep_equal(chosen().gear, {name = "assembler", quality = "uncommon"}, "P5h: right click stores nothing")
        left_click(button)
        local choice = function(name)
            for _, flow in ipairs(picker().frame.picker_scroll.picker_grid.children) do
                if flow.children[1].tags.choice == name then return flow.children[1] end
            end
        end
        left_click(choice("fast-assembler"), 1000)
        left_click(choice("fast-assembler"), 1010)
        H.equal(chosen().gear.name, "fast-assembler", "P5g: double click applies")
        H.equal(picker(), nil, "P5g: and closes")

        sheet_flow = sheet({{item = "gear"}})
        left_click(machine_button(sheet_flow, "gear"))
        left_click(choice("assembler"), 2000)
        H.press(world, "hxrrc_confirm_module_picker", {})
        H.equal(chosen().gear.name, "assembler", "P5g: Enter applies")
    end)

    H.test(shape .. " P5j P5k Q copies a machine through its sprite-button; a machine picked at normal is stored as none and its copy survives to paste", function()
        local world = pipette_world(shape)
        chosen().gear = {name = "assembler", quality = "rare"}
        chosen().cog = {name = "press"}
        local sheet_flow = sheet({{item = "gear"}, {item = "cog"}})
        H.pick_choice(machine_button(sheet_flow, "gear"), {name = "assembler", quality = "normal"})
        H.deep_equal(chosen().gear, {name = "assembler"}, "P5k: normal stored as none")
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}})
        press(world, machine_button(sheet_flow, "gear"))
        world.flush_cursor_events()
        assert(clipboard(), "P5j: Q over the sprite-button copies; P5k: the copy survives its own notification")
        world.advance_tick()
        paste(world, machine_button(sheet_flow, "cog"))
        world.flush_cursor_events()
        H.deep_equal(chosen().cog, {name = "assembler"}, "P5k: pasted")
        assert(clipboard(), "P5k: clipboard kept")
    end)

    H.test(shape .. " P5l a loop stage machine picked at normal after rare is stored as none, and its Q copy pastes", function()
        if shape ~= "2.0" then return end --quality loops are calculated on Factorio 2.0 only
        local world = pipette_world(shape)
        local key = M.QualityId.encode("X", "uncommon")
        chosen().gear = {name = "fast-assembler"}
        local sheet_flow = sheet({{item = "X", quality = "uncommon"}, {item = "gear"}})
        storage[1].quality_loops_by_key[key].crafts.normal.machine = {name = "assembler", quality = "rare"}
        sheet_flow = sheet({{item = "X", quality = "uncommon"}, {item = "gear"}})
        H.pick_choice(H.parse_report(sheet_flow.output_flow).loops[key].tiers[1].craft.machine_button, {name = "assembler"})
        H.deep_equal(storage[1].quality_loops_by_key[key].crafts.normal.machine, {name = "assembler"}, "normal stored as none")
        sheet_flow = sheet({{item = "X", quality = "uncommon"}, {item = "gear"}})
        press(world, H.parse_report(sheet_flow.output_flow).loops[key].tiers[1].craft.machine_button)
        world.flush_cursor_events()
        assert(clipboard(), "copy survives its own notification")
        world.advance_tick()
        paste(world, machine_button(sheet_flow, "gear"))
        H.equal(chosen().gear.name, "assembler", "pasted onto the row")
        H.equal(chosen().gear.quality, nil, "at normal")
    end)

    H.test(shape .. " P5m a hidden crafting machine is not offered", function()
        local world = pipette_world(shape)
        world.set_entity_flags("fast-assembler", {hidden = true})
        chosen().gear = {name = "assembler"}
        local sheet_flow = sheet({{item = "gear"}})
        left_click(machine_button(sheet_flow, "gear"))
        H.equal(offered_choices(), "assembler", "hidden machine left out")
    end)
end

--P6: beacon buttons are sprite-buttons that open the beacon picker, so the pipette key reaches them too

local function groups(recipe_name)
    local out = {}
    for _, group in ipairs(setups()[recipe_name].beacons) do
        local names = {}
        for _, module in ipairs(group.modules) do names[#names + 1] = module.name .. (module.quality and ("@" .. module.quality) or "") end
        out[#out + 1] = group.name .. (group.quality and ("@" .. group.quality) or "") .. " x" .. group.count .. " /" .. group.sharing .. " [" .. table.concat(names, ",") .. "]"
    end
    return table.concat(out, "; ")
end

local function beacon_world(shape)
    local world = pipette_world(shape)
    world.add_beacon({name = "wide-beacon", module_slots = 2, allowed_module_categories = {"speed"}})
    require("logic.indexer").run()
    chosen().gear, chosen().cog = {name = "assembler"}, {name = "assembler"}
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " P6a P6b P6c group and add buttons are sprite-buttons; the add button appends a group; a group button replaces its beacon, keeping numbers and fitting modules", function()
        beacon_world(shape)
        setups().gear = {modules = {}, beacons = {}}
        local sheet_flow = sheet({{item = "gear"}})
        local add = beacon_buttons(sheet_flow, "gear")[1]
        H.equal(add.type, "sprite-button", "P6a: add button is a sprite-button")
        H.equal(add.sprite, nil, "P6a: add button has no sprite")
        H.equal(add.tooltip[1], "hxrrc.add_beacon_button_tooltip", "P6a: add button tooltip")
        left_click(add)
        H.equal(picker().kind, "beacon", "P6b: beacon picker")
        H.equal(offered_choices(), "beacon,wide-beacon", "P6b: beacons offered")
        H.equal(#find_all(picker().frame, function(element) return element.name == "hxrrc_picker_clear_button" end), 0, "P6b: the add button offers no clear")
        M.ModulePicker.close(1, false)
        H.pick_choice(add, {name = "beacon", quality = "uncommon"})
        H.equal(groups("gear"), "beacon@uncommon x1 /1 []", "P6b: group appended at count 1, sharing 1")
        assert(#storage.computation_stack > 0, "P6b: recompute queued")

        setups().gear.beacons[1] = {name = "beacon", quality = "uncommon", count = 4, sharing = 2, modules = {{name = "speed-module"}, {name = "efficiency-module"}}}
        sheet_flow = sheet({{item = "gear"}})
        local group_button = beacon_buttons(sheet_flow, "gear")[1]
        H.equal(group_button.sprite, "entity/beacon", "P6a: group button shows its beacon")
        H.equal(group_button.quality.name, "uncommon", "P6a: and its quality")
        H.equal(group_button.tooltip[4][1], "hxrrc.choose_beacon_button_tooltip_2", "P6a: group button tooltip")
        H.pick_choice(group_button, {name = "wide-beacon", quality = "rare"})
        H.equal(groups("gear"), "wide-beacon@rare x4 /2 [speed-module]", "P6c: beacon replaced; numbers kept; refused module dropped")
    end)

    H.test(shape .. " P6d P6e P6f the trash button and a right click remove a group; a right click on the add button does nothing; a stale button stores nothing", function()
        beacon_world(shape)
        setups().gear = {modules = {}, beacons = {{name = "beacon", count = 2, sharing = 1, modules = {}}, {name = "wide-beacon", count = 1, sharing = 1, modules = {}}}}
        local sheet_flow = sheet({{item = "gear"}})
        left_click(beacon_buttons(sheet_flow, "gear")[1])
        local clear = picker().frame.picker_footer.hxrrc_picker_clear_button
        H.equal(clear.sprite, "utility/trash", "P6d: trash icon")
        event_handlers.on_gui_click[clear.name]({element = clear, player_index = 1, tick = 0, button = defines.mouse_button_type.left})
        H.equal(groups("gear"), "wide-beacon x1 /1 []", "P6d: first group removed")
        H.equal(picker(), nil, "P6d: picker closed")

        sheet_flow = sheet({{item = "gear"}})
        local buttons = beacon_buttons(sheet_flow, "gear")
        H.equal(#buttons, 2, "group and add buttons")
        storage.computation_stack = {}
        H.pick_choice(buttons[2], nil)
        H.equal(groups("gear"), "wide-beacon x1 /1 []", "P6e: right click on the add button removes nothing")
        H.equal(#storage.computation_stack, 0, "P6e: nothing queued")
        H.equal(M.ModuleGUI.pick_beacon(buttons[2], nil), false, "P6e: emptying the add button itself stores nothing")
        H.equal(groups("gear"), "wide-beacon x1 /1 []", "P6e: groups unchanged")
        H.pick_choice(buttons[1], nil)
        H.equal(groups("gear"), "", "P6e: right click removes the group")

        sheet_flow = sheet({{item = "gear"}})
        local stale = beacon_buttons(sheet_flow, "gear")[1] --the add button, before storage changes under it
        setups().gear.beacons = {{name = "beacon", count = 1, sharing = 1, modules = {}}}
        H.equal(H.pick_choice(stale, {name = "wide-beacon"}), false, "P6f: a stale add button opens no picker")
        H.equal(M.ModuleGUI.pick_beacon(stale, {name = "wide-beacon"}), false, "P6f: and stores nothing")
        H.equal(groups("gear"), "beacon x1 /1 []", "P6f: storage unchanged")
    end)

    H.test(shape .. " P6h P6j a beacon picked at normal after rare is stored as none; Q copies the group through its sprite-button and pastes it at another row's add button", function()
        local world = beacon_world(shape)
        setups().gear = {modules = {}, beacons = {{name = "beacon", quality = "rare", count = 3, sharing = 1, modules = {{name = "speed-module"}}}}}
        setups().cog = {modules = {}, beacons = {}}
        local sheet_flow = sheet({{item = "gear"}, {item = "cog"}})
        H.pick_choice(beacon_buttons(sheet_flow, "gear")[1], {name = "beacon", quality = "normal"})
        H.equal(setups().gear.beacons[1].quality, nil, "P6j: normal stored as none")
        sheet_flow = sheet({{item = "gear"}, {item = "cog"}})
        press(world, beacon_buttons(sheet_flow, "gear")[1])
        world.flush_cursor_events()
        assert(clipboard(), "P6h P6j: copied, and the copy survives its own notification")
        world.advance_tick()
        paste(world, beacon_buttons(sheet_flow, "cog")[1])
        H.equal(groups("cog"), "beacon x3 /1 [speed-module]", "P6h: group appended at cog's add button")
        assert(clipboard(), "P6j: clipboard kept")
    end)

    H.test(shape .. " P6i P6k the harness refuses the pipette key over a choose-elem-button (assumed engine rule, G18); a hidden beacon is not offered", function()
        local world = beacon_world(shape)
        local screen = game.players[1].gui.screen
        local chooser = screen.add{type = "choose-elem-button", name = "legacy", elem_type = "entity-with-quality"}
        H.errors(function() press(world, chooser) end, "pipettes choose-elem-buttons itself", "P6i: refused")
        H.press(world, "hxrrc_confirm_module_picker", {element = chooser}) --other custom inputs are not affected
        world.set_entity_flags("wide-beacon", {hidden = true})
        setups().gear = {modules = {}, beacons = {}}
        local sheet_flow = sheet({{item = "gear"}})
        left_click(beacon_buttons(sheet_flow, "gear")[1])
        H.equal(offered_choices(), "beacon", "P6k: hidden beacon left out")
    end)
end

--Q2: a left click with something in the hand never opens a picker: the copied ghost pastes as the pipette key does, anything else does nothing

local function right_click(button)
    event_handlers.on_gui_click[button.name]({element = button, player_index = 1, tick = 0, button = defines.mouse_button_type.right})
end

local function sheet_state()
    return M.QualityLoops._deep_copy({chosen = chosen(), setups = setups(), loops = storage[1].quality_loops_by_key})
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " Q2a a click with the copied machine's ghost on another row's machine button opens no picker and pastes one tick later", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world, "uncommon")
        left_click(machine_button(sheet_flow, "cog"), world.tick)
        H.equal(picker(), nil, "no picker")
        H.deep_equal(chosen().cog, {name = "press"}, "nothing written in the click's own tick")
        world.advance_tick()
        drain(world)
        H.deep_equal(chosen().cog, {name = "assembler", quality = "uncommon"}, "machine and quality pasted")
        H.equal(stored(setups().cog.modules), "speed-module,efficiency-module", "modules pasted")
        H.equal(#setups().cog.beacons, 1, "beacon group pasted")
        assert(clipboard(), "clipboard kept")
    end)

    H.test(shape .. " Q2b a click with the copied machine's ghost on a loop stage's machine button pastes onto that stage", function()
        if shape ~= "2.0" then return end --quality loops are calculated on Factorio 2.0 only
        local world = pipette_world(shape)
        local key = M.QualityId.encode("X", "uncommon")
        copied_assembler(world, "rare", {{name = "q"}})
        local loop_flow = sheet({{item = "X", quality = "uncommon"}})
        left_click(H.parse_report(loop_flow.output_flow).loops[key].tiers[1].craft.machine_button, world.tick)
        H.equal(picker(), nil, "no picker")
        world.advance_tick()
        drain(world)
        local normal = storage[1].quality_loops_by_key[key].crafts.normal
        H.deep_equal(normal.machine, {name = "assembler", quality = "rare"}, "stage machine")
        H.equal(stored(normal.setup.modules), "q", "stage modules")
    end)

    H.test(shape .. " Q2c a click with the copied group's ghost adds a group at the add button and replaces a group at a group button, opening no picker", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_beacon_group(world)
        left_click(beacon_buttons(sheet_flow, "X")[1], world.tick)
        H.equal(picker(), nil, "add button: no picker")
        H.equal(#setups().X.beacons, 0, "nothing written in the click's own tick")
        world.advance_tick()
        drain(world)
        H.equal(#setups().X.beacons, 1, "a group added")
        H.equal(setups().X.beacons[1].count, 3, "with its count")
        left_click(beacon_buttons(sheet_flow, "cog")[1], world.tick)
        H.equal(picker(), nil, "group button: no picker")
        world.advance_tick()
        drain(world)
        H.deep_equal(setups().cog.beacons, {clipboard().group}, "cog's group replaced")
    end)

    H.test(shape .. " Q2d a click with another machine's ghost opens no picker, records nothing, and drops the clipboard as the pipette key does", function()
        local world = pipette_world(shape)
        local sheet_flow = copied_assembler(world)
        world.hold_ghost(1, "press") --not flushed: the click itself must drop the clipboard
        left_click(machine_button(sheet_flow, "cog"), world.tick)
        H.equal(picker(), nil, "no picker")
        H.equal(storage[1].pipette_requests, nil, "no request")
        H.equal(clipboard(), nil, "clipboard dropped")
    end)

    H.test(shape .. " Q2e a real item in the hand, clicked on a machine or beacon button, drops a machine or a beacon clipboard and opens no picker", function()
        for _, clipboard_kind in ipairs({"machine", "beacon"}) do
            for _, button_kind in ipairs({"machine", "beacon"}) do
                local world = pipette_world(shape)
                local sheet_flow = clipboard_kind == "machine" and copied_assembler(world) or copied_beacon_group(world)
                assert(clipboard(), "copied")
                world.hold_item(1, "raw", nil, 5) --not flushed: the click itself must drop the clipboard
                local button = button_kind == "machine" and machine_button(sheet_flow, "cog") or beacon_buttons(sheet_flow, "cog")[1]
                local label = clipboard_kind .. " clipboard, " .. button_kind .. " button: "
                left_click(button, world.tick)
                H.equal(picker(), nil, label .. "no picker")
                H.equal(storage[1].pipette_requests, nil, label .. "no request")
                H.equal(clipboard(), nil, label .. "clipboard dropped")
            end
        end
    end)

    H.test(shape .. " Q2f a module ghost on a beacon button, or a machine ghost with nothing copied on a machine button, opens no picker and stores nothing", function()
        local world = pipette_world(shape)
        chosen().gear = {name = "assembler"}
        setups().gear = {modules = {}, beacons = {}}
        local sheet_flow = sheet({{item = "gear"}})
        local before = sheet_state()
        world.hold_ghost(1, "speed-module")
        left_click(beacon_buttons(sheet_flow, "gear")[1], world.tick)
        H.equal(picker(), nil, "module ghost on the add button: no picker")
        world.empty_hand(1)
        world.hold_ghost(1, "fast-assembler")
        left_click(machine_button(sheet_flow, "gear"), world.tick)
        H.equal(picker(), nil, "machine ghost, nothing copied: no picker")
        H.equal(storage[1].pipette_requests, nil, "no request")
        world.advance_tick()
        drain(world)
        H.deep_equal(sheet_state(), before, "nothing stored")
    end)

    H.test(shape .. " Q2h a right click still removes a beacon group with a ghost in the hand, and still clears a slot with a library blueprint in the hand", function()
        local world = pipette_world(shape)
        chosen().gear = {name = "assembler"}
        setups().gear = {modules = {{name = "speed-module"}}, beacons = {{name = "beacon", count = 1, sharing = 1, modules = {}}}}
        local sheet_flow = sheet({{item = "gear"}})
        world.hold_ghost(1, "speed-module")
        right_click(beacon_buttons(sheet_flow, "gear")[1])
        H.equal(#setups().gear.beacons, 0, "group removed")
        world.empty_hand(1)
        world.hold_record(1)
        sheet_flow = sheet({{item = "gear"}})
        right_click(slots(sheet_flow, "gear")[1])
        H.equal(stored(setups().gear.modules), "", "slot cleared")
    end)

    H.test(shape .. " Q2i Q2j a library blueprint in the hand: no click on a slot, machine, loop machine, beacon group or add button opens a picker or stores; an empty hand opens each", function()
        local world = pipette_world(shape)
        chosen().gear = {name = "assembler"}
        setups().gear = {modules = {{name = "speed-module"}}, beacons = {{name = "beacon", count = 1, sharing = 1, modules = {}}}}
        local key = M.QualityId.encode("X", "uncommon")
        local buttons = {
            slot = function() return slots(sheet({{item = "gear"}}), "gear")[1] end,
            machine = function() return machine_button(sheet({{item = "gear"}}), "gear") end,
            group = function() return beacon_buttons(sheet({{item = "gear"}}), "gear")[1] end,
            add = function() return beacon_buttons(sheet({{item = "gear"}}), "gear")[2] end,
        }
        local names = {"slot", "machine", "group", "add"}
        if shape == "2.0" then --quality loops are calculated on Factorio 2.0 only
            buttons.loop_machine = function()
                return H.parse_report(sheet({{item = "X", quality = "uncommon"}}).output_flow).loops[key].tiers[1].craft.machine_button
            end
            names[#names + 1] = "loop_machine"
        end
        for _, name in ipairs(names) do
            world.empty_hand(1)
            local button = buttons[name]()
            storage.computation_stack = {}
            local before = sheet_state()
            world.hold_record(1)
            left_click(button, world.tick)
            H.equal(picker(), nil, "Q2i " .. name .. ": no picker")
            H.equal(storage[1].pipette_requests, nil, "Q2i " .. name .. ": no request")
            H.equal(#storage.computation_stack, 0, "Q2i " .. name .. ": no recompute")
            H.deep_equal(sheet_state(), before, "Q2i " .. name .. ": nothing stored")
            world.empty_hand(1)
            left_click(button, world.tick)
            assert(picker(), "Q2j " .. name .. ": an empty hand opens the picker")
            M.ModulePicker.close(1, false)
        end
    end)
end

H.done("test_pipette")
