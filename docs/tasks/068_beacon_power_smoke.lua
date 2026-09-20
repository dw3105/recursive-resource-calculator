--A beacon-backed chain whose beacon is part of the plain plan before the
--layout search is allowed to decide whether its own power pole is needed.
local H = require "tests.harness"

local function finish_calculation(world, sheet_id)
    for ticks = 1, 900 do
        if not (storage[1].calc_jobs and storage[1].calc_jobs[sheet_id]) then return end
        H.run_ticks(world, 1)
    end
    H.equal(storage[1].calc_jobs and storage[1].calc_jobs[sheet_id], nil,
        "beacon smoke calculation finishes")
end

local function finish_plan(plan)
    local Plan = require "logic.bp.plan"
    while not plan.done do Plan.step(plan, {ops = 1000}) end
    H.equal(plan.ok, true, "beacon smoke plan finishes")
    return plan.result
end

local function run(shape)
    H.test(shape .. " SMOKE-BEACON the beacon survives into the plan", function()
        local world = H.new_world(shape)
        world.add_item("beacon-ore")
        world.add_item("beacon-part")
        world.add_item("beacon-product")
        world.add_module("speed", "speed", {speed = 0.5})
        world.add_machine({name = "beacon-prep", categories = {"crafting"}, speed = 1, module_slots = 0})
        world.add_machine({name = "beacon-assembler", categories = {"crafting"}, speed = 1, module_slots = 0})
        world.add_beacon({name = "beacon", module_slots = 1, distribution_effectivity = 1.5, energy_kw = 480,
            supply_w = 9, supply_h = 9})
        world.add_recipe({name = "make-beacon-part", category = "crafting",
            ingredients = {{name = "beacon-ore", amount = 1}},
            products = {{name = "beacon-part", amount = 1}}})
        world.add_recipe({name = "beacon-powered-product", category = "crafting",
            ingredients = {{name = "beacon-part", amount = 1}},
            products = {{name = "beacon-product", amount = 1}}})
        world.add_default_infrastructure()
        world.add_blueprint_item()
        world.add_player(1)
        world.init()
        require "control"
        world.handlers.on_init()

        world.bind("item/beacon-part", "make-beacon-part")
        world.bind("item/beacon-product", "beacon-powered-product")
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["make-beacon-part"] = {name = "beacon-prep"}
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["beacon-powered-product"] = {name = "beacon-assembler"}
        storage[1].module_setups_by_recipe_name["make-beacon-part"] = {modules = {}, beacons = {}}
        --The beacon row sits away from its machine row.  Its speed module
        --makes the beacon a powered layout entity, not just a graph label.
        storage[1].module_setups_by_recipe_name["beacon-powered-product"] = {
            modules = {}, beacons = {{name = "beacon", quality = "normal", count = 1, sharing = 1,
                modules = {{name = "speed", quality = "normal"}}}},
        }

        local pane, sheet = H.fill_sheet({{item = "beacon-product", rate = 1, unit = "/s"}}, 1)
        storage[1].sheet_section = {sheet_pane = pane}
        local sheet_id = sheet.tags.hxrrc_sheet_id
        storage[1].sheet_revision = {[sheet_id] = 0}
        storage[1].config_revision = 0

        local Sheet = require "gui.sheet"
        Sheet.calculate(Sheet.compute_button_of(sheet))
        finish_calculation(world, sheet_id)

        local Calculation = require "logic.calculation_result"
        local record = Calculation.get(1, sheet_id)
        H.equal(record ~= nil, true, "beacon smoke publishes a calculation")
        H.equal(record.result.status, "ok", "beacon smoke calculation is solvable")

        --This is the plan assertion point, before Generation.start and before
        --packing, routing, or power placement can hide a missing beacon.
        local Snapshot = require "logic.snapshot"
        local plan = finish_plan(require("logic.bp.plan").begin({solver_result = record.result,
            snapshot = Snapshot.of_sheet(sheet)}))
        local beacon_count, beacon_name = 0, nil
        local step_names = {}
        for _, step in ipairs(plan.steps or {}) do
            step_names[step.step_id] = true
            for _, group in ipairs(step.beacon_groups or {}) do
                beacon_count = beacon_count + group.count_per_machine
                beacon_name = group.name
            end
        end
        H.deep_equal((function()
            local names = {}
            for name, present in pairs(step_names) do if present then names[#names + 1] = name end end
            table.sort(names)
            return names
        end)(), {"beacon-powered-product", "make-beacon-part"}, "beacon smoke plan step names")
        H.equal(beacon_count, 1, "beacon smoke plan contains one physical beacon")
        H.equal(beacon_name, "beacon", "beacon smoke plan names the beacon")

        --Generation is not driven here, for the same reason as the fluid graph case: this file guards the plan,
        --and tests/acceptance/beacon_power.lua demands a real successful blueprint.
    end)
end

local M = {run = run}
if ... == nil then
    for _, shape in ipairs(H.shapes()) do run(shape) end
    H.done("smoke_beacon_power")
end
return M
