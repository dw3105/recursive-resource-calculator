--The window that shows the debug string.
--
--Owned by lane W1-exportui. A scrollable, selectable, read-only text box with Select all and Close, an
--explanation that says the string is not a blueprint, and a message when encoding failed. It reads the sheet and
--changes nothing on it; opening or closing it leaves the report exactly as it was.
local ExportPayload = require "logic.export_payload"

local ExportDialog = {}

ExportDialog.FRAME_NAME = "hxrrc_export_dialog"
local SCROLL_NAME = "hxrrc_export_scroll"
local TEXT_NAME = "hxrrc_export_text"
local STATE_NAME = "hxrrc_export_state"
local SELECT_ALL_NAME = "hxrrc_export_select_all_button"
local CLOSE_NAME = "hxrrc_export_close_button"

--GUI handles are deliberately kept out of storage. This is only a runtime aid for noticing that the sheet which
--owns an open window was destroyed; the saved part below contains only the sheet id and the displayed state.
local opened_sheets = setmetatable({}, {__mode = "v"})

local STATES = {not_computed = true, current = true, pending = true, stale = true, failed = true}

local function player_of(player_index)
    local player = game.get_player(player_index)
    return player and player.valid and player or nil
end

local function find_named(root, name)
    for _, child in ipairs(root and root.children or {}) do
        if child.name == name and child.valid then return child end
    end
end

local function find_type(root, element_type)
    if root and root.valid and root.type == element_type then return root end
    for _, child in ipairs(root and root.children or {}) do
        local found = find_type(child, element_type)
        if found then return found end
    end
end

local function frame_of(player)
    return player and find_named(player.gui.screen, ExportDialog.FRAME_NAME)
end

local function clear_saved_state(player_index)
    if storage[player_index] then
        storage[player_index].export_dialog = nil
    end
    opened_sheets[player_index] = nil
end

local function destroy_frame(frame)
    if frame and frame.valid then frame.destroy() end
end

local function live_frame(player_index)
    local player = player_of(player_index)
    local frame = frame_of(player)
    local tracked_sheet = opened_sheets[player_index]

    --A sheet can disappear without giving this module an event. The weak runtime reference lets the next honest
    --query clean up the window, while no LuaObject is ever put into storage.
    if tracked_sheet and not tracked_sheet.valid then
        clear_saved_state(player_index)
        destroy_frame(frame)
        return nil
    end
    if not player then
        clear_saved_state(player_index)
        destroy_frame(frame)
        return nil
    end
    if not storage[player_index] then
        clear_saved_state(player_index)
        destroy_frame(frame)
        return nil
    end
    if not frame then
        clear_saved_state(player_index)
        return nil
    end
    return frame
end

local function state_from(payload, supplied_state)
    local candidates = {}
    local function add(state)
        if state ~= nil then candidates[#candidates + 1] = state end
    end
    add(supplied_state)
    add(payload and payload.state)
    add(payload and payload.sheet and payload.sheet.state)
    add(payload and payload.snapshot and payload.snapshot.state)
    for _, state in ipairs(candidates) do
        if STATES[state] then return state end
    end
    return "not_computed"
end

local function sheet_id_of(sheet_flow)
    local tags = sheet_flow and sheet_flow.tags
    return tags and tags.hxrrc_sheet_id or nil
end

local function sheet_flow_of(element)
    while element and element.parent and element.parent.type ~= "tabbed-pane" do
        element = element.parent
    end
    return element
end

local function build_window(player, state, encoded, encode_error, sheet_id)
    local frame = player.gui.screen.add{
        type = "frame",
        name = ExportDialog.FRAME_NAME,
        direction = "vertical",
        caption = {"hxrrc.export_dialog_title"},
        tags = {hxrrc_sheet_id = sheet_id},
    }
    frame.auto_center = true

    frame.add{
        type = "label",
        name = STATE_NAME,
        caption = {"hxrrc.export_state_" .. state},
    }

    if type(encoded) == "string" and encode_error == nil then
        local scroll = frame.add{type = "scroll-pane", name = SCROLL_NAME}
        scroll.style.maximal_height = 400
        scroll.add{
            type = "text-box",
            name = TEXT_NAME,
            text = encoded,
            read_only = true,
            selectable = true,
            word_wrap = true,
        }
    else
        frame.add{
            type = "label",
            name = "hxrrc_export_failure",
            caption = {"hxrrc.export_encoding_failed"},
        }
    end

    frame.add{
        type = "label",
        name = "hxrrc_export_explanation",
        caption = {"hxrrc.export_explanation"},
    }

    local footer = frame.add{type = "flow", name = "hxrrc_export_footer", direction = "horizontal"}
    footer.style.horizontally_stretchable = true
    footer.style.horizontal_align = "right"
    footer.add{type = "button", name = SELECT_ALL_NAME, caption = {"hxrrc.export_select_all"}}
    footer.add{type = "button", name = CLOSE_NAME, caption = {"hxrrc.export_close"}}
    return frame
end

function ExportDialog.open(player_index, sheet_flow)
    local player = player_of(player_index)
    if not player then return nil end

    local existing = live_frame(player_index)
    if existing then return existing end

    local payload, supplied_state = ExportPayload.build(player_index, sheet_flow)
    local encoded, encode_error = ExportPayload.encode(payload)
    local state = state_from(payload, supplied_state)
    local frame = build_window(player, state, encoded, encode_error, sheet_id_of(sheet_flow))

    --Only plain data is saved. The frame is recovered from player.gui.screen by name.
    storage[player_index].export_dialog = {sheet_id = sheet_id_of(sheet_flow), state = state}
    opened_sheets[player_index] = sheet_flow
    player.opened = frame
    return frame
end

function ExportDialog.close(player_index)
    local player = player_of(player_index)
    local frame = frame_of(player)
    local was_opened = player and player.opened == frame
    clear_saved_state(player_index)
    destroy_frame(frame)
    if was_opened and player and player.valid then
        player.opened = nil
    end
end

function ExportDialog.is_open(player_index)
    return live_frame(player_index) ~= nil
end

--What the export button does, kept here so gui/sheet.lua only delegates
function ExportDialog.on_export_clicked(event)
    if not event or not event.element then return false end
    return ExportDialog.open(event.player_index, sheet_flow_of(event.element)) ~= nil
end

event_handlers.on_gui_click[SELECT_ALL_NAME] = function(event)
    local frame = frame_of(player_of(event.player_index))
    local text_box = find_type(frame, "text-box")
    if text_box then
        text_box.select_all()
        text_box.focus()
    end
end

event_handlers.on_gui_click[CLOSE_NAME] = function(event)
    ExportDialog.close(event.player_index)
end

return ExportDialog
