--Beacon groups: diminishing effects through the beacon profile, beacon and module quality, beacon power, and keeping groups valid
local H = require "tests.harness"

local VANILLA_PROFILE_TO_8 = {1, 0.7071, 0.5773, 0.5, 0.4472, 0.4082, 0.3779, 0.3535}

--Gear on a 4-slot assembler (speed 1, 210 kW, 4 pollution per minute) with the given beacons; machine_spec and recipe_spec fields override the defaults
local function beacon_world(shape, beacon_specs, machine_spec, recipe_spec)
    local world = H.new_world(shape)
    require "gui.calculator" --registers the event handlers the tests fire
    world.add_item("raw")
    world.add_item("gear")
    world.add_module("speed-module-3", "speed", {speed = 0.5, consumption = 0.7, quality = -0.25}, {legendary = {speed = 1.25, consumption = 0.7, quality = -0.25}})
    world.add_module("speed-module", "speed", {speed = 0.2})
    world.add_module("efficiency-module-3", "efficiency", {consumption = -0.5})
    world.add_module("productivity-module", "productivity", {productivity = 0.1})
    local machine = {name = "assembler", categories = {"crafting"}, speed = 1}
    for key, value in pairs(machine_spec or {}) do machine[key] = value end
    world.add_machine(machine)
    for _, spec in ipairs(beacon_specs) do world.add_beacon(spec) end
    local recipe = {name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}}
    for key, value in pairs(recipe_spec or {}) do recipe[key] = value end
    world.add_recipe(recipe)
    world.add_player(1)
    world.init()
    return world
end

--"name" or "name@quality" entries into stored modules
local function module_list(entries)
    local list = {}
    for index, entry in ipairs(entries) do
        local name, quality = entry:match("^([^@]+)@?(.*)$")
        list[index] = {name = name, quality = quality ~= "" and quality or nil}
    end
    return list
end

local function group(name, count, module_entries, fields)
    local beacon_group = {name = name, count = count, sharing = 1, modules = module_list(module_entries)}
    for key, value in pairs(fields or {}) do beacon_group[key] = value end
    return beacon_group
end

local function set_setup(slot_entries, groups)
    local setup = storage[1].module_setups_by_recipe_name.gear
    setup.modules = module_list(slot_entries)
    setup.beacons = groups
end

local function gear_report(rate)
    local report, sheet_pane = H.run_sheet({{item = "gear", rate = rate or 10, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    return report, sheet_pane
end

local function reconfigure()
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
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

local function find_all(element, name, found)
    found = found or {}
    if element.name == name then found[#found + 1] = element end
    for _, child in ipairs(element.children) do find_all(child, name, found) end
    return found
end

--L1 numbers: 2 speed module 3 in slots, 8 beacons (effectivity 1.5, profile[8] = 0.3535) of 2 speed module 3, 10 gears per second
local L1_SPEED = 2 * 0.5 + 8 * 1.5 * 0.3535 * 2 * 0.5
local L1_CONSUMPTION = 2 * 0.7 + 8 * 1.5 * 0.3535 * 2 * 0.7
local L1_MACHINES = 10 / (1 + L1_SPEED)
local L1_MACHINE_MW = 0.21 * L1_MACHINES * (1 + L1_CONSUMPTION)
local L1_BEACON_MW = 8 * L1_MACHINES * 0.48

local function l1_setup(fields)
    set_setup({"speed-module-3", "speed-module-3"}, {group("beacon", 8, {"speed-module-3", "speed-module-3"}, fields)})
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " L1 eight beacons of two speed modules each diminish through the profile and draw power", function()
        beacon_world(shape, {{name = "beacon", profile = VANILLA_PROFILE_TO_8}})
        l1_setup()
        local report = gear_report()
        H.near(report.rows["item/gear"].machines, L1_MACHINES, "machines (1.6020506248)")
        H.near(report.energy_mw, L1_MACHINE_MW + L1_BEACON_MW, "MW of machines and beacons (8.95730214675)")
        H.near(report.pollution_per_minute, 4 * L1_MACHINES * (1 + L1_CONSUMPTION), "pollution per minute (53.4367190003)")
    end)

    H.test(shape .. " L2 a same_type beacon counts its own type, a total beacon counts every beacon", function()
        beacon_world(shape, {
            {name = "beacon", profile = {1, 0.7071, 0.5773, 0.5}},
            {name = "mod-beacon", beacon_counter = "total", distribution_effectivity = 1, module_slots = 1, profile = {1, 0.5, 0.25}},
        })
        set_setup({}, {group("beacon", 2, {"speed-module", "speed-module"}), group("mod-beacon", 1, {"speed-module"})})
        local report = gear_report()
        H.near(report.rows["item/gear"].machines, 10 / (1 + 2 * 1.5 * 0.7071 * 0.4 + 1 * 1 * 0.25 * 0.2), "machines (5.26726081369)")
    end)

    H.test(shape .. " L3 beacon quality raises effectivity and scales beacon power, module quality raises module effects", function()
        local world = beacon_world(shape, {{name = "beacon"}})
        world.set_quality("legendary", {beacon_power_usage_multiplier = 0.5})
        set_setup({}, {group("beacon", 1, {"speed-module-3@legendary", "speed-module-3@legendary"}, {quality = "legendary"})})
        local report = gear_report()
        local machines = 10 / (1 + 2.5 * 2 * 1.25)
        H.near(report.rows["item/gear"].machines, machines, "machines (1.37931034483)")
        H.near(report.energy_mw, 0.21 * machines * (1 + 2.5 * 2 * 0.7) + machines * 0.48 * 0.5, "MW (1.63448275862)")
    end)

    H.test(shape .. " L4 beacons past the end of the profile use its last value, and no profile means no diminishing", function()
        beacon_world(shape, {{name = "short", distribution_effectivity = 1, profile = {1, 0.5}}, {name = "flat", distribution_effectivity = 1}})
        set_setup({}, {group("short", 3, {"speed-module"})})
        H.near(gear_report().rows["item/gear"].machines, 10 / (1 + 3 * 0.5 * 0.2), "machines past the profile (7.69230769231)")
        set_setup({}, {group("flat", 3, {"speed-module"})})
        H.near(gear_report().rows["item/gear"].machines, 10 / (1 + 3 * 0.2), "machines without a profile (6.25)")
    end)

    H.test(shape .. " L5 changing to a machine that ignores beacons drops the groups", function()
        local world = beacon_world(shape, {{name = "beacon"}})
        world.add_machine({name = "no-beacons", categories = {"crafting"}, speed = 1, uses_beacon_effects = false})
        require("logic.indexer").run()
        set_setup({}, {group("beacon", 2, {"speed-module"})})
        local _, sheet_pane = gear_report()
        local machine_button = find_all(sheet_pane, "hxrrc_choose_crafting_machine_button")[1]
        H.pick_choice(machine_button, {name = "no-beacons"})
        H.equal(stored_groups(), "", "groups after the machine change")
    end)

    H.test(shape .. " L6 guard: energy use never drops below 20%", function()
        beacon_world(shape, {{name = "beacon"}})
        set_setup({"efficiency-module-3", "efficiency-module-3", "efficiency-module-3", "efficiency-module-3"}, {})
        local report = gear_report()
        H.near(report.rows["item/gear"].machines, 10, "machines")
        H.near(report.energy_mw, 0.21 * 10 * 0.2, "MW at the 20% floor")
    end)

    H.test(shape .. " L7 productivity from a beacon that allows it reduces ingredients", function()
        beacon_world(shape, {{name = "prod-beacon", distribution_effectivity = 1, profile = {1}, allowed_effects = {"consumption", "speed", "productivity", "pollution"}}})
        set_setup({}, {group("prod-beacon", 1, {"productivity-module"})})
        H.near(gear_report(11).rows["item/raw"].rate, 10, "raw per second at +10%")
    end)

    H.test(shape .. " L11 a beacon without modules still counts toward diminishing", function()
        beacon_world(shape, {{name = "beacon", distribution_effectivity = 1, profile = {1, 0.5, 0.25}}})
        set_setup({}, {group("beacon", 1, {"speed-module"}), group("beacon", 1, {})})
        H.near(gear_report().rows["item/gear"].machines, 10 / (1 + 0.5 * 0.2), "machines (9.09090909091)")
    end)

    H.test(shape .. " L12 beacons shared by several machines draw power once per beacon", function()
        beacon_world(shape, {{name = "beacon", profile = VANILLA_PROFILE_TO_8}})
        l1_setup({sharing = 4})
        local report = gear_report()
        H.near(report.rows["item/gear"].machines, L1_MACHINES, "machines unchanged by sharing")
        H.near(report.energy_mw, L1_MACHINE_MW + L1_BEACON_MW / 4, "MW (4.34339634732)")
    end)

    H.test(shape .. " L13 normal quality's level and beacon power come from its prototype", function()
        local world = beacon_world(shape, {{name = "beacon", profile = VANILLA_PROFILE_TO_8}})
        world.set_quality("normal", {beacon_power_usage_multiplier = 2})
        l1_setup()
        H.near(gear_report().energy_mw, L1_MACHINE_MW + 2 * L1_BEACON_MW, "MW with normal beacon power doubled (15.109176546)")

        world = beacon_world(shape, {{name = "beacon", profile = VANILLA_PROFILE_TO_8}})
        world.set_quality("normal", {beacon_power_usage_multiplier = 2})
        l1_setup({quality = "rare"})
        world.remove_quality("rare")
        reconfigure()
        H.equal(stored_groups(), "beacon x8 /1 [speed-module-3,speed-module-3]", "group falls back to normal quality")
        H.near(gear_report().energy_mw, L1_MACHINE_MW + 2 * L1_BEACON_MW, "MW after the fallback")

        world = beacon_world(shape, {{name = "beacon", profile = VANILLA_PROFILE_TO_8}})
        world.set_quality("normal", {level = 1})
        l1_setup()
        local speed = 2 * 0.5 + 8 * 1.7 * 0.3535 * 2 * 0.5
        local machines = 10 / (1 + speed)
        local report = gear_report()
        H.near(report.rows["item/gear"].machines, machines, "machines at normal level 1 (1.46894647159)")
        H.near(report.energy_mw, 0.21 * machines * (1 + 2 * 0.7 + 8 * 1.7 * 0.3535 * 2 * 0.7) + 8 * machines * 0.48, "MW at normal level 1 (8.45736294729)")
    end)

    H.test(shape .. " G5c a beacon turned into another entity type by a mod drops its group without reading it", function()
        local world = beacon_world(shape, {{name = "beacon"}})
        set_setup({}, {group("beacon", 2, {"speed-module"})})
        world.replace_beacon_with_entity("beacon", "container")
        reconfigure()
        H.equal(stored_groups(), "", "groups")
    end)

    H.test(shape .. " U7 groups keep existing beacons and qualities, fit their beacon's slots, and hold whole counts from 1 to 9999", function()
        local world = beacon_world(shape, {{name = "beacon", quality_affects_module_slots = true}, {name = "gone-beacon"}})
        set_setup({}, {
            group("beacon", 2, {"speed-module", "speed-module", "speed-module", "speed-module"}, {quality = "rare", sharing = 0}),
            group("gone-beacon", 1, {"speed-module"}),
            group("beacon", 3, {}, {sharing = 1.5}),
            group("beacon", 4, {}, {sharing = 10000}),
            group("beacon", 5, {}, {sharing = 0 / 0}),
            group("beacon", 10000, {}),
            group("beacon", 100000000000001, {}),
            group("beacon", 1.5, {}),
        })
        world.remove_quality("rare")
        world.remove_beacon("gone-beacon")
        reconfigure()
        H.equal(stored_groups(), "beacon x2 /1 [speed-module,speed-module]; beacon x3 /1 []; beacon x4 /1 []; beacon x5 /1 []", "kept groups")
    end)

    H.test(shape .. " U8 beacon modules raising an effect the recipe disallows are dropped", function()
        beacon_world(shape, {{name = "prod-beacon", allowed_effects = {"consumption", "speed", "productivity", "pollution"}}}, nil,
            {allowed_effects = {"consumption", "speed", "pollution", "quality"}})
        set_setup({}, {group("prod-beacon", 1, {"productivity-module", "speed-module"})})
        reconfigure()
        H.equal(stored_groups(), "prod-beacon x1 /1 [speed-module]", "kept group modules")
    end)
end

H.done("test_beacons")
