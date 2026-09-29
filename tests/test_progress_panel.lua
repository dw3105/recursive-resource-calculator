--The progress panel shows honest phase progress, keeps the calculator usable, and cancels without replacing its report.
local H = require "tests.harness"

local function panel_world(shape)
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate")
    world.add_machine({name = "furnace", categories = {"smelting"}, speed = 1})
    world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}},
        products = {{name = "plate", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    local sheet_flow = storage[1].sheet_section.sheet_pane.tabs[1].content
    return world, sheet_flow, game.players[1].gui.screen.hxrrc_calculator
end

local function child_named(parent, name)
    for _, child in ipairs(parent.children) do
        if child.name == name then return child end
    end
end

local function assert_safe_update(ProgressPanel, sheet_flow, bar, progress, label)
    H.equal(bar ~= nil, true, label .. ": the progress bar exists")
    local ok = pcall(function()
        ProgressPanel.update(sheet_flow, progress)
    end)
    H.equal(ok, true, label .. ": update does not raise")
    H.equal(bar.value ~= nil, true, label .. ": the bar writes a value")
    H.equal(type(bar.value), "number", label .. ": the value is numeric")
    H.equal(bar.value >= 0 and bar.value <= 1, true, label .. ": the value stays in range")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PP-01 controls stay hidden until work starts and appear together", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local Sheet = require "gui.sheet"
        local bar, cancel = Sheet.progressbar_of(sheet_flow), Sheet.cancel_button_of(sheet_flow)

        H.equal(bar.visible, false, "the bar is hidden while idle")
        H.equal(cancel.visible, false, "Cancel is hidden while idle")
        ProgressPanel.show(sheet_flow)
        H.equal(bar.visible, true, "the bar appears when work starts")
        H.equal(cancel.visible, true, "Cancel appears with the bar")
        H.equal(child_named(sheet_flow, "hxrrc_progress_status") ~= nil, true, "status appears with the controls")
        ProgressPanel.hide(sheet_flow)
        H.equal(bar.visible, false, "hiding work hides the bar")
        H.equal(cancel.visible, false, "hiding work hides Cancel")
        H.equal(child_named(sheet_flow, "hxrrc_progress_status"), nil, "hiding work removes status")
    end)

    H.test(shape .. " PP-02 caption names the phase and known totals are completed work over total", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        ProgressPanel.update(sheet_flow, {phase = "expanding", done_units = 3, total_units = 10})
        H.deep_equal(bar.caption[1], "hxrrc.progress_bar_percent", "bar caption is percent only")
        H.deep_equal(bar.caption[2], 30, "bar caption shows the percentage")
        H.near(bar.value, 0.3, "the bar is done over total")
        H.equal(bar.tooltip[1], "hxrrc.progress_tooltip", "the tooltip gives elapsed and estimated time")
    end)

    H.test(shape .. " PP-03 unknown totals rise with an explicit estimate and never fabricate a countdown", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        ProgressPanel.update(sheet_flow, {phase = "reading", done_units = 1, total_units = nil})
        local first = bar.value
        ProgressPanel.update(sheet_flow, {phase = "reading", done_units = 3, total_units = nil})
        H.equal(bar.value > first, true, "unknown-total progress rises")
        H.equal(bar.value < 1, true, "unknown-total progress stays below one")
        H.equal(bar.tooltip[1], "hxrrc.progress_tooltip", "tooltip shows timing even when no ETA is known")
        H.equal(bar.tooltip[3], "?", "unknown progress has no fabricated ETA")
    end)

    H.test(shape .. " PP-04 the bar stays below one until completion is reported", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        ProgressPanel.update(sheet_flow, {phase = "report", done_units = 0, total_units = 10})
        H.equal(bar.value < 1, true, "the last phase beginning is not completion")
        ProgressPanel.update(sheet_flow, {phase = "report", done_units = 10, total_units = 10})
        H.equal(bar.value, 1, "one is reserved for the completed update")
    end)

    H.test(shape .. " PP-05 cancel hides controls, calls Jobs, and labels the old report", function()
        local _, sheet_flow, calculator = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local Sheet = require "gui.sheet"
        local Jobs = require "logic.jobs"
        local canceled = {}
        Jobs.cancel = function(player_index, sheet_id)
            canceled = {player_index, sheet_id}
        end
        local old_report = sheet_flow.output_flow.add{type = "label", name = "old_report", caption = "old report"}
        ProgressPanel.show(sheet_flow)
        ProgressPanel.on_cancel_clicked({element = Sheet.cancel_button_of(sheet_flow), player_index = 1})

        H.equal(canceled[1], 1, "Cancel names the player")
        H.equal(canceled[2], Sheet.id_of(sheet_flow), "Cancel names the sheet")
        H.equal(Sheet.progressbar_of(sheet_flow).visible, false, "Cancel hides the bar")
        H.equal(Sheet.cancel_button_of(sheet_flow).visible, false, "Cancel hides itself")
        H.equal(old_report.valid, true, "the old report remains on screen")
        H.equal(old_report.caption, "old report", "the old report is not replaced")
        local note = child_named(sheet_flow, "hxrrc_job_note")
        H.equal(note ~= nil, true, "cancellation note is a separate sheet child")
        H.equal(note.children[1].caption[1], "hxrrc.calc_canceled", "the note explains cancellation")
        H.equal(note:get_index_in_parent(), sheet_flow.output_flow:get_index_in_parent() - 1,
            "the note sits immediately above the output")
        H.equal(child_named(sheet_flow.output_flow, "hxrrc_calc_canceled_label"), nil, "the note is outside the output")
        H.equal(calculator.enabled, true, "Cancel never disables the calculator")
    end)

    H.test(shape .. " PP-06 refreshes from Jobs on the tenth tick without delaying completion", function()
        local world, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local Jobs = require "logic.jobs"
        local sheet_id = require("gui.sheet").id_of(sheet_flow)
        storage[1].calc_jobs = {[sheet_id] = {kind="calculation", sheet_id=sheet_id, started_tick=0, done=false,
            phase="solve", progress={stage="solve", stage_done=20, stage_total=100}}}
        ProgressPanel.show(sheet_flow)
        --Keep the persisted sample stationary; this case isolates the registered tenth-tick fallback.
        world.handlers.events[defines.events.on_tick] = nil
        H.run_ticks(world, 10)
        H.near(require("gui.sheet").progressbar_of(sheet_flow).value, 0.2, "the refresh reads the saved job record")
        storage[1].calc_jobs = nil
        H.run_ticks(world, 10)
        H.equal(require("gui.sheet").progressbar_of(sheet_flow).visible, false, "a same-tick completion hides the controls")
    end)

    H.test(shape .. " PP-07 a sheet missing round 8 cells is left alone without error", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local controls = sheet_flow.hxrrc_sheet_controls
        controls.progress_cell.destroy()
        controls.cancel_cell.destroy()
        local ok = pcall(function()
            ProgressPanel.show(sheet_flow)
            ProgressPanel.hide(sheet_flow)
            ProgressPanel.update(sheet_flow, {phase = "reading", done_units = 1, total_units = 2})
        end)
        H.equal(ok, true, "missing round 8 controls do not crash the panel")
    end)

    H.test(shape .. " PP-08 negative done units keep the bar nonnegative", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        assert_safe_update(ProgressPanel, sheet_flow, bar,
            {phase = "reading", done_units = -3, total_units = 10}, "negative done units")
    end)

    H.test(shape .. " PP-09 negative total units do not escape the bar range", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        assert_safe_update(ProgressPanel, sheet_flow, bar,
            {phase = "reading", done_units = 3, total_units = -10}, "negative total units")
    end)

    H.test(shape .. " PP-10 done units above total stay capped at one", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        assert_safe_update(ProgressPanel, sheet_flow, bar,
            {phase = "reading", done_units = 12, total_units = 5}, "done above total")
    end)

    H.test(shape .. " PP-11 nonnumeric done units do not raise", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        assert_safe_update(ProgressPanel, sheet_flow, bar,
            {phase = "reading", done_units = "many", total_units = 10}, "nonnumeric done units")
    end)

    H.test(shape .. " PP-12 NaN done units do not raise", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        assert_safe_update(ProgressPanel, sheet_flow, bar,
            {phase = "reading", done_units = 0 / 0, total_units = 10}, "NaN done units")
    end)

    H.test(shape .. " PP-13 infinite done units do not raise", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        assert_safe_update(ProgressPanel, sheet_flow, bar,
            {phase = "reading", done_units = math.huge, total_units = 10}, "infinite done units")
    end)

    H.test(shape .. " PP-14 progress in one phase never moves backwards", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        assert_safe_update(ProgressPanel, sheet_flow, bar,
            {phase = "solving", done_units = 8, total_units = 10}, "first phase update")
        local first = bar.value
        local ok = pcall(function()
            ProgressPanel.update(sheet_flow, {phase = "solving", done_units = 3, total_units = 10})
        end)
        H.equal(ok, true, "a backwards report does not raise")
        H.equal(bar.value ~= nil, true, "the second update leaves a value")
        H.equal(bar.value >= first, true, "the bar does not move backwards")
        H.equal(bar.value, first, "the prior phase value is retained")
    end)

    H.test(shape .. " PP-15 caption, best-so-far and note are visible in the sheet flow", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        ProgressPanel.update(sheet_flow, {kind="blueprint", stage_key="pack", attempt=2, attempts=3, fraction=.42,
            elapsed_ticks=600, eta_ticks=300, best_entities=57})
        local bar=require("gui.sheet").progressbar_of(sheet_flow)
        H.equal(bar.caption[1], "hxrrc.progress_bar_percent", "bar uses the percentage key")
        H.equal(child_named(sheet_flow, "hxrrc_progress_status").caption[1], "hxrrc.progress_status", "status names current stage")
        H.equal(child_named(sheet_flow, "hxrrc_progress_status").caption[5][1], "hxrrc.progress_stage_pack", "status names current stage")
        ProgressPanel.set_best(sheet_flow, 57)
        H.equal(child_named(sheet_flow, "hxrrc_progress_best").caption[1], "hxrrc.progress_best", "best-so-far has its own line")
        ProgressPanel.set_note(sheet_flow, {"hxrrc.calc_canceled"})
        H.equal(child_named(sheet_flow, "hxrrc_job_note") ~= nil, true, "note is a child of the sheet")
        H.equal(child_named(sheet_flow.output_flow, "hxrrc_job_note"), nil, "note never enters output flow")
    end)

    H.test(shape .. " PP-16 calc starts preserve blueprint notes and blueprint starts clear them", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        ProgressPanel.set_note(sheet_flow, {"hxrrc.blueprint_stopped_update"})
        local note = child_named(sheet_flow, "hxrrc_job_note")
        H.equal(note.tags.kind, "blueprint", "blueprint caption stores its kind on the note flow")
        ProgressPanel.show(sheet_flow, "calc")
        H.equal(child_named(sheet_flow, "hxrrc_job_note"), note, "calc start leaves blueprint note visible")
        ProgressPanel.show(sheet_flow, "blueprint")
        H.equal(child_named(sheet_flow, "hxrrc_job_note"), nil, "blueprint start clears blueprint note")
        ProgressPanel.set_note(sheet_flow, {"hxrrc.calc_canceled"})
        note = child_named(sheet_flow, "hxrrc_job_note")
        H.equal(note.tags.kind, "calc", "other captions are tagged calc")
    end)
    --PP-17 red before round 46 (2026-09-28): the tenth-tick poll swept every idle sheet every time, and the sweep walks
    --the whole sheet GUI tree (destroy_legacy_notes). Headless 2.0.77 on the player's save SA_D0: a script spike of
    --8.7-9.4 ms every 10 ticks vs 1.0 ms without the mod. An idle sheet is swept once, until work shows again.
    H.test(shape .. " PP-17 an idle sheet is swept once, not on every tenth tick, and again after work ends", function()
        local world, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local sheet_id = require("gui.sheet").id_of(sheet_flow)
        world.handlers.events[defines.events.on_tick] = nil
        local raw, sweeps = ProgressPanel.sweep, 0
        ProgressPanel.sweep = function(...) sweeps = sweeps + 1; return raw(...) end
        H.run_ticks(world, 30)
        H.equal(sweeps, 1, "three idle polls sweep the idle sheet once")
        storage[1].calc_jobs = {[sheet_id] = {kind="calculation", sheet_id=sheet_id, started_tick=0, done=false,
            phase="solve", progress={stage="solve", stage_done=20, stage_total=100}}}
        H.run_ticks(world, 10)
        H.equal(require("gui.sheet").progressbar_of(sheet_flow).visible, true, "running work shows the bar")
        storage[1].calc_jobs = nil
        H.run_ticks(world, 30)
        H.equal(sweeps, 2, "the first idle poll after work sweeps once more, later polls do not")
        H.equal(require("gui.sheet").progressbar_of(sheet_flow).visible, false, "the bar is hidden after work ends")
        ProgressPanel.sweep = raw
    end)
    H.test(shape .. " PP-18 a stale visible bar with a swept mark and no job is hidden by the next idle poll", function()
        --Player save _autosave1 (1.1.105, legalcopilot-dev headless 2026-09-29): no job stored, both sheets'
        --bars visible at 0.9 and 0.9864, progress_swept true for both, so the poll never looked at them again.
        local world, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local Sheet = require "gui.sheet"
        local sheet_id = Sheet.id_of(sheet_flow)
        world.handlers.events[defines.events.on_tick] = nil
        H.run_ticks(world, 10)
        ProgressPanel.show(sheet_flow, "blueprint")
        Sheet.progressbar_of(sheet_flow).value = 0.9864
        storage[1].progress_swept = {[sheet_id] = true}
        storage[1].calc_jobs, storage[1].blueprint_job = nil, nil
        H.equal(Sheet.progressbar_of(sheet_flow).visible, true, "stale bar visible before the poll")
        H.run_ticks(world, 10)
        H.equal(Sheet.progressbar_of(sheet_flow).visible, false, "the idle poll hides a stale visible bar")
        H.equal(Sheet.cancel_button_of(sheet_flow).visible, false, "and its cancel button")
        io.write("PP-18\n")
    end)
end

H.done("test_progress_panel")
