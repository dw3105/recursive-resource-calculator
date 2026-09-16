--The module picker window: the modules a slot accepts in one grid with no groups, the unlocked qualities below it, a clear button and a confirm tick.
--One click selects; a double click on a module (or on a quality while a module is selected) confirms, as the tick does. Confirming stores the pick
--through ModuleGUI.pick_into, the path every pick takes, and closes the window; confirming with no module selected does nothing.
local ModuleSetup = require "logic.module_setup"
local ModuleGUI = require "gui.modulegui"

local ModulePicker = {}

--A second click on the same module or quality within this many ticks is a double click (the engine raises no double-click event)
ModulePicker.DOUBLE_CLICK_TICKS = 30
local GRID_COLUMNS = 10

local function state_of(player_index)
    return storage[player_index] and storage[player_index].module_picker
end

--Unlocked qualities by level, then name; qualities the engine hides are left out
local function offered_qualities(force)
    local names = {}
    for name, quality in pairs(prototypes.quality) do
        if not quality.hidden and force.is_quality_unlocked(name) then
            names[#names + 1] = name
        end
    end
    table.sort(names, function(a, b)
        local level_a, level_b = prototypes.quality[a].level, prototypes.quality[b].level
        if level_a ~= level_b then return level_a < level_b end
        return a < b
    end)
    return names
end

--Marks the selected module and quality as the pressed buttons, and only them
local function repaint(state)
    for _, flow in ipairs(state.frame.picker_scroll.picker_grid.children) do
        local button = flow.children[1]
        button.toggled = button.tags.module == state.selected_module
    end
    for _, flow in ipairs(state.frame.picker_qualities.children) do
        local button = flow.children[1]
        button.toggled = button.tags.quality == state.selected_quality
    end
end

--Closes the player's picker without storing anything. The state goes first, so a close that raises another event finds nothing to act on.
--restore: whether the calculator gets the player's focus back afterwards; false when the calculator itself is closing
function ModulePicker.close(player_index, restore)
    local state = state_of(player_index)
    if not state then
        return
    end
    storage[player_index].module_picker = nil
    if state.frame.valid then
        state.frame.destroy()
    end
end

--Opens the picker for a module slot of a current report; returns false, opening nothing, when the slot's cell is stale
function ModulePicker.open(slot_button)
    local player_index = slot_button.player_index
    local setup, _, recipe_name, identifier = ModuleGUI.context(slot_button)
    if not setup then
        return false
    end
    local modules, entities = ModuleGUI.slot_target(slot_button, setup, identifier)
    if not modules then
        return false
    end
    ModulePicker.close(player_index, false)

    local player = game.get_player(player_index)
    local allowed = ModuleSetup.allowed_module_names(entities, prototypes.recipe[recipe_name])
    local stored = modules[slot_button.tags.index]
    local offered = {}
    for _, name in ipairs(allowed) do offered[name] = true end

    local frame = player.gui.screen.add{type = "frame", name = "hxrrc_module_picker", direction = "vertical", caption = {"hxrrc.module_picker_title"}}
    frame.auto_center = true
    local scroll = frame.add{type = "scroll-pane", name = "picker_scroll"}
    scroll.style.maximal_height = 400
    local grid = scroll.add{type = "table", name = "picker_grid", column_count = GRID_COLUMNS}
    for _, name in ipairs(allowed) do
        --each button in its own flow: the engine refuses two children with the same name under one parent
        grid.add{type = "flow"}.add{type = "sprite-button", name = "hxrrc_picker_module_button", sprite = "item/" .. name,
            tooltip = prototypes.item[name].localised_name, tags = {module = name}}
    end
    local qualities = frame.add{type = "flow", name = "picker_qualities", direction = "horizontal"}
    for _, name in ipairs(offered_qualities(player.force)) do
        qualities.add{type = "flow"}.add{type = "button", name = "hxrrc_picker_quality_button", caption = prototypes.quality[name].localised_name,
            tags = {quality = name}}
    end
    local footer = frame.add{type = "flow", name = "picker_footer", direction = "horizontal"}
    footer.style.horizontally_stretchable = true
    footer.style.horizontal_align = "right"
    footer.add{type = "button", name = "hxrrc_picker_clear_button", caption = {"hxrrc.module_picker_clear"}, tooltip = {"hxrrc.module_picker_clear_tooltip"}}
    footer.add{type = "sprite-button", name = "hxrrc_picker_confirm_button", sprite = "utility/check_mark_green", style = "item_and_count_select_confirm",
        tooltip = {"hxrrc.module_picker_confirm_tooltip"}}

    local stored_quality = stored and stored.quality and prototypes.quality[stored.quality] and stored.quality or "normal"
    local state = {
        frame = frame,
        button = slot_button,
        --a stored module the grid does not offer (hidden) is never preselected, so confirming cannot store it again
        selected_module = stored and offered[stored.name] and stored.name or nil,
        selected_quality = stored_quality,
    }
    storage[player_index].module_picker = state
    repaint(state)
    return true
end

--Stores the selected module at the selected quality into the slot and closes. With no picker open or no module selected it does nothing,
--and the window stays open. Returns true when the stored setup changed.
function ModulePicker.confirm(player_index)
    local state = state_of(player_index)
    if not (state and state.selected_module) then
        return false
    end
    local changed = state.button.valid and ModuleGUI.pick_into(state.button, {name = state.selected_module, quality = state.selected_quality}) or false
    ModulePicker.close(player_index, true)
    return changed
end

--Empties the slot and closes; the only path that stores nothing into a slot. Returns true when the stored setup changed.
function ModulePicker.clear(player_index)
    local state = state_of(player_index)
    if not state then
        return false
    end
    local changed = state.button.valid and ModuleGUI.pick_into(state.button, nil) or false
    ModulePicker.close(player_index, true)
    return changed
end

--A click on a module or quality button: selects it, or confirms on a double click. kind: "module" or "quality"
local function on_choice_click(event, kind)
    local state = state_of(event.player_index)
    if not state then
        return false
    end
    local key = event.element.tags[kind]
    local last = state.last_click
    local double = last and last.kind == kind and last.key == key and event.tick - last.tick <= ModulePicker.DOUBLE_CLICK_TICKS
    if kind == "module" then
        state.selected_module = key
    else
        state.selected_quality = key
    end
    if double and state.selected_module then
        return ModulePicker.confirm(event.player_index)
    end
    state.last_click = {kind = kind, key = key, tick = event.tick}
    repaint(state)
    return false
end

function ModulePicker.on_module_click(event)
    return on_choice_click(event, "module")
end

function ModulePicker.on_quality_click(event)
    return on_choice_click(event, "quality")
end

return ModulePicker
