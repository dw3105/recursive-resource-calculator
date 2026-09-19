--A calculation sliced across ticks commits exactly the synchronous report, or no report when stale or cancelled.
local H = require "tests.harness"
local Registry

local function report_line(line)
    if not line then return nil end
    return {
        rate = line.rate,
        quality = line.quality,
        kind = line.kind,
        machines = line.machines,
        reason = line.reason,
        machine = line.machine,
        machine_caption = line.machine_caption,
        machine_tooltip = line.machine_tooltip,
    }
end

local function report_signature(report)
    local signature = {
        energy_mw = report and report.energy_mw,
        pollution_per_minute = report and report.pollution_per_minute,
        energy_caption = report and report.energy_caption,
        pollution_caption = report and report.pollution_caption,
        row_count = report and report.row_count,
        loop_row_count = report and report.loop_row_count,
        rows = {},
        loops = {},
    }
    for name, row in pairs(report and report.rows or {}) do
        signature.rows[name] = report_line(row)
    end
    for key, loop in pairs(report and report.loops or {}) do
        local loop_signature = {reason = loop.reason, tiers = {}, pool = nil, assist = nil}
        for index, tier in ipairs(loop.tiers or {}) do
            loop_signature.tiers[index] = {
                quality = tier.quality,
                rate = tier.rate,
                craft = report_line(tier.craft),
                recycle = report_line(tier.recycle),
            }
        end
        if loop.assist then
            loop_signature.assist = report_line(loop.assist)
        end
        if loop.pool then loop_signature.pool = {recycle = report_line(loop.pool.recycle)} end
        signature.loops[key] = loop_signature
    end
    return signature
end

local function child_named(parent, name)
    for _, child in ipairs(parent and parent.children or {}) do
        if child.name == name then return child end
    end
end

local function running_job(sheet_id)
    local data = storage[1]
    return data and data.calc_jobs and data.calc_jobs[sheet_id]
end

local function cursor_description(job)
    local cursor = job and job.cursor or {}
    local value = cursor.value or cursor
    local position = value.position or value.column or value.unsolved or value.snapshot or value.section or "?"
    return string.format("phase=%s cursor=%s:%s", tostring(job and job.phase), tostring(cursor.phase), tostring(position))
end

local function wait_for(world, sheet_id, limit)
    local bound = limit or 600
    for tick = 1, bound do
        if not running_job(sheet_id) then return tick - 1 end
        H.run_ticks(world, 1)
    end
    local job = running_job(sheet_id)
    H.equal(job, nil, "job finishes within 600 ticks (" .. cursor_description(job) .. ")")
    return bound
end

local function wait_for_many(world, sheet_ids, limit)
    local bound = limit or 600
    for tick = 1, bound do
        local active = false
        for _, sheet_id in ipairs(sheet_ids) do
            active = active or running_job(sheet_id) ~= nil
        end
        if not active then return tick - 1 end
        H.run_ticks(world, 1)
    end
    for _, sheet_id in ipairs(sheet_ids) do
        local job = running_job(sheet_id)
        if job then
            H.equal(job, nil, "job finishes within 600 ticks (sheet " .. tostring(sheet_id) .. ", " .. cursor_description(job) .. ")")
        end
    end
    return bound
end

local function no_staging(output_flow)
    for _, child in ipairs(output_flow.children or {}) do
        if tostring(child.name):find("hxrrc_report_staging_", 1, true) then return false end
    end
    return true
end

local function base_world(shape)
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate")
    world.add_machine({name = "furnace", categories = {"smelting"}, speed = 1, energy_kw = 100})
    world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}},
        products = {{name = "plate", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    Registry = require "logic.registry"
    return world
end

local function prepared_sheet(targets)
    local Sheet = require "gui.sheet"
    local pane, sheet_flow = H.fill_sheet(targets)
    storage[1].sheet_section = {sheet_pane = pane}
    return Sheet, pane, sheet_flow
end

local function synchronous_report(Sheet, sheet_flow)
    local pipeline = Registry.calc_pipeline
    Registry.calc_pipeline = nil
    Sheet.calculate(Sheet.compute_button_of(sheet_flow))
    local expected = report_signature(H.parse_report(sheet_flow.output_flow))
    Registry.calc_pipeline = pipeline
    return expected
end

local function quality_world(shape)
    local world = H.new_world(shape)
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    world.add_item("A")
    world.add_item("X")
    world.add_module("q", "quality", {quality = 0.25, speed = -0.05})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4})
    world.add_recipe({name = "X", category = "crafting", ingredients = {{name = "A", amount = 1}},
        products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-recycling", category = "recycling", hidden = true,
        ingredients = {{name = "X", amount = 1}}, products = {{name = "A", amount = 1}}})
    world.add_recipe({name = "A-make", category = "crafting", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
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
    Registry = require "logic.registry"
    return world
end

local function infeasible_world(shape)
    local world = H.new_world(shape)
    world.add_item("P")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "backwards", ingredients = {{name = "P", amount = 2}}, products = {{name = "P", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    world.bind("item/P", "backwards")
    Registry = require "logic.registry"
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " CP-01 one default-budget job finishes and publishes a report", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local before = report_signature(H.parse_report(sheet_flow.output_flow))
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "the old report is visible before slicing")
        local sheet_id = Sheet.id_of(sheet_flow)
        local started = CalcPipeline.start(sheet_flow)
        H.equal(started ~= nil, true, "pipeline start registers a job")
        H.equal(running_job(sheet_id) ~= nil, true, "start returns before solving")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), before, "start does not expose a partial report")
        H.equal(Jobs.OPS_PER_TICK > 0, true, "the scheduler has a default budget")
        H.run_ticks(world, 1)
        H.equal(running_job(sheet_id), nil, "the smallest default-budget job finishes within one tick")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "the report is published")
    end)

    H.test(shape .. " CP-11 Compute enqueues instead of publishing and the panel follows the run", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local row = sheet_flow.input_container.children[1]
        row.rate_textfield.text = "4"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local sheet_id = Sheet.id_of(sheet_flow)
        local old_report = child_named(sheet_flow.output_flow, "report")

        Sheet.calculate(Sheet.compute_button_of(sheet_flow))

        H.equal(running_job(sheet_id) ~= nil, true, "Compute enqueues a calculation job")
        H.equal(child_named(sheet_flow.output_flow, "report"), old_report, "Compute does not publish before a tick")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "the previous report remains visible while queued")
        H.equal(Sheet.progressbar_of(sheet_flow).visible, true, "the progress bar is visible while the job runs")
        H.equal(Sheet.cancel_button_of(sheet_flow).visible, true, "Cancel is visible while the job runs")

        wait_for(world, sheet_id)
        H.equal(Sheet.progressbar_of(sheet_flow).visible, false, "the progress bar hides after publish")
        H.equal(Sheet.cancel_button_of(sheet_flow).visible, false, "Cancel hides after publish")
        H.equal(report_signature(H.parse_report(sheet_flow.output_flow)).rows["item/plate"].rate, 4, "the queued input is eventually published")
    end)

    H.test(shape .. " CP-12 Cancel during Compute keeps the old report and marks it stale", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local row = sheet_flow.input_container.children[1]
        row.rate_textfield.text = "4"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local sheet_id = Sheet.id_of(sheet_flow)
        Sheet.calculate(Sheet.compute_button_of(sheet_flow))
        H.equal(running_job(sheet_id) ~= nil, true, "the calculation is running before Cancel")

        event_handlers.on_gui_click["hxrrc_cancel_button"]({element = Sheet.cancel_button_of(sheet_flow), player_index = 1})

        H.equal(running_job(sheet_id), nil, "Cancel removes the running job")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "Cancel leaves the old report intact")
        H.equal(child_named(sheet_flow.output_flow, "report").tags.hxrrc_report_stale, true, "Cancel marks the old report stale")
        H.equal(Sheet.progressbar_of(sheet_flow).visible, false, "Cancel hides the progress bar")
        H.equal(Sheet.cancel_button_of(sheet_flow).visible, false, "Cancel hides itself")
    end)

    H.test(shape .. " CP-02 tiny budget spreads one report across ticks without partial rows", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local old = report_signature(H.parse_report(sheet_flow.output_flow))
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local sheet_id = Sheet.id_of(sheet_flow)
        CalcPipeline.start(sheet_flow)
        local ticks = 0
        while running_job(sheet_id) and ticks < 600 do
            H.run_ticks(world, 1)
            ticks = ticks + 1
            if running_job(sheet_id) then
                H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), old, "no partial report is visible between ticks")
            end
        end
        H.equal(running_job(sheet_id), nil, "tiny-budget job finishes")
        H.equal(ticks > 1, true, "tiny budget uses multiple ticks")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "tiny-budget report equals synchronous report")
    end)

    H.test(shape .. " CP-03 edit during a run drops the stale result and keeps the old report", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local old_report = child_named(sheet_flow.output_flow, "report")
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local sheet_id = Sheet.id_of(sheet_flow)
        CalcPipeline.start(sheet_flow)
        H.run_ticks(world, 3)
        storage[1].sheet_revision = storage[1].sheet_revision or {}
        storage[1].sheet_revision[sheet_id] = (storage[1].sheet_revision[sheet_id] or 0) + 1
        wait_for(world, sheet_id)
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "an edited sheet keeps its previous report")
        H.equal(child_named(sheet_flow.output_flow, "report"), old_report, "an edited sheet keeps the previous report container")
        H.equal(no_staging(sheet_flow.output_flow), true, "stale staging is removed")
    end)

    H.test(shape .. " CP-04 cancel mid-run leaves the old report stale and complete", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local sheet_id = Sheet.id_of(sheet_flow)
        CalcPipeline.start(sheet_flow)
        H.run_ticks(world, 3)
        H.equal(CalcPipeline.cancel(1, sheet_id), true, "cancellation removes the running job")
        H.run_ticks(world, 2)
        H.equal(running_job(sheet_id), nil, "cancelled work is gone")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "cancellation leaves the old report")
        H.equal(child_named(sheet_flow.output_flow, "report").tags.hxrrc_report_stale, true, "cancellation marks the old report stale")
        H.equal(no_staging(sheet_flow.output_flow), true, "cancellation leaves no partial rows")
    end)

    H.test(shape .. " CP-05 two sheets of one player both finish", function()
        local world = base_world(shape)
        local Sheet = require "gui.sheet"
        local pane_a, sheet_a = H.fill_sheet({{item = "plate", rate = 2, unit = "/s"}})
        local expected_a = synchronous_report(Sheet, sheet_a)
        local pane_b, sheet_b = H.fill_sheet({{item = "plate", rate = 5, unit = "/s"}})
        local expected_b = synchronous_report(Sheet, sheet_b)
        storage[1].sheet_section = {sheet_pane = pane_a}
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local id_a, id_b = Sheet.id_of(sheet_a), Sheet.id_of(sheet_b)
        CalcPipeline.start(sheet_a)
        CalcPipeline.start(sheet_b)
        local ticks = wait_for_many(world, {id_a, id_b})
        H.equal(ticks > 1, true, "both sheets are served across ticks")
        H.deep_equal(report_signature(H.parse_report(sheet_a.output_flow)), expected_a, "first sheet report")
        H.deep_equal(report_signature(H.parse_report(sheet_b.output_flow)), expected_b, "second sheet report")
    end)

    H.test(shape .. " CP-06 quality-loop report survives slicing unchanged", function()
        local world = quality_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local sheet_id = Sheet.id_of(sheet_flow)
        CalcPipeline.start(sheet_flow)
        wait_for(world, sheet_id)
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "quality-loop rows and controls are unchanged")
    end)

    H.test(shape .. " CP-07 infeasible report survives slicing unchanged", function()
        local world = infeasible_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "P", rate = 1, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local sheet_id = Sheet.id_of(sheet_flow)
        CalcPipeline.start(sheet_flow)
        wait_for(world, sheet_id)
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "infeasible status and rows are unchanged")
    end)

    H.test(shape .. " CP-08 sheet revision above zero still publishes the synchronous report", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local sheet_id = Sheet.id_of(sheet_flow)
        local player_storage = storage[1]
        H.equal(player_storage ~= nil, true, "player storage exists")
        player_storage.sheet_revision = player_storage.sheet_revision or {}
        local sheet_revisions = player_storage.sheet_revision
        H.equal(sheet_revisions ~= nil, true, "sheet revisions exist")
        sheet_revisions[sheet_id] = 4
        player_storage.config_revision = 0
        local sheet_revision = sheet_revisions[sheet_id]
        local config_revision = player_storage.config_revision
        H.equal(sheet_revision ~= nil, true, "sheet revision exists before start")
        H.equal(config_revision ~= nil, true, "config revision exists before start")
        local expected = synchronous_report(Sheet, sheet_flow)
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        CalcPipeline.start(sheet_flow)
        local job = running_job(sheet_id)
        H.equal(job ~= nil, true, "the sheet-revision job is stored")
        local revisions = job.revisions
        H.equal(revisions ~= nil, true, "the running job stores revisions")
        H.equal(revisions.sheet, sheet_revision, "the job carries the sheet revision from start")
        H.equal(revisions.config, config_revision, "the job carries the config revision from start")
        wait_for(world, sheet_id)
        local report = child_named(sheet_flow.output_flow, "report")
        H.equal(report ~= nil, true, "a non-zero sheet revision publishes a report")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "the report equals the synchronous report")
    end)

    H.test(shape .. " CP-09 config revision above zero still publishes the synchronous report", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local sheet_id = Sheet.id_of(sheet_flow)
        local player_storage = storage[1]
        H.equal(player_storage ~= nil, true, "player storage exists")
        player_storage.config_revision = 3
        local config_revision = player_storage.config_revision
        H.equal(config_revision ~= nil, true, "config revision exists before start")
        local expected = synchronous_report(Sheet, sheet_flow)
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        CalcPipeline.start(sheet_flow)
        local job = running_job(sheet_id)
        H.equal(job ~= nil, true, "the config-revision job is stored")
        local revisions = job.revisions
        H.equal(revisions ~= nil, true, "the running job stores revisions")
        H.equal(revisions.config, config_revision, "the job carries the config revision from start")
        wait_for(world, sheet_id)
        local report = child_named(sheet_flow.output_flow, "report")
        H.equal(report ~= nil, true, "a non-zero config revision publishes a report")
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "the report equals the synchronous report")
    end)

    H.test(shape .. " CP-10 config revision raised during a run drops the result and keeps the old report", function()
        local world = base_world(shape)
        local Sheet, _, sheet_flow = prepared_sheet({{item = "plate", rate = 3, unit = "/s"}})
        local expected = synchronous_report(Sheet, sheet_flow)
        local old_report = child_named(sheet_flow.output_flow, "report")
        H.equal(old_report ~= nil, true, "the previous report exists")
        local player_storage = storage[1]
        H.equal(player_storage ~= nil, true, "player storage exists")
        player_storage.config_revision = 5
        local starting_config_revision = player_storage.config_revision
        H.equal(starting_config_revision ~= nil, true, "config revision exists before start")
        local CalcPipeline = require "logic.calc_pipeline"
        local Jobs = require "logic.jobs"
        Jobs.OPS_PER_TICK = 1
        local sheet_id = Sheet.id_of(sheet_flow)
        CalcPipeline.start(sheet_flow)
        local job = running_job(sheet_id)
        H.equal(job ~= nil, true, "the config-revision job is stored")
        local revisions = job.revisions
        H.equal(revisions ~= nil, true, "the running job stores revisions")
        H.equal(revisions.config, starting_config_revision, "the job carries the starting config revision")
        H.run_ticks(world, 3)
        player_storage.config_revision = starting_config_revision + 1
        local current_config_revision = player_storage.config_revision
        H.equal(current_config_revision ~= nil, true, "the raised config revision exists")
        wait_for(world, sheet_id)
        H.deep_equal(report_signature(H.parse_report(sheet_flow.output_flow)), expected, "a config edit keeps the previous report")
        H.equal(child_named(sheet_flow.output_flow, "report"), old_report, "a config edit keeps the previous report container")
        H.equal(no_staging(sheet_flow.output_flow), true, "stale config staging is removed")
    end)
end

H.done("test_calc_pipeline")
