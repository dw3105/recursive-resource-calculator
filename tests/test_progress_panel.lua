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
        ProgressPanel.hide(sheet_flow)
        H.equal(bar.visible, false, "hiding work hides the bar")
        H.equal(cancel.visible, false, "hiding work hides Cancel")
    end)

    H.test(shape .. " PP-02 caption names the phase and known totals are completed work over total", function()
        local _, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local bar = require("gui.sheet").progressbar_of(sheet_flow)
        ProgressPanel.update(sheet_flow, {phase = "expanding", done_units = 3, total_units = 10})
        H.deep_equal(bar.caption, {"hxrrc.calc_phase_expanding"}, "the caption is the phase locale key")
        H.near(bar.value, 0.3, "the bar is done over total")
        H.deep_equal(bar.tooltip, {"hxrrc.calc_progress_tooltip", {"hxrrc.calc_phase_expanding"}, 3, 10}, "the tooltip has phase, done and total")
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
        H.equal(bar.tooltip[4], "?", "unknown total is shown as unknown")
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
        H.equal(child_named(sheet_flow.output_flow, "hxrrc_calc_canceled_label").caption[1], "hxrrc.calc_canceled", "the report is labeled canceled")
        H.equal(calculator.enabled, true, "Cancel never disables the calculator")
    end)

    H.test(shape .. " PP-06 refreshes from Jobs on the tenth tick without delaying completion", function()
        local world, sheet_flow = panel_world(shape)
        local ProgressPanel = require "gui.progress_panel"
        local Jobs = require "logic.jobs"
        local progress = {phase = "solving", done_units = 2, total_units = 10}
        local reads = 0
        Jobs.progress_of = function(player_index, sheet_id)
            reads = reads + 1
            return progress
        end
        ProgressPanel.show(sheet_flow)
        H.run_ticks(world, 9)
        H.equal(reads > 0, true, "the panel polls while work runs")
        H.run_ticks(world, 1)
        H.equal(reads >= 10, true, "the panel refreshes at least every ten ticks")
        H.near(require("gui.sheet").progressbar_of(sheet_flow).value, 0.2, "the tick refresh uses current progress")
        progress = nil
        H.run_ticks(world, 1)
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
end

H.done("test_progress_panel")
