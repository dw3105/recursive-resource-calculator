--The window that shows the debug string.
--
--Owned by lane W1-exportui. A scrollable, selectable, read-only text box with Copy and Close, an
--explanation that says the string is not a blueprint, and a message when encoding failed. It reads the sheet and
--changes nothing on it; opening or closing it leaves the report exactly as it was.
local ExportPayload = require "logic.export_payload"

local ExportDialog = {}

ExportDialog.FRAME_NAME = "hxrrc_export_dialog"
local TEXT_NAME = "hxrrc_export_text"
local STATE_NAME = "hxrrc_export_state"
local CLOSE_ONLY_NOTE = "hxrrc_export_explanation"
local SELECT_ALL_NAME = "hxrrc_export_select_all_button"
local CLOSE_NAME = "hxrrc_export_close_button"
local TITLEBAR_NAME = "hxrrc_export_titlebar"
local FRAME_MIN_WIDTH = 600
local TEXT_WIDTH = 600
local TEXT_HEIGHT = 240
--A line must be narrower than TEXT_WIDTH at the default font, or the pane grows a sideways scrollbar.
--64 characters is about 460 px, well inside 600.
local DISPLAY_LINE_LENGTH = 64

--GUI handles are deliberately kept out of storage. This is only a runtime aid for noticing that the sheet which
--owns an open window was destroyed; the saved part below contains only the sheet id and the displayed state.
local opened_sheets = {}

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

local function select_and_focus(frame)
    local text_box = find_type(frame, "text-box")
    if not text_box then return nil end
    text_box.select_all()
    text_box.focus()
    return text_box
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
    local saved_state = storage[player_index] and storage[player_index].export_dialog

    --A sheet can disappear without giving this module an event. The runtime reference lets the next honest query
    --clean up the window, while no LuaObject is ever put into storage.
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
    --Esc or another GUI can take the focus without this module receiving a close callback. Treat that as closed.
    if frame and player.opened ~= frame then
        clear_saved_state(player_index)
        destroy_frame(frame)
        return nil
    end
    if saved_state and saved_state.sheet_id and not tracked_sheet then
        local pane = storage[player_index].sheet_section and storage[player_index].sheet_section.sheet_pane
        if pane then
            local found = false
            for _, tab_and_content in ipairs(pane.tabs) do
                local content = tab_and_content.content
                local tags = content and content.tags
                if content and content.valid and tags and tags.hxrrc_sheet_id == saved_state.sheet_id then
                    found = true
                    break
                end
            end
            if not found then
                clear_saved_state(player_index)
                destroy_frame(frame)
                return nil
            end
        end
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

local function display_text(encoded)
    if #encoded <= DISPLAY_LINE_LENGTH then return encoded end
    local lines = {}
    for start = 1, #encoded, DISPLAY_LINE_LENGTH do
        lines[#lines + 1] = encoded:sub(start, start + DISPLAY_LINE_LENGTH - 1)
    end
    return table.concat(lines, "\n")
end

local function build_window(player, state, encoded, encode_error, sheet_id, blueprint_string)
    local frame = player.gui.screen.add{
        type = "frame",
        name = ExportDialog.FRAME_NAME,
        direction = "vertical",
        tags = {hxrrc_sheet_id = sheet_id},
    }
    frame.auto_center = true
    frame.style.minimal_width = FRAME_MIN_WIDTH

    --The game's own string windows carry their title, a draggable gap and a close button in one bar. The three
    --close sprites are core utility sprites of 2.0 ("close" and "close_black"); "close_white" does not exist.
    local titlebar = frame.add{type = "flow", name = TITLEBAR_NAME, direction = "horizontal"}
    titlebar.drag_target = frame
    titlebar.add{type = "label", name = "hxrrc_export_title", caption = {blueprint_string and "hxrrc.blueprint_string_title" or "hxrrc.export_dialog_title"},
        style = "frame_title"}
    local drag_space = titlebar.add{type = "empty-widget", name = "hxrrc_export_drag",
        style = "draggable_space_header"}
    drag_space.style.horizontally_stretchable = true
    drag_space.style.height = 24
    drag_space.drag_target = frame
    titlebar.add{
        type = "sprite-button", name = CLOSE_NAME, style = "frame_action_button",
        sprite = "utility/close", hovered_sprite = "utility/close_black", clicked_sprite = "utility/close_black",
        tooltip = {"hxrrc.export_close"}, mouse_button_filter = {"left"},
    }

    frame.add{
        type = "label",
        name = STATE_NAME,
        caption = {blueprint_string and "hxrrc.blueprint_delivered" or "hxrrc.export_state_" .. state},
    }

    if type(encoded) == "string" and encode_error == nil then
        local text_box = frame.add{
            type = "text-box",
            name = TEXT_NAME,
            text = display_text(encoded),
        }
        --LuaGuiElement::add takes "text" and "icon_selector" for a text-box and drops anything else without a
        --word. read_only, selectable and word_wrap are attributes, so they are written here, after the box
        --exists. 1.1.47 passed them to add{} and shipped a box the player could type in, which ate the E key.
        text_box.read_only = true
        text_box.selectable = true
        text_box.word_wrap = true
        text_box.style.width = TEXT_WIDTH
        text_box.style.height = TEXT_HEIGHT
        --Fill the frame the way the game's own string window does, and never grow a sideways scrollbar.
        text_box.style.horizontally_stretchable = true
        text_box.style.horizontally_squashable = false
        select_and_focus(frame)
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
        caption = {blueprint_string and "hxrrc.blueprint_string_explanation" or "hxrrc.export_explanation"},
    }

    local footer = frame.add{type = "flow", name = "hxrrc_export_footer", direction = "horizontal"}
    footer.style.horizontally_stretchable = true
    footer.style.horizontal_align = "left"
    --One button only. A mod cannot write text to the system clipboard: LuaPlayer.add_to_clipboard takes a
    --blueprint stack and feeds the game's own blueprint clipboard. So the window selects the string itself and
    --the player presses CTRL + C, and no button pretends to copy.
    --Esc and the close key shut the window: player.opened holds the frame, control.lua answers on_gui_closed,
    --and the title bar's X does the same thing by hand.
    footer.add{type = "button", name = SELECT_ALL_NAME, caption = {"hxrrc.export_select_all"}}
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

function ExportDialog.open_blueprint_string(player_index, encoded)
    local player = player_of(player_index)
    if not player or type(encoded) ~= "string" then return nil end
    local existing = live_frame(player_index)
    if existing then destroy_frame(existing) end
    local frame = build_window(player, "current", encoded, nil, nil, true)
    storage[player_index].export_dialog = {state = "current"}
    opened_sheets[player_index] = nil
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
    select_and_focus(frame_of(player_of(event.player_index)))
end

event_handlers.on_gui_click[CLOSE_NAME] = function(event)
    ExportDialog.close(event.player_index)
end

return ExportDialog
