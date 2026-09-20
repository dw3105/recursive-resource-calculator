--A small calculated chain whose fluid producer and consumer must survive into
--the plain blueprint plan before the layout search is allowed to run.
local H = require "tests.harness"

local function sorted_keys(values)
    local result = {}
    for value, present in pairs(values or {}) do
        if present then result[#result + 1] = value end
    end
    table.sort(result)
    return result
end

local function calculated_graph(result)
    local steps, flows = {}, {}
    for _, column in ipairs(result and result.columns or {}) do
        local name = column.recipe_name or column.step_id
        if name then steps[name] = true end
        for full_name, amount in pairs(column.net_amounts or {}) do
            if type(full_name) == "string" and amount ~= 0 then flows[full_name] = true end
        end
    end
    for full_name, amount in pairs(result and result.solved_rates or {}) do
        if type(full_name) == "string" and amount ~= 0 then flows[full_name] = true end
    end
    for full_name, amount in pairs(result and result.unsolved_rates or {}) do
        if type(full_name) == "string" and amount ~= 0 then flows[full_name] = true end
    end
    return {steps = sorted_keys(steps), flows = flows, flow_names = sorted_keys(flows)}
end

local function finish_calculation(world, sheet_id)
    for ticks = 1, 900 do
        if not (storage[1].calc_jobs and storage[1].calc_jobs[sheet_id]) then return end
        H.run_ticks(world, 1)
    end
    H.equal(storage[1].calc_jobs and storage[1].calc_jobs[sheet_id], nil,
        "fluid smoke calculation finishes")
end

local function finish_plan(plan)
    local Plan = require "logic.bp.plan"
    while not plan.done do Plan.step(plan, {ops = 1000}) end
    H.equal(plan.ok, true, "fluid smoke plan finishes")
    return plan.result
end

local function run(shape)
    H.test(shape .. " SMOKE-FLUID the calculated fluid chain survives into the plan", function()
        local world = H.new_world(shape)
        world.add_item("fluid-ore")
        world.add_item("fluid-product")
        world.add_fluid("smoke-fluid")
        world.add_machine({name = "fluid-maker", categories = {"chemistry"}, speed = 1, module_slots = 0})
        world.add_machine({name = "fluid-consumer", categories = {"chemistry"}, speed = 1, module_slots = 0})
        world.add_recipe({name = "make-smoke-fluid", category = "chemistry",
            ingredients = {{name = "fluid-ore", amount = 1}},
            products = {{type = "fluid", name = "smoke-fluid", amount = 1}}})
        world.add_recipe({name = "consume-smoke-fluid", category = "chemistry",
            ingredients = {{type = "fluid", name = "smoke-fluid", amount = 1}},
            products = {{name = "fluid-product", amount = 1}}})
        world.add_default_infrastructure()
        world.add_blueprint_item()
        world.add_player(1)
        world.init()
        require "control"
        world.handlers.on_init()

        world.bind("fluid/smoke-fluid", "make-smoke-fluid")
        world.bind("item/fluid-product", "consume-smoke-fluid")
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["make-smoke-fluid"] = {name = "fluid-maker"}
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["consume-smoke-fluid"] = {name = "fluid-consumer"}

        local pane, sheet = H.fill_sheet({{item = "fluid-product", rate = 1, unit = "/s"}}, 1)
        storage[1].sheet_section = {sheet_pane = pane}
        local sheet_id = sheet.tags.hxrrc_sheet_id
        storage[1].sheet_revision = {[sheet_id] = 0}
        storage[1].config_revision = 0

        local Sheet = require "gui.sheet"
        Sheet.calculate(Sheet.compute_button_of(sheet))
        finish_calculation(world, sheet_id)

        local Calculation = require "logic.calculation_result"
        local record = Calculation.get(1, sheet_id)
        H.equal(record ~= nil, true, "fluid smoke publishes a calculation")
        H.equal(record.result.status, "ok", "fluid smoke calculation is solvable")
        local graph = calculated_graph(record.result)
        H.deep_equal(graph.steps, {"consume-smoke-fluid", "make-smoke-fluid"},
            "fluid smoke calculated step names")
        H.equal(graph.flows["fluid/smoke-fluid"], true,
            "fluid smoke calculation keeps the full fluid flow name")
        H.equal(graph.flows["item/fluid-product"], true,
            "fluid smoke calculation keeps the item output flow name")

        --This is still before Generation.start: the plan must carry the same
        --fluid flow, rather than letting layout manufacture an external import.
        local Snapshot = require "logic.snapshot"
        local Plan = require "logic.bp.plan"
        local plan = finish_plan(Plan.begin({solver_result = record.result, snapshot = Snapshot.of_sheet(sheet)}))
        local plan_flows = {}
        local plan_steps = {}
        for _, step in ipairs(plan.steps or {}) do plan_steps[step.step_id] = true end
        for _, flow in ipairs(plan.flows or {}) do plan_flows[flow.flow_id or flow.full_name] = true end
        H.deep_equal(sorted_keys(plan_steps), {"consume-smoke-fluid", "make-smoke-fluid"},
            "fluid smoke plan step names")
        H.equal(plan_flows["fluid/smoke-fluid"], true,
            "fluid smoke plan contains the full fluid flow name")

        --Generation is not driven here. A cheap graph regression must stay green while layout is still being
        --repaired, and a positive generation gate must stay red until it truly succeeds; one case cannot be
        --both. The positive case lives in tests/acceptance/fluid_chain.lua and demands success.
    end)
end

local M = {run = run}
if ... == nil then
    for _, shape in ipairs(H.shapes()) do run(shape) end
    H.done("smoke_fluid")
end
return M
