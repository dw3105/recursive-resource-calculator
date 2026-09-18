--The export dialog shows a complete debug string safely, reports encoding failure, and leaves its sheet untouched.
local H = require "tests.harness"

local function find(root, predicate)
    if predicate(root) then return root end
    for _, child in ipairs(root.children or {}) do
        local found = find(child, predicate)
        if found then return found end
    end
end

local function count_named(root, name)
    local count = root.name == name and 1 or 0
    for _, child in ipairs(root.children or {}) do
        count = count + count_named(child, name)
    end
    return count
end

local function assert_no_duplicate_sibling_names(root)
    local names = {}
    for _, child in ipairs(root.children or {}) do
        if child.name and child.name ~= "" then
            H.equal(names[child.name], nil, "no duplicate child name under " .. tostring(root.name))
            names[child.name] = true
        end
        assert_no_duplicate_sibling_names(child)
    end
end

local function world_with_export(shape, result)
    local world = H.new_world(shape)
    world.add_item("plate")
    world.add_player(1)
    world.init()
    package.loaded["logic.export_payload"] = {
        build = function(player_index, sheet_flow)
            return {sheet = {state = result.state}, marker = sheet_flow, player_index = player_index}
        end,
        encode = function(_)
            return result.text, result.error
        end,
    }
    local sheet_pane, sheet_flow = H.fill_sheet({})
    local ExportDialog = require "gui.export_dialog"
    return world, sheet_pane, sheet_flow, ExportDialog
end

local function close_button(frame)
    return find(frame, function(element) return element.name == "hxrrc_export_close_button" end)
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " E1 opens with a read-only selectable complete string", function()
        local world, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local frame = ExportDialog.open(1, sheet_flow)
        H.equal(frame ~= nil, true, "dialog opens")
        local box = find(frame, function(element) return element.type == "text-box" end)

        H.equal(frame.name, ExportDialog.FRAME_NAME, "export frame name")
        H.equal(box.text, "debug-string", "whole encoded string")
        H.equal(box.read_only, true, "string is read-only")
        H.equal(box.selectable, true, "string is selectable")
        H.equal(box.word_wrap, true, "string box wraps")
        H.equal(frame.auto_center, true, "frame is centered")
        H.equal(game.players[1].opened, frame, "dialog takes focus")
        H.equal(ExportDialog.is_open(1), true, "dialog is open")
        H.equal(find(frame, function(element) return element.caption == "debug-string" end), nil, "no duplicate string label")

        event_handlers.on_gui_click.hxrrc_export_select_all_button({element = find(frame, function(element)
            return element.name == "hxrrc_export_select_all_button"
        end), player_index = 1})
        H.equal(H.text_selected(box), true, "Select all marks the whole text")
        H.equal(H.text_focused(box), true, "Select all focuses the text")
        H.equal(world.flying_texts[1], nil, "no unrelated UI output")
    end)

    H.test(shape .. " E2 Close destroys the frame and clears dialog state", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local frame = ExportDialog.open(1, sheet_flow)
        H.equal(frame ~= nil, true, "dialog opens")
        event_handlers.on_gui_click.hxrrc_export_close_button({element = close_button(frame), player_index = 1})

        H.equal(frame.valid, false, "Close destroys the frame")
        H.equal(ExportDialog.is_open(1), false, "closed dialog is not open")
        H.equal(storage[1].export_dialog, nil, "Close clears dialog state")
    end)

    H.test(shape .. " E3 opening twice keeps one frame", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local first = ExportDialog.open(1, sheet_flow)
        H.equal(first ~= nil, true, "first open builds a frame")
        local second = ExportDialog.open(1, sheet_flow)

        H.equal(second, first, "second open reuses the existing frame")
        H.equal(count_named(game.players[1].gui.screen, ExportDialog.FRAME_NAME), 1, "only one export frame exists")
    end)

    H.test(shape .. " E4 an encoding failure shows the failure and no text box", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "failed", text = "truncated", error = "encode failed"})
        local frame = ExportDialog.open(1, sheet_flow)
        H.equal(frame ~= nil, true, "failure still opens a dialog")

        H.equal(find(frame, function(element) return element.type == "text-box" end), nil, "failure has no text box")
        local failure = find(frame, function(element)
            return type(element.caption) == "table" and element.caption[1] == "hxrrc.export_encoding_failed"
        end)
        H.equal(failure ~= nil, true, "failure message is shown")
    end)

    H.test(shape .. " E5 opening and closing leaves report and controls untouched", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local report = sheet_flow.output_flow.add{type = "label", name = "existing_report", caption = "report"}
        local checkbox = sheet_flow.hxrrc_sheet_controls.round_up_cell.hxrrc_round_up_machines_checkbox
        local controls_before = {state = checkbox.state, report = report, report_text = report.caption}

        local frame = ExportDialog.open(1, sheet_flow)
        H.equal(frame ~= nil, true, "dialog opens")
        H.equal(sheet_flow.output_flow.children[1], controls_before.report, "opening does not rebuild report")
        H.equal(checkbox.state, controls_before.state, "opening does not change controls")
        ExportDialog.close(1)

        H.equal(sheet_flow.output_flow.children[1], controls_before.report, "closing does not rebuild report")
        H.equal(report.valid, true, "closing leaves report valid")
        H.equal(report.caption, controls_before.report_text, "closing leaves report text")
        H.equal(checkbox.state, controls_before.state, "closing leaves controls unchanged")
        H.equal(frame.valid, false, "only the dialog frame was destroyed")
    end)

    H.test(shape .. " E6 state label follows each supplied snapshot state", function()
        for _, state in ipairs({"not_computed", "current", "pending", "stale", "failed"}) do
            local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = state, text = "debug-string"})
            local frame = ExportDialog.open(1, sheet_flow)
            H.equal(frame ~= nil, true, "dialog opens for " .. state)
            local label = find(frame, function(element) return element.name == "hxrrc_export_state" end)
            H.equal(label.caption[1], "hxrrc.export_state_" .. state, state .. " state label")
            ExportDialog.close(1)
        end
    end)

    H.test(shape .. " E7 sheet deletion and player removal leave no dialog state", function()
        local world, sheet_pane, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local frame = ExportDialog.open(1, sheet_flow)
        H.equal(frame ~= nil, true, "dialog opens")
        require("gui.sheet").new(sheet_pane)
        sheet_pane.selected_tab_index = 1
        require("gui.sheet").delete_selected_sheet(sheet_pane)
        H.equal(ExportDialog.is_open(1), false, "deleted sheet closes its dialog")
        H.equal(frame.valid, false, "deleted sheet destroys its dialog")

        frame = ExportDialog.open(1, sheet_pane.tabs[1].content)
        storage[1] = nil --the control handler does this after the player has gone away
        H.equal(ExportDialog.is_open(1), false, "removed player has no dialog")
        H.equal(frame.valid, false, "removed player has no dialog frame")
    end)

    H.test(shape .. " E8 every dialog parent has unique child names", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local frame = ExportDialog.open(1, sheet_flow)
        H.equal(frame ~= nil, true, "dialog opens")
        assert_no_duplicate_sibling_names(frame)
    end)
end

H.done("test_export_dialog")
