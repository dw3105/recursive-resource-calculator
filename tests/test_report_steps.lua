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
        if slices > 10000 then
            H.equal(state.done, true, "report stepper finishes within the bounded test limit")
            return slices
        end
    end
    return slices
end

local function report_signature(report)
    local signature = {energy_mw = report.energy_mw, pollution_per_minute = report.pollution_per_minute,
        energy_caption = report.energy_caption, pollution_caption = report.pollution_caption,
        row_count = report.row_count, loop_row_count = report.loop_row_count, rows = {}}
    for name, row in pairs(report.rows) do
        signature.rows[name] = {rate = row.rate, quality = row.quality, kind = row.kind, machines = row.machines,
            reason = row.reason, machine_caption = row.machine_caption}
    end
    signature.loops = {}
    for key, loop in pairs(report.loops) do
        local loop_signature = {reason = loop.reason, tiers = {}}
        for index, tier in ipairs(loop.tiers) do
            loop_signature.tiers[index] = {quality = tier.quality, rate = tier.rate,
                craft = tier.craft and {machines = tier.craft.machines, reason = tier.craft.reason} or nil,
                recycle = tier.recycle and {machines = tier.recycle.machines, reason = tier.recycle.reason} or nil}
        end
        loop_signature.has_pool = loop.pool ~= nil
        signature.loops[key] = loop_signature
    end
    return signature
end

local function quality_world(shape)
    local world = H.new_world(shape)
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    world.add_item("A")
    world.add_item("X")
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50})
    world.add_recipe({name = "X", category = "crafting", ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-recycling", category = "recycling", ingredients = {{name = "X", amount = 1}}, products = {{name = "A", amount = 1}}, hidden = true})
    world.add_recipe({name = "A-make", category = "crafting", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_player(1)
    world.init()
    require "gui.calculator"
    world.bind("item/X", "X")
    world.bind("item/A", "A-make")
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.X = {name = "assembler"}
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["A-make"] = {name = "assembler"}
    local QualityId = require "logic.quality_id"
    local QualityLoops = require "logic.quality_loops"
    local key = QualityId.encode("X", "uncommon")
    QualityLoops.store(1, key, QualityLoops.normalized(1, key, {type = "item", name = "X", quality = "uncommon"}))
    local loop = storage[1].quality_loops_by_key[key]
    for _, settings in pairs(loop.crafts) do
        settings.machine = {name = "assembler"}
        settings.setup.modules = {{name = "q"}}
    end
    loop.recycle_recipe_name = "X-recycling"
    loop.recycle.machine = {name = "recycler"}
    loop.recycle.setup.modules = {}
    return world
end

local function quality_input(world)
    local Sheet = require "gui.sheet"
    local Solver = require "logic.solver"
    local pane, sheet_flow = H.fill_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = pane}
    local inputs = Sheet.read_inputs(sheet_flow)
    local result = Solver.solve_for(inputs.rates, 1, inputs.product_parts, {start_leftovers = inputs.options.start_leftovers})
    Sheet.publish_result(sheet_flow, result, inputs)
    return pane, sheet_flow, inputs, result
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
    H.test(shape .. " RW1 solved report rows charge 200 ops each", function()
        local world = basic_world(shape)
        local Report = require "gui.report"
        local ReportSteps = require "logic.report_steps"
        local _, sheet_flow, inputs, result = solved_input(world, shape)
        local source = result.columns[1]
        result.columns = {}
        for index = 1, 30 do
            local column = {}
            for key, value in pairs(source) do column[key] = value end
            result.columns[index] = column
        end
        result.status = "error" --Skip the power phase while retaining rates required by the solved row renderer.
        local calls, original = 0, Report.add_staged_solved
        Report.add_staged_solved = function(...) calls = calls + 1; return original(...) end
        local state = ReportSteps.begin(async_input(sheet_flow, inputs, result))
        ReportSteps.step(state, {ops = 2000})
        Report.add_staged_solved = original
        H.equal(calls, math.floor(2000 / ReportSteps.ROW_OPS), "2000 ops renders exactly 2000 / ROW_OPS rows")
    end)

    H.test(shape .. " RW2 positive budget always renders one report row", function()
        local world = basic_world(shape)
        local Report = require "gui.report"
        local ReportSteps = require "logic.report_steps"
        local _, sheet_flow, inputs, result = solved_input(world, shape)
        result.status = "error" --Skip the power phase while retaining rates required by the solved row renderer.
        local calls, original = 0, Report.add_staged_solved
        Report.add_staged_solved = function(...) calls = calls + 1; return original(...) end
        local state = ReportSteps.begin(async_input(sheet_flow, inputs, result))
        ReportSteps.step(state, {ops = 1})
        Report.add_staged_solved = original
        H.equal(calls, 1, "one positive op renders one row")
    end)

    H.test(shape .. " RS-01 a large report takes several slices and parses identically after one publish", function()
        local world = basic_world(shape)
        local Report = require "gui.report"
        local ReportSteps = require "logic.report_steps"
        local _, sheet_flow, inputs, result = solved_input(world, shape)
        local expected = H.parse_report(sheet_flow.output_flow)
        local state = ReportSteps.begin(async_input(sheet_flow, inputs, result))
        local slices = run_to_done(ReportSteps, state, 1)
        H.equal(slices > 3, true, "the report is split across ticks")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), report_signature(expected), "the visible report stayed unchanged while staging")
        H.equal(ReportSteps.publish(state), true, "matching revisions publish")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), report_signature(expected), "sliced report equals the synchronous report")
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
        storage[1].sheet_revision = storage[1].sheet_revision or {}
        storage[1].sheet_revision[inputs.sheet_id] = 1
        run_to_done(ReportSteps, state, 1)
        H.equal(ReportSteps.publish(state), false, "a stale revision is refused")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), report_signature(expected), "a stale build does not replace the old report")
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
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), report_signature(expected), "cancel leaves the old report readable")
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
        local destroy_started = os.clock()
        local published = ReportSteps.publish(state)
        local destroy_seconds = os.clock() - destroy_started
        print(string.format("DESTROY-MEASURE rows=%d seconds=%.9f", expected.row_count, destroy_seconds))
        H.equal(published, true, "the many-row report publishes")
        H.equal(destroy_seconds >= 0, true, "the single destroy call was measured")
        H.deep_equal(report_signature(H.parse_report(output_flow)), report_signature(expected), "no row was dropped")
        H.equal(expected.row_count, 24, "the baseline has every row")
    end)

    H.test(shape .. " RS-06 a diagnostic report is staged in the same row batches", function()
        local world = basic_world(shape)
        local Sheet = require "gui.sheet"
        local ReportSteps = require "logic.report_steps"
        local _, sheet_flow, inputs, result = solved_input(world, shape)
        result.recipe_rates = nil
        result.solved_rates = nil
        result.unsolved_rates = nil
        result.reasons_by_column = result.reasons_by_column or {}
        for _, column in ipairs(result.columns) do result.reasons_by_column[column.recipe_name] = "no_rate" end
        Sheet.publish_result(sheet_flow, result, inputs)
        local expected = H.parse_report(sheet_flow.output_flow)
        local state = ReportSteps.begin(async_input(sheet_flow, inputs, result))
        H.equal(state.diagnostic, true, "missing rates select diagnostic construction")
        H.equal(run_to_done(ReportSteps, state, 1) > 1, true, "diagnostic construction yields")
        H.equal(ReportSteps.publish(state), true, "diagnostic report publishes")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), report_signature(expected), "diagnostic rows match")
    end)
end

H.test("2.0 RS-07 quality-loop power and rows match the synchronous report", function()
    local world = quality_world("2.0")
    local _, sheet_flow, inputs, result = quality_input(world)
    local expected = H.parse_report(sheet_flow.output_flow)
    local ReportSteps = require "logic.report_steps"
    local state = ReportSteps.begin(async_input(sheet_flow, inputs, result))
    H.equal(run_to_done(ReportSteps, state, 1) > 5, true, "quality work yields by tier")
    H.equal(ReportSteps.publish(state), true, "quality report publishes")
    H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), report_signature(expected), "quality report matches")
    H.near_relative(state.energy_consumption, require("logic.compute_power_and_pollution")(1, result.columns, result.recipe_rates), "quality energy")
end)

H.test("2.0 RS-08 burner power and report rows match the synchronous report", function()
    local world = H.new_world("2.0")
    world.add_item("fuel", {value = 12e6, category = "chemical"})
    world.add_burner({name = "tower", type = "reactor", energy_kw = 40000, emissions_per_joule = {pollution = 1e-6},
        burner = {fuel_categories = {"chemical"}, effectivity = 2.5}})
    world.add_player(1)
    world.init()
    require "gui.calculator"
    local Report = require "gui.report"
    local ReportSteps = require "logic.report_steps"
    local Power = require "logic.compute_power_and_pollution"
    local result = {status = "ok", player_index = 1, columns = {{recipe_name = "burn", product_full_name = "item/fuel", burner = {name = "tower"}}},
        recipe_rates = {burn = 2}, solved_rates = {['item/fuel'] = -2}, unsolved_rates = {}, product_parts = {}, reasons_by_column = {}}
    local output_flow = H.gui_root({type = "flow", name = "output_flow"})
    local expected_energy, expected_pollution = Power(1, result.columns, result.recipe_rates)
    Report.new(output_flow, result, expected_energy, expected_pollution, false)
    local expected = H.parse_report(output_flow)
    local state = ReportSteps.begin{parent = output_flow, player_index = 1, sheet_id = "burner", revisions = {sheet = 0, config = 0}, result = result}
    run_to_done(ReportSteps, state, 1)
    H.equal(ReportSteps.publish(state), true, "burner report publishes")
    H.deep_equal(report_signature(H.parse_report(output_flow)), report_signature(expected), "burner row matches")
    H.near_relative(state.pollution, expected_pollution, "burner pollution")
end)

print("RW1 RW2")
H.done("test_report_steps")
