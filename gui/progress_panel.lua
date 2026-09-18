--The progress bar and Cancel button on a sheet.
--
--Owned by lane W1-progress. The bar shows real work: a phase name a player can read and a fraction that stays
--below 1 until a complete result is committed. Nothing invents a countdown while the dependency graph is still
--growing.
--
--The calculator window is never disabled while work runs, because the controls that stop that work live inside
--it. Cancel stops within two ticks of its handler and leaves the previous report visible and marked canceled.
local ProgressPanel = {}

local UNKNOWN_TOTAL_ESTIMATE = 100
local CANCEL_LABEL_NAME = "hxrrc_calc_canceled_label"

--Requiring Sheet at module load would recurse: Sheet requires this module to install its handlers.
local function Sheet()
    return require "gui.sheet"
end

local function Jobs()
    return require "logic.jobs"
end

local function controls_of(sheet_flow)
    if not sheet_flow then
        return nil, nil
    end
    local sheet = Sheet()
    return sheet.progressbar_of(sheet_flow), sheet.cancel_button_of(sheet_flow)
end

local function phase_key(phase)
    phase = tostring(phase or "reading")
    if phase:sub(1, 6) == "hxrrc." then
        return phase
    end
    if phase:sub(1, 11) == "calc_phase_" then
        return "hxrrc." .. phase
    end
    return "hxrrc.calc_phase_" .. phase
end

local function finite_nonnegative_integer(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return 0
    end
    return math.max(0, math.floor(value))
end

local function progress_value(progress)
    local done = finite_nonnegative_integer(progress.done_units)
    local total = progress.total_units
    if type(total) == "number" and total == total and total ~= math.huge and total ~= -math.huge then
        total = math.max(0, math.floor(total))
        if total == 0 then
            return done > 0 and 1 or 0, total
        end
        --A completed total is the only progress update that may write 1. The job publishes that update only
        --when its result or final diagnostic is ready, so the last phase's first update remains below 1.
        return math.min(1, done / total), total
    end

    --There is no honest denominator while discovery is still growing. This is a documented display estimate,
    --not a claimed total: the tooltip says "?", and the asymptote guarantees that unknown work never reads 1.
    if done == 0 then
        return 0, "?"
    end
    return math.min(0.99, done / (done + UNKNOWN_TOTAL_ESTIMATE)), "?"
end

function ProgressPanel.show(sheet_flow)
    local bar, cancel = controls_of(sheet_flow)
    if not bar or not cancel or bar.valid == false or cancel.valid == false then
        return
    end
    bar.visible = true
    cancel.visible = true
end

function ProgressPanel.hide(sheet_flow)
    local bar, cancel = controls_of(sheet_flow)
    if not bar or not cancel or bar.valid == false or cancel.valid == false then
        return
    end
    bar.visible = false
    cancel.visible = false
end

--progress: {phase = locale key suffix, done_units, total_units | nil}
function ProgressPanel.update(sheet_flow, progress)
    if not progress then
        return
    end
    local bar, cancel = controls_of(sheet_flow)
    if not bar or not cancel or bar.valid == false or cancel.valid == false then
        return
    end

    local key = phase_key(progress.phase)
    local value, total = progress_value(progress)
    bar.caption = {key}
    bar.tooltip = {"hxrrc.calc_progress_tooltip", {key}, finite_nonnegative_integer(progress.done_units), total}
    bar.value = value
    ProgressPanel.show(sheet_flow)
end

local function output_flow_of(sheet_flow)
    for _, child in ipairs(sheet_flow and sheet_flow.children or {}) do
        if child.name == "output_flow" then
            return child
        end
    end
end

local function mark_canceled(sheet_flow)
    local output_flow = output_flow_of(sheet_flow)
    if not output_flow or output_flow.valid == false then
        return
    end

    for _, child in ipairs(output_flow.children) do
        if child.name == CANCEL_LABEL_NAME then
            child.caption = {"hxrrc.calc_canceled"}
            return
        end
        if child.name == "report" then
            --A cancellation never clears or replaces the last report.
            child.visible = true
        end
    end

    output_flow.add{
        type = "label",
        name = CANCEL_LABEL_NAME,
        caption = {"hxrrc.calc_canceled"},
        index = 1,
    }
end

function ProgressPanel.on_cancel_clicked(event)
    local element = event and event.element
    if not element then
        return
    end
    local sheet_flow = Sheet().sheet_flow_of(element)
    local player_index = (event and event.player_index) or sheet_flow.player_index
    local sheet_id = Sheet().id_of(sheet_flow)
    if player_index and sheet_id then
        Jobs().cancel(player_index, sheet_id)
    end
    ProgressPanel.hide(sheet_flow)
    mark_canceled(sheet_flow)
end

--Poll all existing sheets without putting GUI objects or functions in storage. The real game invokes this on
--the tenth tick as a fallback; the Jobs.on_tick hook below observes a result in the same tick in which Jobs
--commits it, so a quick job is never held behind a polling frame.
local function refresh_all()
    if not game or not game.players or not storage then
        return
    end
    local sheet = Sheet()
    local jobs = Jobs()
    for player_index, _ in pairs(game.players) do
        local player_storage = storage[player_index]
        local pane = player_storage and player_storage.sheet_section and player_storage.sheet_section.sheet_pane
        for _, tab_and_sheet in ipairs(pane and pane.tabs or {}) do
            local sheet_flow = tab_and_sheet.content
            local progress = jobs.progress_of(player_index, sheet.id_of(sheet_flow))
            if progress then
                ProgressPanel.update(sheet_flow, progress)
            else
                ProgressPanel.hide(sheet_flow)
            end
        end
    end
end

if script and script.on_nth_tick then
    script.on_nth_tick(10, refresh_all)
end

--control.lua owns the on_tick registration and is frozen. Wrap its existing Jobs call so the test harness, which
--fires that handler directly, exercises the same ten-tick refresh without replacing the control handler.
do
    local jobs = Jobs()
    local jobs_on_tick = jobs.on_tick
    if type(jobs_on_tick) == "function" then
        jobs.on_tick = function(event)
            jobs_on_tick(event)
            refresh_all()
        end
    end
end

return ProgressPanel
