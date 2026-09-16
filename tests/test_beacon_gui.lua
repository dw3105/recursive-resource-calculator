--Beacon groups through the report: adding, counting, sharing, filling, changing and removing groups, filters, field limits, stale controls
local H = require "tests.harness"

--Gear on a 4-slot assembler with two beacons: "beacon" (2 slots, more with quality, speed and efficiency modules) and "mod-beacon" (1 slot, effectivity 1)
local function gui_world(shape, machine_spec)
    local world = H.new_world(shape)
    require "gui.calculator" --registers the event handlers the tests fire
    world.add_item("raw")
    world.add_item("gear")
    world.add_module("speed-module", "speed", {speed = 0.2})
    world.add_module("productivity-module", "productivity", {productivity = 0.1})
    world.add_module("efficiency-module", "efficiency", {consumption = -0.3})
    world.add_module("quality-module", "quality", {quality = 0.1})
    local machine = {name = "assembler", categories = {"crafting"}, speed = 1}
    for key, value in pairs(machine_spec or {}) do machine[key] = value end
    world.add_machine(machine)
    world.add_beacon({name = "beacon", quality_affects_module_slots = true, allowed_module_categories = {"speed", "efficiency", "productivity"}})
    world.add_beacon({name = "mod-beacon", module_slots = 1, distribution_effectivity = 1, allowed_effects = {"consumption", "speed", "pollution", "productivity"}})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.init()
    return world
end

local function find_all(element, predicate, found)
    found = found or {}
    if predicate(element) then found[#found + 1] = element end
    for _, child in ipairs(element.children) do find_all(child, predicate, found) end
    return found
end

local function named(sheet_pane, name)
    return find_all(sheet_pane, function(element) return element.name == name end)
end

local function beacon_buttons(sheet_pane) return named(sheet_pane, "hxrrc_choose_beacon_button") end
local function count_fields(sheet_pane) return named(sheet_pane, "hxrrc_beacon_count_textfield") end
local function sharing_fields(sheet_pane) return named(sheet_pane, "hxrrc_beacon_sharing_textfield") end

local function beacon_module_buttons(sheet_pane, group_index)
    return find_all(sheet_pane, function(element)
        return element.name == "hxrrc_choose_beacon_module_button" and element.tags.group == group_index
    end)
end

local function pick(button, value)
    button.elem_value = value
    event_handlers.on_gui_elem_changed[button.name]({element = button, player_index = 1})
end

local function confirm(field, text)
    field.text = text
    event_handlers.on_gui_confirmed[field.name]({element = field, player_index = 1})
end

local function offered(button)
    local names = {}
    for _, name in ipairs(button.elem_filters[1].name) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ",")
end

local function gear_sheet(rate)
    local report, sheet_pane = H.run_sheet({{item = "gear", rate = rate or 10, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    return report, sheet_pane
end

local function set_groups(groups)
    storage[1].module_setups_by_recipe_name.gear.beacons = groups
end

--Stored groups as "name@quality xcount /sharing [modules]"
local function stored_groups()
    local out = {}
    for _, beacon_group in ipairs(storage[1].module_setups_by_recipe_name.gear.beacons) do
        local names = {}
        for _, module in ipairs(beacon_group.modules) do names[#names + 1] = module.name .. (module.quality and ("@" .. module.quality) or "") end
        out[#out + 1] = beacon_group.name .. (beacon_group.quality and ("@" .. beacon_group.quality) or "") .. " x" .. tostring(beacon_group.count)
            .. " /" .. tostring(beacon_group.sharing) .. " [" .. table.concat(names, ",") .. "]"
    end
    return table.concat(out, "; ")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " L8 beacon groups are added, counted, shared, filled, changed and removed through the report", function()
        local world = gui_world(shape)
        world.set_quality("normal", {beacon_power_usage_multiplier = 2})
        local _, sheet_pane = gear_sheet()
        H.equal(#beacon_buttons(sheet_pane), 1, "only the add button before any group")

        pick(beacon_buttons(sheet_pane)[1], {name = "beacon", quality = "normal"})
        H.equal(stored_groups(), "beacon x1 /1 []", "group added at count 1 and sharing 1, normal quality stored as none")
        assert(#storage.computation_stack > 0, "adding a group recomputes")
        H.equal(#beacon_buttons(sheet_pane), 2, "group row and the add button")

        confirm(count_fields(sheet_pane)[1], "8")
        confirm(sharing_fields(sheet_pane)[1], "2")
        H.equal(stored_groups(), "beacon x8 /2 []", "count and sharing")

        local slots = beacon_module_buttons(sheet_pane, 1)
        H.equal(#slots, 2, "beacon slots")
        pick(slots[2], {name = "speed-module"})
        H.equal(stored_groups(), "beacon x8 /2 [speed-module,speed-module]", "a pick into the group's empty slots fills both (N5)")
        H.equal(storage[1].module_setups_by_recipe_name.gear.modules[1], nil, "machine slots untouched")

        pick(beacon_buttons(sheet_pane)[1], {name = "mod-beacon"})
        H.equal(stored_groups(), "mod-beacon x8 /2 [speed-module]", "changing the beacon keeps count, sharing and fitting modules")

        require("gui.sheet").calculate(nil, sheet_pane, 1)
        local report = H.parse_report(sheet_pane.tabs[1].content.output_flow)
        local machines = 10 / (1 + 8 * 1 * 0.2)
        H.near(report.energy_mw, 0.21 * machines + 8 * machines / 2 * 0.48 * 2, "MW with 4 machines per beacon pair at normal power multiplier 2")

        pick(beacon_buttons(sheet_pane)[1], nil)
        H.equal(stored_groups(), "", "emptying the beacon button removes the group")
        H.equal(#beacon_buttons(sheet_pane), 1, "only the add button again")
    end)

    H.test(shape .. " L9 beacon buttons list beacons; beacon slots follow beacon quality and offer modules the beacon, machine and recipe accept", function()
        gui_world(shape, {allowed_module_categories = {"speed", "productivity", "quality"}})
        set_groups({{name = "beacon", quality = "rare", count = 1, sharing = 1, modules = {}}, {name = "beacon", count = 1, sharing = 1, modules = {}}})
        local _, sheet_pane = gear_sheet()
        H.equal(offered(beacon_buttons(sheet_pane)[1]), "beacon,mod-beacon", "beacons offered")
        local rare_slots = beacon_module_buttons(sheet_pane, 1)
        H.equal(#rare_slots, 4, "rare beacon slots")
        H.equal(#beacon_module_buttons(sheet_pane, 2), 2, "normal beacon slots")
        H.equal(offered(rare_slots[1]), "speed-module", "modules offered in beacon slots")
    end)

    H.test(shape .. " L10 count and sharing fields accept whole numbers from 1 to 9999 only", function()
        gui_world(shape)
        set_groups({{name = "beacon", count = 3, sharing = 2, modules = {}}})
        local _, sheet_pane = gear_sheet()
        for _, fields in ipairs({{"count", count_fields}, {"sharing", sharing_fields}}) do
            for _, text in ipairs({"0", "1.5", "", "10000", "100000000000001", "inf", "nan"}) do
                storage.computation_stack = {}
                local field = fields[2](sheet_pane)[1]
                local before = field.text
                confirm(field, text)
                H.equal(field.text, before, fields[1] .. " field restored after '" .. text .. "'")
                H.equal(#storage.computation_stack, 0, "nothing queued after " .. fields[1] .. " '" .. text .. "'")
            end
        end
        H.equal(stored_groups(), "beacon x3 /2 []", "group unchanged")
        confirm(count_fields(sheet_pane)[1], "9999")
        confirm(sharing_fields(sheet_pane)[1], "9999")
        H.equal(stored_groups(), "beacon x9999 /9999 []", "largest accepted values")
    end)

    H.test(shape .. " W2 stale beacon controls refuse changes and restore once when writes raise events", function()
        gui_world(shape)
        set_groups({{name = "beacon", count = 3, sharing = 2, modules = {{name = "speed-module"}}}})
        local _, pane_a = gear_sheet(10)
        local _, pane_b = gear_sheet(20)
        storage[1].sheet_section = {sheet_pane = pane_a}

        --change through sheet A; sheet B is not rebuilt, the way a failed recomputation leaves it
        confirm(count_fields(pane_a)[1], "5")
        H.equal(stored_groups(), "beacon x5 /2 [speed-module]", "changed through sheet A")
        local queued = #storage.computation_stack

        H.refire_on_script_set = true
        local beacon_b = beacon_buttons(pane_b)[1]
        beacon_b.elem_value = {name = "mod-beacon"}
        H.equal(beacon_b.elem_value and beacon_b.elem_value.name, "beacon", "beacon button restored")
        local count_b = count_fields(pane_b)[1]
        count_b.text = "7"
        H.equal(count_b.text, "3", "count field restored")
        local sharing_b = sharing_fields(pane_b)[1]
        sharing_b.text = "4"
        H.equal(sharing_b.text, "2", "sharing field restored")
        local slot_b = beacon_module_buttons(pane_b, 1)[1]
        slot_b.elem_value = nil
        H.equal(slot_b.elem_value and slot_b.elem_value.name, "speed-module", "beacon slot restored")
        H.refire_on_script_set = false

        H.equal(stored_groups(), "beacon x5 /2 [speed-module]", "stored groups unchanged")
        H.equal(#storage.computation_stack, queued, "nothing queued from sheet B")
    end)
end

H.done("test_beacon_gui")
