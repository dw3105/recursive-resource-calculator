--Power and report construction yield in bounded work, keep the old report visible, and publish only matching revisions.
local H = require "tests.harness"

local function basic_world(shape)
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate")
    world.add_machine({name = "furnace", categories = {"smelting"}, speed = 1, energy_kw = 100})
    world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "plate", amount = 1}}})
    world.add_player(1)
    world.init()
    require "gui.calculator"
    return world
end

local function solved_input(world, shape)
    local Sheet = require "gui.sheet"
    local Solver = require "logic.solver"
    local pane, sheet_flow = H.fill_sheet({{item = "plate", rate = 3, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = pane}
    local inputs = Sheet.read_inputs(sheet_flow)
    local result = Solver.solve_for(inputs.rates, inputs.player_index, inputs.product_parts,
        {start_leftovers = inputs.options.start_leftovers})
    Sheet.publish_result(sheet_flow, result, inputs)
    return pane, sheet_flow, inputs, result, H.parse_report(sheet_flow.output_flow)
end

local function child_named(parent, name)
    for _, child in ipairs(parent.children) do
        if child.name == name then return child end
    end
end

local function run_to_done(ReportSteps, state, budget)
    local slices = 0
    while not state.done do
        ReportSteps.step(state, {ops = budget or 1})
        slices = slices + 1
        if slices > 10000 then error("report stepper did not finish") end
    end
    return slices
end

local function async_input(sheet_flow, inputs, result)
    return {
        parent = sheet_flow.output_flow,
        player_index = inputs.player_index,
        sheet_id = inputs.sheet_id,
        revisions = {sheet = 0, config = 0},
        result = result,
        options = inputs.options,
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RS-01 a large report takes several slices and parses identically after one publish", function()
        local world = basic_world(shape)
        local Report = require "gui.report"
        local ReportSteps = require "logic.report_steps"
        local _, sheet_flow, inputs, result = solved_input(world, shape)
        local expected = H.parse_report(sheet_flow.output_flow)
        local state = ReportSteps.begin(async_input(sheet_flow, inputs, result))
        local slices = run_to_done(ReportSteps, state, 1)
        H.equal(slices > 5, true, "the report is split across ticks")
        H.deep_equal(H.parse_report(sheet_flow.output_flow), expected, "the visible report stayed unchanged while staging")
        H.equal(ReportSteps.publish(state), true, "matching revisions publish")
        H.deep_equal(H.parse_report(sheet_flow.output_flow), expected, "sliced report equals the synchronous report")
        H.equal(child_named(sheet_flow.output_flow, state.stage_name), nil, "the staged sibling was consumed")
        H.equal(Report ~= nil, true, "the report module remains available")
    end)

    H.test(shape .. " RS-02 a revision change destroys staging and leaves the old report visible", function()
        local world = basic_world(shape)
        local ReportSteps = require "logic.report_steps"
        local _, sheet_flow, inputs, result = solved_input(world, shape)
        local expected = H.parse_report(sheet_flow.output_flow)
        local state = ReportSteps.begin(async_input(sheet_flow, inputs, result))
        ReportSteps.step(state, {ops = 1})
        H.equal(child_named(sheet_flow.output_flow, "report").visible, true, "the old report stays visible during build")
        storage[1].sheet_revision[inputs.sheet_id] = 1
        run_to_done(ReportSteps, state, 1)
        H.equal(ReportSteps.publish(state), false, "a stale revision is refused")
        H.deep_equal(H.parse_report(sheet_flow.output_flow), expected, "a stale build does not replace the old report")
        H.equal(child_named(sheet_flow.output_flow, state.stage_name), nil, "stale staging is destroyed")
    end)

    H.test(shape .. " RS-03 cancel removes staging, keeps the old report, and marks it stale", function()
        local world = basic_world(shape)
        local ReportSteps = require "logic.report_steps"
        local _, sheet_flow, inputs, result = solved_input(world, shape)
        local expected = H.parse_report(sheet_flow.output_flow)
        local state = ReportSteps.begin(async_input(sheet_flow, inputs, result))
        ReportSteps.step(state, {ops = 1})
        H.equal(ReportSteps.cancel(state), true, "cancel accepts a live build")
        H.deep_equal(H.parse_report(sheet_flow.output_flow), expected, "cancel leaves the old report readable")
        H.equal(child_named(sheet_flow.output_flow, state.stage_name), nil, "cancel destroys staging")
        H.equal(child_named(sheet_flow.output_flow, "report").tags.hxrrc_report_stale, true, "cancel marks the old report stale")
    end)

    H.test(shape .. " RS-04 resumable power equals the synchronous totals", function()
        local world = basic_world(shape)
        local Power = require "logic.compute_power_and_pollution"
        local _, _, inputs, result = solved_input(world, shape)
        local expected_energy, expected_pollution = Power(1, result.columns, result.recipe_rates)
        local state = Power.begin(1, result.columns, result.recipe_rates)
        local slices = 0
        while not state.done do
            Power.step(state, {ops = 1})
            slices = slices + 1
        end
        H.equal(slices > 1, true, "power has a resumable cursor")
        H.near_relative(state.energy, expected_energy, "energy")
        H.near_relative(state.pollution, expected_pollution, "pollution")
        H.equal(inputs.player_index, 1, "power uses the sheet player")
    end)

    H.test(shape .. " RS-05 every unsolved row is staged and published", function()
        local world = basic_world(shape)
        local Report = require "gui.report"
        local ReportSteps = require "logic.report_steps"
        local output_flow = H.gui_root({type = "flow", name = "output_flow"})
        local result = {status = "ok", player_index = 1, columns = {}, recipe_rates = {}, solved_rates = {},
            unsolved_rates = {}, product_parts = {}}
        for index = 1, 24 do
            local name = "item/ore-" .. index
            world.add_item("ore-" .. index)
            result.unsolved_rates[name] = index
            result.product_parts[name] = nil
        end
        Report.new(output_flow, result, 0, 0, false)
        local expected = H.parse_report(output_flow)
        local state = ReportSteps.begin{parent = output_flow, player_index = 1, sheet_id = "rows", revisions = {sheet = 0, config = 0}, result = result}
        local slices = run_to_done(ReportSteps, state, 1)
        H.equal(slices > 20, true, "many rows consume many bounded slices")
        H.equal(ReportSteps.publish(state), true, "the many-row report publishes")
        H.deep_equal(H.parse_report(output_flow), expected, "no row was dropped")
        H.equal(expected.row_count, 24, "the baseline has every row")
    end)
end

H.done("test_report_steps")
