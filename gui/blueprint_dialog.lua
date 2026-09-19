--Where the player picks what the blueprint is built out of, and which edges carry inputs and outputs.
--
--Owned by lane W3-infra. A thin shell over logic/bp/settings.lua: it shows the choices, keeps overrides per
--sheet, and refuses a choice the game cannot honour with the reason why.
local BlueprintDialog = {}

BlueprintDialog.FRAME_NAME = "hxrrc_blueprint_dialog"

local Settings = require "logic.bp.settings"
local Catalog = require "logic.catalog"
local ReasonCodes = require "logic.bp.reason_codes"

local GENERATE_NAME = "hxrrc_blueprint_generate_button"
local CLOSE_NAME = "hxrrc_blueprint_close_button"
local ERROR_NAME = "hxrrc_blueprint_error"
local INPUT_EDGE_NAME = "hxrrc_blueprint_input_edge_dropdown"
local OUTPUT_EDGE_NAME = "hxrrc_blueprint_output_edge_dropdown"

local INFRASTRUCTURE = {
    {key = "roboport", name = "hxrrc_blueprint_roboport_button", entity_type = "roboport"},
    {key = "pole", name = "hxrrc_blueprint_pole_button", entity_type = "electric-pole"},
    {key = "belt", name = "hxrrc_blueprint_belt_button", entity_type = "transport-belt"},
    {key = "inserter", name = "hxrrc_blueprint_inserter_button", entity_type = "inserter"},
    {key = "pipe", name = "hxrrc_blueprint_pipe_button", entity_type = "pipe"},
    {key = "underground_pipe", name = "hxrrc_blueprint_underground_pipe_button", entity_type = "pipe-to-ground"},
}

--GUI objects are runtime-only. The saved settings are recovered by sheet id through Settings.of_sheet.
local opened_sheets = {}

local function player_of(player_index)
    local player = game.get_player(player_index)
    return player and player.valid and player or nil
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

local function find_named(root, name)
    if not root or not root.valid then return nil end
    if root.name == name then return root end
    for _, child in ipairs(root.children or {}) do
        local found = find_named(child, name)
        if found then return found end
    end
end

local function frame_of(player)
    return find_named(player and player.gui and player.gui.screen, BlueprintDialog.FRAME_NAME)
end

local function destroy(frame)
    if frame and frame.valid then frame.destroy() end
end

local function clear_opened(player_index)
    opened_sheets[player_index] = nil
    if storage[player_index] then storage[player_index].blueprint_dialog = nil end
end

local function live_frame(player_index)
    local player = player_of(player_index)
    local frame = frame_of(player)
    local sheet = opened_sheets[player_index]
    if sheet and not sheet.valid then
        clear_opened(player_index)
        destroy(frame)
        return nil
    end
    if not player then
        clear_opened(player_index)
        destroy(frame)
        return nil
    end
    --Esc or another GUI may have taken focus without a module callback. Do not leave a stale frame on screen.
    if frame and player.opened ~= frame then
        clear_opened(player_index)
        destroy(frame)
        return nil
    end
    if not frame then
        clear_opened(player_index)
        return nil
    end
    return frame
end

local function edge_index(edge)
    for index, value in ipairs(Settings.EDGES) do
        if value == edge then return index end
    end
    return 1
end

local function entity_value(choice)
    if type(choice) ~= "table" or not choice.name then return nil end
    if not rawget(_G, "prototypes") or not prototypes.entity[choice.name] then return nil end
    return {name = choice.name, quality = choice.quality or "normal"}
end

local function add_choice_row(grid, definition, choice)
    grid.add{type = "label", name = "hxrrc_blueprint_" .. definition.key .. "_label", caption = {"hxrrc.blueprint_infra_" .. definition.key}}
    grid.add{
        type = "choose-elem-button",
        name = definition.name,
        elem_type = "entity-with-quality",
        ["entity-with-quality"] = entity_value(choice),
        elem_filters = {{filter = "type", type = definition.entity_type}},
        tags = {setting = definition.key},
    }
end

local function build_window(player, sheet_flow, settings)
    local frame = player.gui.screen.add{
        type = "frame",
        name = BlueprintDialog.FRAME_NAME,
        direction = "vertical",
        caption = {"hxrrc.blueprint_dialog_title"},
        tags = {hxrrc_sheet_id = sheet_id_of(sheet_flow)},
    }
    frame.auto_center = true

    local grid = frame.add{type = "table", name = "hxrrc_blueprint_edges", column_count = 2}
    grid.style.column_alignments[1] = "middle-right"
    grid.style.column_alignments[2] = "middle-left"

    for _, definition in ipairs(INFRASTRUCTURE) do
        add_choice_row(grid, definition, settings[definition.key])
    end

    grid.add{type = "label", name = "hxrrc_blueprint_input_edge_label", caption = {"hxrrc.blueprint_edge_input"}}
    grid.add{type = "drop-down", name = INPUT_EDGE_NAME, items = {
        {"hxrrc.blueprint_edge_left"}, {"hxrrc.blueprint_edge_right"},
        {"hxrrc.blueprint_edge_top"}, {"hxrrc.blueprint_edge_bottom"},
    }, selected_index = edge_index(settings.input_edge)}
    grid.add{type = "label", name = "hxrrc_blueprint_output_edge_label", caption = {"hxrrc.blueprint_edge_output"}}
    grid.add{type = "drop-down", name = OUTPUT_EDGE_NAME, items = {
        {"hxrrc.blueprint_edge_left"}, {"hxrrc.blueprint_edge_right"},
        {"hxrrc.blueprint_edge_top"}, {"hxrrc.blueprint_edge_bottom"},
    }, selected_index = edge_index(settings.output_edge)}

    frame.add{type = "label", name = ERROR_NAME, caption = "", visible = false}
    local footer = frame.add{type = "flow", name = "hxrrc_blueprint_footer", direction = "horizontal"}
    footer.style.horizontally_stretchable = true
    footer.style.horizontal_align = "right"
    footer.add{type = "button", name = GENERATE_NAME, caption = {"hxrrc.blueprint_generate"}}
    footer.add{type = "button", name = CLOSE_NAME, caption = {"gui.cancel"}}
    return frame
end

local function catalog_for(player_index, settings)
    local belt = settings.belt or {}
    local pipe = settings.pipe or {}
    local underground_pipe = settings.underground_pipe or {}
    return Catalog.build(player_index, {
        belt = {
            belt = belt.name,
            underground = belt.underground,
            splitter = belt.splitter,
            quality = belt.quality,
        },
        pipe = {
            pipe = pipe.name,
            underground = underground_pipe.name,
            quality = pipe.quality,
        },
        inserter = settings.inserter,
        pole = settings.pole,
        robo = settings.roboport,
    })
end

local function show_error(frame, code, subject)
    local label = frame and frame[ERROR_NAME]
    if not label then return end
    local key = ReasonCodes.locale_key(code) or "hxrrc.blueprint_reject_option_prototype_missing"
    label.caption = {key, subject and subject.name or "infrastructure"}
    label.visible = true
end

local function settings_for_open_dialog(player_index, element)
    local sheet = opened_sheets[player_index]
    if sheet and sheet.valid then return sheet end
    return sheet_flow_of(element)
end

function BlueprintDialog.open(player_index, sheet_flow)
    local player = player_of(player_index)
    if not player or not sheet_flow or not sheet_flow.valid then return nil end

    local existing = live_frame(player_index)
    if existing then
        if opened_sheets[player_index] == sheet_flow then return existing end
        BlueprintDialog.close(player_index)
    end

    local settings = Settings.of_sheet(player_index, sheet_id_of(sheet_flow))
    local frame = build_window(player, sheet_flow, settings)
    opened_sheets[player_index] = sheet_flow
    --Only the identity is saved; the frame and sheet are LuaObjects and stay in the runtime table above.
    if storage[player_index] then
        storage[player_index].blueprint_dialog = {sheet_id = sheet_id_of(sheet_flow)}
    end
    player.opened = frame
    return frame
end

function BlueprintDialog.close(player_index)
    local player = player_of(player_index)
    local frame = frame_of(player)
    local was_opened = player and player.opened == frame
    clear_opened(player_index)
    destroy(frame)
    if was_opened and player and player.valid then player.opened = nil end
end

function BlueprintDialog.is_open(player_index)
    return live_frame(player_index) ~= nil
end

local function store_element_change(event)
    local element = event and event.element
    if not element then return end
    local sheet = opened_sheets[event.player_index]
    local tags = element.tags or {}
    local key = tags.setting
    if not sheet or not sheet.valid or not key then return end
    local settings = Settings.of_sheet(event.player_index, sheet_id_of(sheet))
    local value = element.elem_value
    if value == nil then
        settings[key] = nil
    else
        settings[key] = value
    end
    Settings.store(event.player_index, sheet_id_of(sheet), settings)
end

local function store_edge_change(event)
    local element = event and event.element
    local sheet = opened_sheets[event.player_index]
    if not element or not sheet or not sheet.valid then return end
    local settings = Settings.of_sheet(event.player_index, sheet_id_of(sheet))
    local edge = Settings.EDGES[element.selected_index or 1]
    if element.name == INPUT_EDGE_NAME then settings.input_edge = edge else settings.output_edge = edge end
    Settings.store(event.player_index, sheet_id_of(sheet), settings)
end

function BlueprintDialog.on_generate_clicked(event)
    if not event or not event.element then return false end
    local element = event.element
    if element.name == "hxrrc_generate_blueprint_button" then
        return BlueprintDialog.open(event.player_index, sheet_flow_of(element)) ~= nil
    end
    if element.name ~= GENERATE_NAME then return false end

    local player_index = event.player_index
    local sheet = settings_for_open_dialog(player_index, element)
    if not sheet or not sheet.valid then return false end
    local sheet_id = sheet_id_of(sheet)
    local settings = Settings.of_sheet(player_index, sheet_id)
    local catalog, diagnostics = catalog_for(player_index, settings)
    --Catalog diagnostics are projected into the same rejection shape without guessing a replacement prototype.
    for _, diagnostic in ipairs(diagnostics or {}) do
        if diagnostic.code == "CATALOG_MISSING_PROTOTYPE" then
            local name = tostring(diagnostic.subject or "infrastructure"):gsub("^[^/]+/", "")
            show_error(frame_of(player_of(player_index)), "BP_REJ_OPTION_PROTOTYPE_MISSING", {name = name})
            return false, "BP_REJ_OPTION_PROTOTYPE_MISSING", {name = name}
        elseif diagnostic.code == "CATALOG_MISSING_QUALITY" then
            local name = tostring(diagnostic.subject or "quality"):gsub("^[^/]+/", "")
            show_error(frame_of(player_of(player_index)), "BP_REJ_QUALITY_UNAVAILABLE", {name = name})
            return false, "BP_REJ_QUALITY_UNAVAILABLE", {name = name}
        end
    end
    local ok, code, subject = Settings.validate(settings, catalog, player_index)
    if not ok then
        show_error(frame_of(player_of(player_index)), code, subject)
        return false, code, subject
    end
    --The generator job is supplied by the later blueprint lanes. The dialog's accepted boundary is the stored,
    --validated settings; keeping the window open makes a valid click side-effect free for the sheet itself.
    return true, settings
end

for _, definition in ipairs(INFRASTRUCTURE) do
    event_handlers.on_gui_elem_changed[definition.name] = store_element_change
end
event_handlers.on_gui_selection_state_changed[INPUT_EDGE_NAME] = store_edge_change
event_handlers.on_gui_selection_state_changed[OUTPUT_EDGE_NAME] = store_edge_change
event_handlers.on_gui_click[GENERATE_NAME] = BlueprintDialog.on_generate_clicked
event_handlers.on_gui_click[CLOSE_NAME] = function(event) BlueprintDialog.close(event.player_index) end

return BlueprintDialog
