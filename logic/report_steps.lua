--Power totals and report rows, built a batch at a time.
--
--The saved part of this module is plain data. GUI elements are found again from the player and sheet identity on
--every slice; the one process-local parent hint is only an optimization for callers that start from a test or GUI
--element and is never put in a job.
local Report = require "gui.report"
local Power = require "logic.compute_power_and_pollution"
local QualityLoops = require "logic.quality_loops"

local ReportSteps = {}
--One report row with its module cells: ~1 ms on the player save (2026-09-29); 400 of a 2000-op tick = 5 rows
ReportSteps.ROW_OPS = 400
local parent_hints = {}

local function copy_data(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if value_type == "userdata" then
        --Solver results can carry a prototype in a quality chain. A saved report needs only its stable name.
        local name = value.name
        return type(name) == "string" and {name = name} or nil
    end
    if value_type ~= "table" then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        local key_type = type(key)
        if key_type == "string" or key_type == "number" then
            local copied = copy_data(child, seen)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local function finite_integer(value, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return math.max(0, math.floor(value))
end

local function result_of(input)
    return input.result or input
end

local function output_flow_child(sheet_flow)
    for _, child in ipairs(sheet_flow and sheet_flow.children or {}) do
        if child.name == "output_flow" then return child end
    end
end

local function sheet_flow_from_output(output_flow)
    local element = output_flow
    while element and element.parent and element.parent.type ~= "tabbed-pane" do element = element.parent end
    return element
end

local function stage_token(player_index, sheet_id, input)
    local raw = input.stage_key or (tostring(player_index) .. "_" .. tostring(sheet_id or "report"))
    return tostring(raw):gsub("[^%w_]", "_")
end

local function remember_parent(input, player_index, sheet_id, token)
    local candidate = input.output_flow or input.parent or input.sheet_flow
    if candidate and candidate.name ~= "output_flow" then
        candidate = output_flow_child(input.sheet_flow or sheet_flow_from_output(candidate)) or candidate.output_flow
    end
    if candidate and candidate.name == "output_flow" and candidate.valid ~= false then
        parent_hints[token] = candidate
        local sheet_flow = sheet_flow_from_output(candidate)
        if sheet_flow and sheet_flow.tags and sheet_flow.tags.hxrrc_sheet_id and not sheet_id then
            sheet_id = sheet_flow.tags.hxrrc_sheet_id
        end
    end
    return sheet_id
end

local function output_flow_of(state)
    local hinted = parent_hints[state.stage_token]
    if hinted and hinted.valid ~= false then return hinted end

    local data = type(storage) == "table" and storage[state.player_index]
    local section = data and data.sheet_section
    local pane = section and section.sheet_pane
    for _, tab in ipairs(pane and pane.tabs or {}) do
        local sheet_flow = tab.content
        if sheet_flow and sheet_flow.tags and sheet_flow.tags.hxrrc_sheet_id == state.sheet_id then
            local output_flow = output_flow_child(sheet_flow)
            if output_flow and output_flow.valid ~= false then
                parent_hints[state.stage_token] = output_flow
                return output_flow
            end
        end
    end
end

local function child_named(parent, name)
    for _, child in ipairs(parent and parent.children or {}) do
        if child.name == name then return child end
    end
end

local function current_revisions(state)
    local data = type(storage) == "table" and storage[state.player_index]
    local sheet_revision = data and data.sheet_revision and data.sheet_revision[state.sheet_id] or 0
    local config_revision = data and data.config_revision or 0
    return finite_integer(sheet_revision, 0), finite_integer(config_revision, 0)
end

local function revisions_match(state)
    local sheet_revision, config_revision = current_revisions(state)
    return sheet_revision == state.revisions.sheet and config_revision == state.revisions.config
end

local function reasons_for(state, column)
    return state.result.reasons_by_column and state.result.reasons_by_column[column.recipe_name]
end

local function count_quality_rows(info, recipe_rate, reason)
    if not info.config then return 1 end
    if not reason and recipe_rate and info.tiers then return #info.tiers + 1 end
    return #QualityLoops.tier_names(info.config) + 1
end

local function report_units(result)
    local units = 1 --the report header table is one bounded setup operation
    for _, column in ipairs(result.columns or {}) do
        if column.quality_loop then
            local recipe_rate = result.recipe_rates and result.recipe_rates[column.recipe_name]
            units = units + count_quality_rows(column.quality_loop, recipe_rate, result.reasons_by_column and result.reasons_by_column[column.recipe_name])
            local info = column.quality_loop
            if info.config and info.start_takes_no_items and info.start_leftovers == "craft" then units = units + 1 end
        else
            units = units + 1
        end
    end
    for _, _ in pairs(result.unsolved_rates or {}) do units = units + 1 end
    return units
end

local function loop_indices(result)
    local found = {}
    for index, column in ipairs(result.columns or {}) do
        local info = column.quality_loop
        if info and info.reason ~= "quality_loop_unavailable" and info.config then
            local full_name = "item/" .. info.item
            found[full_name] = found[full_name] or {}
            found[full_name][#found[full_name] + 1] = index
        end
    end
    return found
end

local function sorted_unsolved(result)
    local names = {}
    for name, _ in pairs(result.unsolved_rates or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function initialize_loop(state, column)
    local recipe_rate = state.result.recipe_rates and state.result.recipe_rates[column.recipe_name]
    local reason = reasons_for(state, column)
    local info = column.quality_loop
    local solved = not reason and recipe_rate and info.tiers
    state.cursor.loop = {
        phase = "tier",
        index = 1,
        count = count_quality_rows(info, recipe_rate, reason) - 1,
        solved = solved and true or false,
        recipe_rate = recipe_rate,
        reason = reason,
        recycler_counts = {},
        recycler_total = 0,
    }
end

local function ensure_stage(state, output_flow)
    if state.stage_started then return child_named(output_flow, state.stage_name) end
    local old_stage = child_named(output_flow, state.stage_name)
    if old_stage then old_stage.destroy() end
    local stage = Report.begin_staged(output_flow, state.result,
        state.power and state.power.energy or nil, state.power and state.power.pollution or nil,
        state.round_up_machines, state.diagnostic, state.stage_name)
    stage.visible = false
    state.stage_started = true
    return stage
end

local function count_progress(state)
    state.progress.done_units = state.progress.done_units + 1
end

local function consume(budget, ops)
    budget.ops = budget.ops - (ops or 1)
end

local function step_report_once(state, budget)
    local output_flow = output_flow_of(state)
    if not output_flow then
        state.done, state.ok = true, false
        state.phase = "report_failed"
        return
    end

    local report = ensure_stage(state, output_flow)
    if not report then
        state.done, state.ok = true, false
        state.phase = "report_failed"
        return
    end
    if not state.cursor.section then state.cursor.section = "columns" end

    if not state.cursor.loop and state.cursor.section == "columns" then
        local column = state.result.columns and state.result.columns[state.cursor.column]
        if column then
            if column.quality_loop and Report.staged_column_renderable(column, state.result) then
                initialize_loop(state, column)
            elseif not column.quality_loop then
                if Report.staged_column_renderable(column, state.result) then
                    local parts = column.binding_full_name and state.result.product_parts and state.result.product_parts[column.product_full_name]
                    Report.add_staged_solved(report, column, state.result.solved_rates and state.result.solved_rates[column.product_full_name],
                        state.result.recipe_rates and state.result.recipe_rates[column.recipe_name], state.round_up_machines, reasons_for(state, column), parts)
                end
                state.cursor.column = state.cursor.column + 1
                consume(budget, ReportSteps.ROW_OPS)
                count_progress(state)
                return
            else
                state.cursor.column = state.cursor.column + 1
                consume(budget, ReportSteps.ROW_OPS)
                count_progress(state)
                return
            end
        else
            state.cursor.section = "unsolved"
            state.cursor.unsolved_names = state.cursor.unsolved_names or sorted_unsolved(state.result)
            state.cursor.unsolved = 1
        end
    end

    if state.cursor.loop then
        local column = state.result.columns[state.cursor.column]
        local loop = state.cursor.loop
        local info = column.quality_loop
        if loop.phase == "tier" then
            if loop.index <= loop.count then
                Report.add_staged_quality_tier(report, column, loop.recipe_rate, state.round_up_machines, loop.reason, loop, loop.index)
                loop.index = loop.index + 1
                if loop.index > loop.count then
                    if info.config and info.start_takes_no_items and info.start_leftovers == "craft" then
                        loop.phase = "assist"
                    elseif info.config then
                        loop.phase = "pool"
                    else
                        state.cursor.loop = nil
                        state.cursor.column = state.cursor.column + 1
                    end
                end
                consume(budget, ReportSteps.ROW_OPS)
                count_progress(state)
                return
            end
        elseif loop.phase == "assist" then
            Report.add_staged_quality_assist(report, column, loop.recipe_rate, state.round_up_machines, loop.solved)
            loop.phase = info.config and "pool" or "done"
            consume(budget, ReportSteps.ROW_OPS)
            count_progress(state)
            return
        elseif loop.phase == "pool" then
            Report.add_staged_quality_pool(report, column, loop.recipe_rate, state.round_up_machines, loop, loop.reason)
            loop.phase = "done"
            consume(budget, ReportSteps.ROW_OPS)
            count_progress(state)
            return
        end
        if loop.phase == "done" then
            state.cursor.loop = nil
            state.cursor.column = state.cursor.column + 1
        end
    end

    if state.cursor.section == "unsolved" then
        local name = state.cursor.unsolved_names[state.cursor.unsolved]
        if not name then
            state.phase, state.done, state.ok = "done", true, true
            return
        end
        local parts = state.result.product_parts and state.result.product_parts[name]
        if Report.staged_product_renderable(name, parts) then
            local loops = {}
            for _, column_index in ipairs(state.loop_indices[name] or {}) do
                loops[#loops + 1] = state.result.columns[column_index].quality_loop
            end
            Report.add_staged_unsolved(report, name, state.result.unsolved_rates[name], parts, #loops > 0 and loops or nil)
        end
        state.cursor.unsolved = state.cursor.unsolved + 1
        consume(budget, ReportSteps.ROW_OPS)
        count_progress(state)
    end
end

function ReportSteps.begin(input)
    input = input or {}
    local result = copy_data(result_of(input)) or {}
    local player_index = input.player_index or result.player_index or 1
    local sheet_id = input.sheet_id or (input.revisions and input.revisions.sheet) or result.sheet_id
    local token = stage_token(player_index, sheet_id, input)
    sheet_id = remember_parent(input, player_index, sheet_id, token) or sheet_id
    local revisions = input.revisions or {}
    local diagnostic = result.recipe_rates == nil
    local state = {
        player_index = player_index,
        sheet_id = sheet_id,
        revisions = {sheet = finite_integer(revisions.sheet or input.sheet_revision, 0), config = finite_integer(revisions.config or input.config_revision, 0)},
        result = result,
        round_up_machines = input.round_up_machines ~= nil and input.round_up_machines or (input.options and input.options.round_up) or false,
        diagnostic = diagnostic,
        stage_token = token,
        stage_name = "hxrrc_report_staging_" .. token,
        stage_started = false,
        phase = (not diagnostic and result.status == "ok") and "power" or "report",
        cursor = {column = 1, section = "columns"},
        loop_indices = loop_indices(result),
        progress = {phase = (not diagnostic and result.status == "ok") and "power" or "report", done_units = 0},
        done = false,
        ok = nil,
        cancelled = false,
    }
    if state.phase == "power" then
        state.power = Power.begin(player_index, result.columns or {}, result.recipe_rates or {})
        state.progress.total_units = #(result.columns or {}) + report_units(result)
    else
        state.progress.total_units = report_units(result)
    end
    return state
end

function ReportSteps.step(state, budget)
    budget = budget or {ops = 0}
    budget.ops = finite_integer(budget.ops, 0)
    while budget.ops > 0 and not state.done and not state.cancelled do
        if state.phase == "power" then
            Power.step(state.power, budget)
            state.progress.phase = "power"
            state.progress.done_units = state.power.done_units
            if state.power.done then
                state.phase = "report"
                state.progress.phase = "report"
                state.progress.done_units = 0
                state.energy_consumption = state.power.energy
                state.pollution = state.power.pollution
            end
        elseif state.phase == "report" then
            step_report_once(state, budget)
        else
            state.done = true
        end
    end
    return state
end

local function mark_stale(output_flow)
    local report = child_named(output_flow, "report")
    if not report then return end
    local tags = report.tags or {}
    tags.stale = true
    tags.hxrrc_report_stale = true
    report.tags = tags
end

function ReportSteps.cancel(state)
    if state.done then return false end
    local output_flow = output_flow_of(state)
    local stage = output_flow and child_named(output_flow, state.stage_name)
    if stage then stage.destroy() end
    if output_flow then mark_stale(output_flow) end
    state.cancelled = true
    state.done, state.ok = true, false
    state.phase = "cancelled"
    return true
end

--Swaps the staged container in only after both saved revisions still match. A mismatch destroys only the hidden
--container, so the last published report remains exactly as it was.
function ReportSteps.publish(state)
    if not state or state.cancelled or not state.done or state.ok == false then return false end
    local output_flow = output_flow_of(state)
    local staged = output_flow and child_named(output_flow, state.stage_name)
    if not output_flow or not staged then return false end
    if not revisions_match(state) then
        staged.destroy()
        state.ok = false
        state.phase = "stale"
        return false
    end

    local previous = child_named(output_flow, "report")
    if previous and previous ~= staged then
        local old_name = "hxrrc_report_previous_" .. state.stage_token
        previous.name = old_name
        output_flow.swap_children(previous:get_index_in_parent(), staged:get_index_in_parent())
        staged.name = "report"
        staged.visible = true
        previous.visible = false
        previous.destroy()
    else
        staged.name = "report"
        staged.visible = true
    end
    state.published = true
    return true
end

return ReportSteps
