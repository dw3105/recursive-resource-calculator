--The path a sheet calculation takes across ticks: snapshot, solve, power, report, publish.
--
--A job contains only plain data. The GUI parent is remembered by report_steps.lua in process-local state and is
--also recoverable from the player's sheet pane, while the job itself carries only the sheet identity and a unique
--staging token.
local Snapshot = require "logic.snapshot"
local Sheet = require "gui.sheet"
local Jobs = require "logic.jobs"
local Registry = require "logic.registry"
local Calculation = require "logic.calculation_result"
local SolverSteps = require "logic.solver_steps"
local ReportSteps = require "logic.report_steps"
local QualityLoops = require "logic.quality_loops"

local CalcPipeline = {}

local next_stage_number = 0

local function finite_copy(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if value_type == "userdata" then
        local ok, name = pcall(function() return value.name end)
        return ok and type(name) == "string" and {name = name} or nil
    end
    if value_type ~= "table" or getmetatable(value) ~= nil then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local copied = finite_copy(child, seen)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local function number(value, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function consume(budget)
    if budget.ops > 0 and budget.ops ~= math.huge then budget.ops = budget.ops - 1 end
end

local function stage_key(player_index, sheet_id)
    next_stage_number = next_stage_number + 1
    return "calc_" .. tostring(player_index) .. "_" .. tostring(sheet_id or "sheet") .. "_" .. tostring(next_stage_number)
end

local function pipeline_input(inputs)
    return {
        rates = finite_copy(inputs.rates) or {},
        player_index = inputs.player_index,
        product_parts = finite_copy(inputs.product_parts) or {},
        options = finite_copy(inputs.options) or {},
        sheet_id = inputs.sheet_id,
    }
end

local function progress(job, phase, done_units, total_units)
    job.phase = phase
    job.progress = job.progress or {}
    job.progress.phase = phase
    job.progress.done_units = math.max(0, math.floor(number(done_units, 0)))
    if total_units == nil then
        job.progress.total_units = nil
    else
        job.progress.total_units = math.max(0, math.floor(number(total_units, 0)))
    end
end

local function cursor(job, phase, value)
    job.cursor = {phase = phase, value = finite_copy(value) or {}}
end

local function input_for_state(state, job)
    if type(state.input) == "table" then return state.input end
    return {
        rates = {},
        product_parts = {},
        options = {},
        player_index = job.player_index,
        sheet_id = job.sheet_id,
        revisions = job.revisions,
    }
end

local function begin_state(context)
    context = context or {}
    return {
        phase = "snapshot",
        cursor = {snapshot = 0},
        snapshot = finite_copy(context.snapshot) or {},
        input = finite_copy(context.input) or {},
        stage_key = context.stage_key,
        solver = nil,
        report = nil,
        result = nil,
        published = false,
    }
end

local function fail(job, code, detail)
    job.done = true
    job.ok = false
    job.phase = "failed"
    job.errors = {code = code, detail = detail}
    progress(job, "failed", 1, 1)
end

local function remember_report_parent(sheet_flow, inputs, key)
    --begin() records the output flow without creating a staged report. The hint is deliberately outside storage;
    --report_steps.lua can rediscover it from storage after a save.
    ReportSteps.begin{
        output_flow = sheet_flow.output_flow,
        player_index = inputs.player_index,
        sheet_id = inputs.sheet_id,
        revisions = inputs.revisions,
        stage_key = key,
        result = {columns = {}},
    }
end

local function begin_report(job, state, result)
    --The synchronous diagnostic renderer supplies no_rate for columns without a solver-specific reason. The
    --incremental renderer receives the same result in slices, so make that implicit diagnostic data explicit before
    --it starts a staged row; otherwise an infeasible mixed sheet would try to calculate a nil recipe rate.
    if result.recipe_rates == nil then
        result.reasons_by_column = result.reasons_by_column or {}
        for _, column in ipairs(result.columns or {}) do
            if result.reasons_by_column[column.recipe_name] == nil then
                result.reasons_by_column[column.recipe_name] = "no_rate"
            end
        end
    end
    local input = input_for_state(state, job)
    local report = ReportSteps.begin{
        player_index = job.player_index,
        sheet_id = job.sheet_id,
        revisions = job.revisions,
        result = result,
        options = input.options,
        stage_key = state.stage_key,
    }
    state.report = report
    state.result = report.result
    job.result = report.result

    --The synchronous path stores repaired quality-loop settings before rendering their rows. Keep that observable
    --choice identical for a successful sliced calculation, while copying it before it can cross the save boundary.
    for _, column in ipairs(result.columns or {}) do
        local info = column.quality_loop
        if info and info.config then
            local config = finite_copy(info.config)
            if config then QualityLoops.store(job.player_index, info.key, config) end
        end
    end

    if report.phase == "power" then
        progress(job, "power", report.progress.done_units, report.progress.total_units)
    else
        progress(job, "report", report.progress.done_units, report.progress.total_units)
    end
end

local function finish_solve(job, state)
    --When the solver finished in the current Lua state its runtime result is available. After a tick, Jobs has
    --copied the state to plain data, so _result is absent and the solver's serialized result is the continuation.
    local result = SolverSteps._result(state.solver) or state.solver.result
    if not result then
        fail(job, "solve_result_missing", "the sliced solver completed without a result")
        return
    end
    begin_report(job, state, result)
    state.solver = nil
    state.phase = "power"
end

local function calculation_record(job, state)
    local snapshot = type(state.snapshot) == "table" and state.snapshot or {}
    local fingerprint = snapshot.fingerprint
    return {
        schema_version = Calculation.SCHEMA_VERSION,
        player_index = job.player_index,
        sheet_id = job.sheet_id,
        sheet_revision = job.revisions and job.revisions.sheet or 0,
        config_revision = job.revisions and job.revisions.config or 0,
        input_fingerprint = type(fingerprint) == "table" and fingerprint.input or nil,
        result = state.result,
    }
end

local function seed_unconfigured_quality_loop(report)
    if report.phase ~= "report" or report.cursor.loop or report.cursor.section ~= "columns" then return end
    local column = report.result.columns and report.result.columns[report.cursor.column]
    if not (column and column.quality_loop and not column.quality_loop.config) then return end

    --ReportSteps' normal loop initializer counts configured tiers. The 2.1 diagnostic loop has no config and its
    --synchronous renderer deliberately emits one reason row; seed that one row so the shared stepper consumes an
    --operation instead of entering its zero-tier path.
    local reason = report.result.reasons_by_column and report.result.reasons_by_column[column.recipe_name]
        or column.quality_loop.reason or "no_rate"
    report.cursor.loop = {
        phase = "tier",
        index = 1,
        count = 1,
        solved = false,
        recipe_rate = nil,
        reason = reason,
        recycler_counts = {},
        recycler_total = 0,
    }
end

function CalcPipeline.start(sheet_flow)
    if not sheet_flow then return nil end

    local snapshot, snapshot_total
    if type(Snapshot.begin_sheet) == "function" and type(Snapshot.progress) == "function" then
        snapshot = Snapshot.begin_sheet(sheet_flow)
        local _, total = Snapshot.progress(snapshot)
        snapshot_total = total
    else
        --Older saves and the pre-slice snapshot module have no builder API; retain their completed-snapshot path.
        snapshot = Snapshot.of_sheet(sheet_flow)
        snapshot_total = 1
    end
    local inputs = Sheet.read_inputs(sheet_flow)
    local revisions = snapshot.revisions or {sheet = 0, config = 0}
    local key = stage_key(inputs.player_index, inputs.sheet_id)
    remember_report_parent(sheet_flow, {
        player_index = inputs.player_index,
        sheet_id = inputs.sheet_id,
        revisions = revisions,
    }, key)

    return Jobs.request_sheet(inputs.player_index, inputs.sheet_id, {
        kind = "calculation",
        sheet_id = inputs.sheet_id,
        revisions = revisions,
        phase = "snapshot",
        cursor = {snapshot = 0},
        progress = {phase = "snapshot", done_units = 0, total_units = snapshot_total},
        snapshot = snapshot,
        input = pipeline_input(inputs),
        stage_key = key,
    })
end

function CalcPipeline.step(job, budget)
    budget = type(budget) == "table" and budget or {ops = 0}
    if budget.ops ~= math.huge then
        budget.ops = math.max(0, math.floor(number(budget.ops, 0)))
    end
    if not job or job.done or budget.ops <= 0 then return job end

    local state = type(job.state) == "table" and job.state or begin_state{}
    job.state = state
    state.cursor = type(state.cursor) == "table" and state.cursor or {}

    while budget.ops > 0 and not job.done do
        if job.phase == "queued" then job.phase = state.phase or "snapshot" end

        if job.phase == "snapshot" then
            state.phase = "snapshot"
            local snapshot = type(state.snapshot) == "table" and state.snapshot or {}
            local done = true
            if snapshot.build ~= nil and type(Snapshot.step) == "function" then
                done = Snapshot.step(snapshot, budget)
                local done_units, total_units = Snapshot.progress(snapshot)
                progress(job, "snapshot", done_units, total_units)
                cursor(job, "snapshot", {done = done_units})
            end
            if done then
                --On legalcopilot-dev (2026-09-29), snapshot+fingerprint cost 86-95 + 10-35 ms; five copies add 31-52 ms.
                --Build the 529-product snapshot a few dozen products per tick instead of stalling Compute.
                snapshot.selection = nil
                state.cursor.snapshot = 1
                state.solver = SolverSteps.begin(input_for_state(state, job))
                state.phase = "solve"
                cursor(job, "solve", state.solver.cursor)
                progress(job, "solve", state.solver.progress.done_units, state.solver.progress.total_units)
                consume(budget)
            end
        elseif job.phase == "solve" then
            if not state.solver then
                fail(job, "solve_state_missing", "the solve phase has no solver state")
            else
                SolverSteps.step(state.solver, budget)
                cursor(job, "solve", state.solver.cursor)
                progress(job, "solve", state.solver.progress.done_units, state.solver.progress.total_units)
                if state.solver.done then finish_solve(job, state) end
            end
        elseif job.phase == "power" or job.phase == "report" then
            if not state.report then
                fail(job, "report_state_missing", "the report phase has no report state")
            else
                seed_unconfigured_quality_loop(state.report)
                ReportSteps.step(state.report, budget)
                local report_phase = state.report.phase == "power" and "power" or "report"
                cursor(job, report_phase, state.report.cursor)
                progress(job, report_phase, state.report.progress.done_units, state.report.progress.total_units)
                if state.report.done then
                    if state.report.ok == false then
                        job.done = true
                        job.ok = false
                        job.phase = "failed"
                        progress(job, "failed", 1, 1)
                    else
                        job.phase = "publish"
                        state.phase = "publish"
                        progress(job, "publish", 0, 1)
                    end
                else
                    job.phase = report_phase
                    state.phase = report_phase
                end
            end
        elseif job.phase == "publish" then
            if not state.report or state.published then
                fail(job, "publish_state_missing", "the publish phase has no report state")
            else
                local published = ReportSteps.publish(state.report)
                if published then
                    --The record is written only after the staged report has passed the same revision check and
                    --swapped into view.  A stale, cancelled, failed or superseded run never reaches this call.
                    Calculation.publish(calculation_record(job, state), budget)
                end
                state.published = true
                job.done = true
                job.ok = published == true
                job.phase = published and "done" or "stale"
                cursor(job, job.phase, {})
                progress(job, job.phase, 1, 1)
                if not published then
                    job.result = nil
                    state.result = nil
                end
                consume(budget)
            end
        else
            fail(job, "unknown_phase", tostring(job.phase))
        end
    end
    return job
end

local function sheet_flow_for(player_index, sheet_id)
    local data = type(storage) == "table" and storage[player_index]
    local pane = data and data.sheet_section and data.sheet_section.sheet_pane
    for _, tab in ipairs(pane and pane.tabs or {}) do
        local sheet_flow = tab.content
        if sheet_flow and Sheet.id_of(sheet_flow) == sheet_id then return sheet_flow end
    end
end

local function cancel_report(job, player_index, sheet_id)
    if job and job.state and job.state.report then
        return ReportSteps.cancel(job.state.report)
    end

    local sheet_flow = sheet_flow_for(player_index, sheet_id)
    if not sheet_flow then return false end
    local key = job and job.state and job.state.stage_key or stage_key(player_index, sheet_id)
    local state = ReportSteps.begin{
        output_flow = sheet_flow.output_flow,
        player_index = player_index,
        sheet_id = sheet_id,
        revisions = job and job.revisions or {},
        stage_key = key,
        result = {columns = {}},
    }
    return ReportSteps.cancel(state)
end

function CalcPipeline.cancel(player_index, sheet_id)
    local data = type(storage) == "table" and storage[player_index]
    local job = data and data.calc_jobs and data.calc_jobs[sheet_id]
    cancel_report(job, player_index, sheet_id)
    return Jobs.cancel(player_index, sheet_id)
end

Jobs.register("calculation", {begin = begin_state, step = CalcPipeline.step})
Registry.calc_pipeline = CalcPipeline

return CalcPipeline
