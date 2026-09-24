--The progress bar and Cancel button on a sheet.
--
--Owned by lane W1-progress. The bar shows real work: a phase name a player can read and a fraction that stays
--below 1 until a complete result is committed. Nothing invents a countdown while the dependency graph is still
--growing.
--
--The calculator window is never disabled while work runs, because the controls that stop that work live inside
--it. Cancel stops within two ticks of its handler and leaves the previous report visible and marked canceled.
local Registry = require "logic.registry"
local ProgressView = require "logic.progress_view"

local ProgressPanel = {}

local UNKNOWN_TOTAL_ESTIMATE = 100
local NOTE_NAME = "hxrrc_job_note"
local LAST_PHASE_TAG = "hxrrc_progress_phase"
local LAST_VALUE_TAG = "hxrrc_progress_value"
local OFFER_NAME = "hxrrc_better_layout_offer"
local OFFER_BUTTON = "hxrrc_deliver_better_layout"
local BEST_NAME = "hxrrc_progress_best"
local refreshed_tick, last_game_tick, refresh_sequence

--Sheet requires this module to install its handlers, so the edge back is late: Factorio refuses require inside a
--handler, and both modules load while control.lua is parsed.
local function Sheet()
    return Registry.need("sheet")
end

local function Jobs()
    return Registry.need("jobs")
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

local function reset_progress_tracking(bar)
    local tags = bar.tags or {}
    tags[LAST_PHASE_TAG] = nil
    tags[LAST_VALUE_TAG] = nil
    bar.tags = tags
end

local function nondecreasing_value(bar, key, value)
    local tags = bar.tags or {}
    local previous_phase = tags[LAST_PHASE_TAG]
    local previous_value = tags[LAST_VALUE_TAG]
    if previous_phase == key and type(previous_value) == "number" then
        value = math.max(previous_value, value)
    end
    tags[LAST_PHASE_TAG] = key
    tags[LAST_VALUE_TAG] = value
    bar.tags = tags
    return value
end

function ProgressPanel.show(sheet_flow)
    local bar, cancel = controls_of(sheet_flow)
    if not bar or not cancel or bar.valid == false or cancel.valid == false then
        return
    end
    bar.visible = true
    cancel.visible = true
    ProgressPanel.set_note(sheet_flow, nil)
end

function ProgressPanel.hide(sheet_flow)
    local bar, cancel = controls_of(sheet_flow)
    if not bar or not cancel or bar.valid == false or cancel.valid == false then
        return
    end
    reset_progress_tracking(bar)
    bar.visible = false
    cancel.visible = false
end

--progress: {phase = locale key suffix, done_units, total_units | nil}
local function clock_text(ticks)
    local seconds = math.floor((ticks or 0) / 60)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function ProgressPanel.update(sheet_flow, progress, job_id, interim)
    if not progress then
        return
    end
    local bar, cancel = controls_of(sheet_flow)
    if not bar or not cancel or bar.valid == false or cancel.valid == false then
        return
    end

    local key = "hxrrc.progress_stage_" .. tostring(progress.stage_key or progress.phase or "prepare")
    local value = progress.fraction
    if type(value) ~= "number" then value = progress_value(progress) end
    value = nondecreasing_value(bar, key, value)
    local percent = math.floor(value * 100)
    local caption_sig = table.concat({progress.kind or "calc", progress.attempt or 1, progress.attempts or 1, key, percent}, "|")
    local tags = bar.tags or {}
    if tags.hxrrc_progress_caption_sig ~= caption_sig then
        bar.caption = {"hxrrc.progress_caption", {"hxrrc.progress_kind_" .. (progress.kind or "calc")}, progress.attempt or 1, progress.attempts or 1, {key}, percent}
        tags.hxrrc_progress_caption_sig = caption_sig
    end
    local eta = progress.eta_ticks and clock_text(progress.eta_ticks) or "?"
    local tooltip = {"hxrrc.progress_tooltip", clock_text(progress.elapsed_ticks or 0), eta}
    local tooltip_sig = tostring(progress.elapsed_ticks or 0) .. "|" .. tostring(progress.eta_ticks or "?")
    if tags.hxrrc_progress_tooltip_sig ~= tooltip_sig then bar.tooltip = tooltip; tags.hxrrc_progress_tooltip_sig = tooltip_sig end
    bar.tags = tags
    if bar.value ~= value then bar.value = value end
    ProgressPanel.show(sheet_flow)
    ProgressPanel.set_offer(sheet_flow, job_id, interim)
end

function ProgressPanel.set_note(sheet_flow, caption)
    if not sheet_flow or sheet_flow.valid == false then return end
    local note
    for _, child in ipairs(sheet_flow.children or {}) do if child.name == NOTE_NAME then note = child; break end end
    if not caption then if note then note.destroy() end; return end
    if not note then note = sheet_flow.add{type="flow", name=NOTE_NAME, direction="vertical", index=sheet_flow.output_flow and sheet_flow.output_flow.get_index_in_parent() or #sheet_flow.children+1}; note.add{type="label", name="hxrrc_job_note_label"} end
    note.children[1].caption = caption
    note.children[1].style.single_line = false
end

local function output_flow_of(sheet_flow)
    for _, child in ipairs(sheet_flow and sheet_flow.children or {}) do
        if child.name == "output_flow" then
            return child
        end
    end
end

function ProgressPanel.set_offer(sheet_flow, job_id, interim)
    local flow = output_flow_of(sheet_flow)
    if not flow or flow.valid == false then return end
    local offer
    for _, child in ipairs(flow.children or {}) do
        if child.name == OFFER_NAME then offer = child; break end
    end
    if not interim then
        if offer then offer.destroy() end
        return
    end
    if not offer then
        offer = flow.add{type = "flow", name = OFFER_NAME, direction = "horizontal"}
        offer.add{type = "label", name = "hxrrc_better_layout_label"}
        offer.add{type = "button", name = OFFER_BUTTON, caption = {"hxrrc.deliver_better_layout"}}
    end
    offer.children[1].caption = {"hxrrc.better_layout_found", interim.entities}
    offer.children[2].tags = {job_id = job_id, sequence = interim.sequence}
end

function ProgressPanel.set_best(sheet_flow, entities)
    local label
    for _, child in ipairs(sheet_flow.children or {}) do if child.name == BEST_NAME then label=child; break end end
    if not entities then if label then label.destroy() end; return end
    if not label then label=sheet_flow.add{type="label", name=BEST_NAME, index=sheet_flow.output_flow and sheet_flow.output_flow.get_index_in_parent() or #sheet_flow.children+1} end
    if label.tags and label.tags.entities == entities then return end
    label.caption={"hxrrc.progress_best", entities}
    label.tags={entities=entities}
end

local function deliver_offer(event)
    local tags = event and event.element and event.element.tags or {}
    local generation = Registry.generation
    if generation and tags.job_id and tags.sequence then
        generation.deliver_interim(event.player_index, tags.job_id, tags.sequence)
    end
end
if event_handlers and event_handlers.on_gui_click then
    event_handlers.on_gui_click[OFFER_BUTTON] = deliver_offer
end

local function mark_canceled(sheet_flow)
    ProgressPanel.set_note(sheet_flow, {"hxrrc.calc_canceled"})
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
    ProgressPanel.set_best(sheet_flow, nil)
    ProgressPanel.set_offer(sheet_flow, nil, nil)
    mark_canceled(sheet_flow)
end

--Poll all existing sheets without putting GUI objects or functions in storage. The real game invokes this on
--the tenth tick as a fallback; the Jobs.on_tick hook below observes a result in the same tick in which Jobs
--commits it, so a quick job is never held behind a polling frame.
local function refresh_all()
    if not game or not game.players or not storage then
        return
    end
    local observed=game.tick
    if observed ~= last_game_tick then
        refresh_sequence=finite_nonnegative_integer(observed)
        last_game_tick=observed
    else
        refresh_sequence=(refresh_sequence or 0)+1
    end
    local tick=refresh_sequence or observed or 0
    if tick % 10 ~= 0 then
        --Jobs.on_tick still calls the registry hook in this branch. Keep that path cheap: only settle controls
        --for a job that finished between tenth-tick refreshes; live progress is read and written every ten ticks.
        local sheet = Sheet()
        for player_index, _ in pairs(game.players) do
            local data=storage[player_index]
            local pane=data and data.sheet_section and data.sheet_section.sheet_pane
            for _, tab in ipairs(pane and pane.tabs or {}) do
                local flow=tab.content
                if flow and Sheet().progressbar_of(flow) and Sheet().progressbar_of(flow).visible then
                    local sid=sheet.id_of(flow)
                    if not ProgressView.of(player_index,sid) then
                        ProgressPanel.hide(flow)
                        ProgressPanel.set_best(flow,nil)
                        ProgressPanel.set_offer(flow,nil,nil)
                    end
                end
            end
        end
        return
    end
    if refreshed_tick == tick then return end
    refreshed_tick = tick
    local sheet = Sheet()
    local jobs = Jobs()
    for player_index, _ in pairs(game.players) do
        local player_storage = storage[player_index]
        local pane = player_storage and player_storage.sheet_section and player_storage.sheet_section.sheet_pane
        for _, tab_and_sheet in ipairs(pane and pane.tabs or {}) do
            local sheet_flow = tab_and_sheet.content
            local sheet_id = sheet.id_of(sheet_flow)
            local progress = ProgressView.of(player_index, sheet_id)
            if progress then
                local data = storage[player_index]
                local job = data and data.blueprint_job
                local id = job and job.sheet_id == sheet_id and job.state and job.state.input
                    and job.state.input.generation_job_id
                local status = id and Registry.generation and Registry.generation.status(player_index, id)
                ProgressPanel.update(sheet_flow, progress, id, status and status.interim)
                local best = (job and job.progress and job.progress.best_entities) or (status and status.interim and status.interim.entities)
                if best then ProgressPanel.set_best(sheet_flow, best) else ProgressPanel.set_best(sheet_flow, nil) end
                ProgressPanel.set_note(sheet_flow, nil)
            else
                local attempt = Registry.generation and Registry.generation.lookup(player_index, sheet_id)
                local pending = attempt and attempt.state == "pending"
                ProgressPanel.set_offer(sheet_flow, pending and attempt.job_id, pending and attempt.interim)
                ProgressPanel.hide(sheet_flow)
                ProgressPanel.set_best(sheet_flow, nil)
            end
        end
    end
end

if script and script.on_nth_tick then
    script.on_nth_tick(10, refresh_all)
end

--control.lua owns the on_tick registration and is frozen, so the bar rides on Jobs.on_tick. The callback is
--published rather than wrapped: wrapping needed logic.jobs while this module was still loading, and the load
--order of two modules that need each other is never fixed.
Registry.progress_refresh = refresh_all
Registry.progress_note = function(player_index, sheet_id, caption)
    local data = storage and storage[player_index]
    local pane = data and data.sheet_section and data.sheet_section.sheet_pane
    for _, tab in ipairs(pane and pane.tabs or {}) do if Sheet().id_of(tab.content)==sheet_id then ProgressPanel.set_note(tab.content, caption); return true end end
    return false
end

return ProgressPanel
