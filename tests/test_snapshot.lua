--The sheet snapshot preserves row inputs and setup choices as plain data, fingerprints every solve input, and classifies stale results.
local H = require "tests.harness"

local QualityId = require "logic.quality_id"
local Snapshot
local Sheet

local function world_with(shape)
    local world = H.new_world(shape)
    Snapshot = require "logic.snapshot"
    Sheet = require "gui.sheet"
    world.add_item("raw")
    world.add_item("gear")
    world.add_fluid("water")
    world.add_module("speed-module", "speed", {speed = 0.2})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_beacon({name = "beacon", module_slots = 2})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}},
        products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.init()
    return world
end

local function gear_selection(snapshot)
    for _, entry in ipairs(snapshot.selection) do
        if entry.recipe_name == "gear" then return entry end
    end
end

local function configured_setup()
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler", quality = "rare"}
    storage[1].module_setups_by_recipe_name.gear = {
        modules = {{name = "speed-module", quality = "rare"}, {name = "speed-module"}},
        beacons = {{name = "beacon", quality = "rare", count = 3, sharing = 2,
            modules = {{name = "speed-module", quality = "rare"}}}},
    }
end

local function walk_plain(value, path)
    path = path or "snapshot"
    if type(value) == "userdata" then
        error(path .. " contains a LuaObject", 0)
    end
    if type(value) == "table" then
        for key, child in pairs(value) do walk_plain(child, path .. "." .. tostring(key)) end
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " S1 row order keeps typed text unit and full precision", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({
            {item = "gear", rate = 12.345678901234567, unit = "/s"},
            {fluid = "water", rate = 3.25, unit = "/m"},
        })
        local snapshot = Snapshot.of_sheet(sheet_flow)
        H.equal(#snapshot.targets, 2, "two targets")
        H.equal(snapshot.targets[1].index, 1, "first index")
        H.equal(snapshot.targets[1].full_name, "item/gear", "first target")
        H.equal(snapshot.targets[1].raw_text, "12.345678901234567", "first typed text")
        H.equal(snapshot.targets[1].time_unit, "/s", "first unit")
        H.near_relative(snapshot.targets[1].rate_per_second, 12.345678901234567, "first full precision rate")
        H.equal(snapshot.targets[2].full_name, "fluid/water", "second target")
        H.equal(snapshot.targets[2].time_unit, "/m", "second unit")
        H.near_relative(snapshot.targets[2].rate_per_second, 3.25 / 60, "second rate per second")
    end)

    H.test(shape .. " S2 quality target carries its parts", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", quality = "rare", rate = 1.25, unit = "/s"}})
        local snapshot = Snapshot.of_sheet(sheet_flow)
        local target = snapshot.targets[1]
        H.equal(target.full_name, QualityId.encode("gear", "rare"), "quality full name")
        H.deep_equal(target.parts, {type = "item", name = "gear", quality = "rare"}, "quality parts")
        H.equal(target.quality, "rare", "quality name")
    end)

    H.test(shape .. " S3 unusable rate is invalid and has no rate", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}})
        sheet_flow.input_container.children[1].rate_textfield.text = "not-a-rate"
        local target = Snapshot.of_sheet(sheet_flow).targets[1]
        H.equal(target.valid, false, "invalid rate")
        H.equal(target.rate_per_second, nil, "no unusable rate")
        H.equal(target.reason, "rate_not_finite", "rate reason")
    end)

    H.test(shape .. " S4 empty sheet has an empty target list", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({})
        H.deep_equal(Snapshot.of_sheet(sheet_flow).targets, {}, "empty targets")
    end)

    H.test(shape .. " S5 selection copies machine quality ordered modules and beacon groups", function()
        world_with(shape)
        configured_setup()
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local entry = gear_selection(Snapshot.of_sheet(sheet_flow))
        H.equal(entry.recipe_name, "gear", "recipe name")
        H.deep_equal(entry.machine, {name = "assembler", quality = "rare"}, "machine identity")
        H.deep_equal(entry.modules, {
            {name = "speed-module", quality = "rare"}, {name = "speed-module", quality = "normal"},
        }, "ordered machine modules")
        H.equal(entry.beacons[1].type, "beacon", "beacon type")
        H.equal(entry.beacons[1].quality, "rare", "beacon quality")
        H.equal(entry.beacons[1].count, 3, "beacon count")
        H.equal(entry.beacons[1].sharing, 2, "beacon sharing")
        H.deep_equal(entry.beacons[1].modules, {{name = "speed-module", quality = "rare"}}, "beacon modules")
    end)

    H.test(shape .. " S6 an explicitly unselected binding remains present", function()
        world_with(shape)
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = nil
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local entry = gear_selection(Snapshot.of_sheet(sheet_flow))
        H.equal(entry ~= nil, true, "binding present")
        H.equal(entry.status, "unselected", "unselected binding marked")
        H.equal(entry.machine, nil, "nothing chosen")
    end)

    H.test(shape .. " S7 snapshot contains only plain data", function()
        world_with(shape)
        configured_setup()
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}})
        walk_plain(Snapshot.of_sheet(sheet_flow))
    end)

    H.test(shape .. " S8 unchanged sheet fingerprints equally twice and setup changes it", function()
        world_with(shape)
        configured_setup()
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local base = Snapshot.of_sheet(sheet_flow)
        local first, second = Snapshot.fingerprint(base), Snapshot.fingerprint(Snapshot.of_sheet(sheet_flow))
        H.equal(first, second, "unchanged fingerprint")

        sheet_flow.input_container.children[1].rate_textfield.text = "2"
        H.equal(Snapshot.fingerprint(Snapshot.of_sheet(sheet_flow)) ~= first, true, "rate changes fingerprint")
        sheet_flow.input_container.children[1].rate_textfield.text = "1"
        sheet_flow.input_container.children[1].time_unit_dropdown.selected_index = 1
        H.equal(Snapshot.fingerprint(Snapshot.of_sheet(sheet_flow)) ~= first, true, "unit changes fingerprint")
        sheet_flow.input_container.children[1].time_unit_dropdown.selected_index = 2

        storage[1].module_setups_by_recipe_name.gear.modules[1].name = "speed-module"
        storage[1].module_setups_by_recipe_name.gear.modules[1].quality = "normal"
        local module_changed = Snapshot.fingerprint(Snapshot.of_sheet(sheet_flow))
        H.equal(module_changed ~= first, true, "module changes fingerprint")
        storage[1].module_setups_by_recipe_name.gear.modules[1].quality = "rare"
        local restored = Snapshot.fingerprint(Snapshot.of_sheet(sheet_flow))
        H.equal(restored, first, "module restoration restores fingerprint")

        storage[1].module_setups_by_recipe_name.gear.beacons[1].count = 4
        H.equal(Snapshot.fingerprint(Snapshot.of_sheet(sheet_flow)) ~= first, true, "beacon count changes fingerprint")
        storage[1].module_setups_by_recipe_name.gear.beacons[1].count = 3
        H.equal(Snapshot.fingerprint(Snapshot.of_sheet(sheet_flow)) ~= first, false, "beacon restoration restores fingerprint")

        Sheet.round_up_checkbox_of(sheet_flow).state = true
        H.equal(Snapshot.fingerprint(Snapshot.of_sheet(sheet_flow)) ~= first, true, "round-up changes fingerprint")
    end)

    H.test(shape .. " S9 all states distinguish a stale result from current", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local snapshot = Snapshot.of_sheet(sheet_flow)
        local fingerprint = Snapshot.fingerprint(snapshot)
        H.equal(Snapshot.state_of(snapshot, nil, false), "not_computed", "not computed")
        H.equal(Snapshot.state_of(snapshot, fingerprint, true), "pending", "pending")
        H.equal(Snapshot.state_of(snapshot, fingerprint, false), "current", "current")
        H.equal(Snapshot.state_of(snapshot, "old-result", false), "stale", "stale")
        snapshot.state = "failed"
        H.equal(Snapshot.state_of(snapshot, fingerprint, false), "failed", "failed")
        H.equal(Snapshot.state_of(snapshot, "old-result", false), "failed", "failed stale result")
    end)
end

H.done("test_snapshot")
