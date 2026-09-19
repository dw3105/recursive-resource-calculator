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

local function select_all_button(frame)
    return find(frame, function(element) return element.name == "hxrrc_export_select_all_button" end)
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

        H.equal(H.text_selected(box), true, "opening selects the whole text")
        H.equal(H.text_focused(box), true, "opening focuses the text")
        H.equal(find(frame, function(element) return element.name == "hxrrc_export_copy_button" end), nil,
            "no button claims to copy: a mod cannot write text to the system clipboard")
        H.equal(#world.flying_texts, 0, "nothing draws itself over the window")
    end)

    H.test(shape .. " E2 Esc destroys the frame and clears dialog state", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local frame = ExportDialog.open(1, sheet_flow)
        H.equal(frame ~= nil, true, "dialog opens")
        --Esc is what closes this window now: the engine clears player.opened, and the module treats that as closed.
        game.players[1].opened = nil
        ExportDialog.close(1)

        H.equal(frame.valid, false, "Esc destroys the frame")
        H.equal(ExportDialog.is_open(1), false, "closed dialog is not open")
        H.equal(storage[1].export_dialog, nil, "closing clears dialog state")
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

    H.test(shape .. " E9 layout keeps the whole encoded payload in a readable box", function()
        local payload = {
            format = "rrc-sheet-debug",
            schema_version = 1,
            note = string.rep("whole-payload-", 40),
        }
        local encoded = helpers.encode_string(helpers.table_to_json(payload))
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = encoded})
        local frame = ExportDialog.open(1, sheet_flow)
        local box = find(frame, function(element) return element.type == "text-box" end)

        H.equal(box ~= nil, true, "successful export has a text box")
        H.equal(box.text:gsub("%s", ""), encoded, "text box carries the whole encoded string")
        local decoded = assert(H.decode_export(box.text))
        H.equal(decoded.format, payload.format, "text box payload decodes")
        H.equal(decoded.note, payload.note, "decoded payload is not clipped")
        H.equal(box.style.width, 600, "text box has a readable width")
        H.equal(box.style.height, 240, "text box has a readable height")
        H.equal(frame.style.minimal_width, 600, "frame has a readable minimum width")
    end)

    H.test(shape .. " E10 failed export keeps its labels and has no text box", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "failed", error = "encode failed"})
        local frame = ExportDialog.open(1, sheet_flow)
        local state = find(frame, function(element) return element.name == "hxrrc_export_state" end)
        local failure = find(frame, function(element)
            return type(element.caption) == "table" and element.caption[1] == "hxrrc.export_encoding_failed"
        end)

        H.equal(state ~= nil, true, "failed dialog has a state label")
        H.equal(frame.style.minimal_width, 600, "failed dialog keeps the readable frame width")
        H.equal(state.caption[1], "hxrrc.export_state_failed", "failed dialog keeps the state label")
        H.equal(failure ~= nil, true, "failed dialog keeps the failure label")
        H.equal(find(frame, function(element) return element.type == "text-box" end), nil,
            "failed dialog has no text box")
    end)

    H.test(shape .. " E11 opens with the whole string selected and focused", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local frame = ExportDialog.open(1, sheet_flow)
        local box = find(frame, function(element) return element.type == "text-box" end)

        H.equal(H.text_selected(box), true, "opening selects the whole string")
        H.equal(H.text_focused(box), true, "opening focuses the string")
    end)

    H.test(shape .. " E12 wraps the displayed string and still decodes", function()
        local payload = {
            format = "rrc-sheet-debug",
            schema_version = 1,
            note = string.rep("long-payload-", 100),
        }
        local encoded = helpers.encode_string(helpers.table_to_json(payload))
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = encoded})
        local frame = ExportDialog.open(1, sheet_flow)
        local box = find(frame, function(element) return element.type == "text-box" end)

        H.equal(box.text:find("\n", 1, true) ~= nil, true, "long encoded text has display line breaks")
        H.equal(box.text:gsub("%s", ""), encoded, "display line breaks do not change the payload")
        local decoded = assert(H.decode_export(box.text))
        H.equal(decoded.format, payload.format, "wrapped text decodes")
        H.equal(decoded.note, payload.note, "wrapped text keeps the complete payload")
    end)

    H.test(shape .. " E13 one button selects, and nothing pretends to copy", function()
        local world, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "current", text = "debug-string"})
        local frame = ExportDialog.open(1, sheet_flow)
        local box = find(frame, function(element) return element.type == "text-box" end)

        H.equal(find(frame, function(element) return element.name == "hxrrc_export_copy_button" end), nil,
            "no Copy button: LuaPlayer.add_to_clipboard takes a blueprint stack, never text")
        local select_all = select_all_button(frame)
        H.equal(select_all ~= nil, true, "Select all is present")
        event_handlers.on_gui_click.hxrrc_export_select_all_button({element = select_all, player_index = 1})
        H.equal(H.text_selected(box), true, "Select all marks the whole string again")
        H.equal(select_all_button(frame) ~= nil, true, "Select all is the one button")
        H.equal(find(frame, function(element) return element.name == "hxrrc_export_close_button" end), nil,
            "no Close button: Esc closes the window")
        H.equal(H.text_selected(box), true, "the string is already selected, so CTRL + C works at once")
        H.equal(H.text_focused(box), true, "and the box already holds the focus")
        H.equal(#world.flying_texts, 0, "nothing draws itself over the window")
    end)

    H.test(shape .. " E14 keeps the state line and explanation", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "not_computed", text = "debug-string"})
        local frame = ExportDialog.open(1, sheet_flow)
        local state = find(frame, function(element) return element.name == "hxrrc_export_state" end)
        local explanation = find(frame, function(element) return element.name == "hxrrc_export_explanation" end)

        H.equal(state.caption[1], "hxrrc.export_state_not_computed", "state line is still shown")
        H.equal(explanation.caption[1], "hxrrc.export_explanation", "explanation is still shown")
    end)

    H.test(shape .. " E15 failure keeps the failure label and has no text box", function()
        local _, _, sheet_flow, ExportDialog = world_with_export(shape, {state = "failed", error = "encode failed"})
        local frame = ExportDialog.open(1, sheet_flow)
        local failure = find(frame, function(element)
            return type(element.caption) == "table" and element.caption[1] == "hxrrc.export_encoding_failed"
        end)

        H.equal(failure ~= nil, true, "failure label is still shown")
        H.equal(find(frame, function(element) return element.type == "text-box" end), nil,
            "failure still has no text box")
    end)
end

H.done("test_export_dialog")
