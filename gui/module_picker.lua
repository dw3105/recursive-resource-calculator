--The picker window for a module slot, a machine button or a beacon button: the choices in one grid with no groups, the unlocked qualities below
--it as icons, a clear button where emptying is allowed, and a confirm tick. One click selects; a double click on a choice (or on a quality while a
--choice is selected) confirms, as the tick does. Confirming stores the pick through its kind's storing path and closes the window; confirming
--with nothing selected does nothing.
local ModuleSetup = require "logic.module_setup"
local ModuleGUI = require "gui.modulegui"
local Pipette = require "gui.pipette"
local Report = require "gui.report"
local Utils = require "logic.utils"

local ModulePicker = {}

--A second click on the same module or quality within this many ticks is a double click (the engine raises no double-click event)
ModulePicker.DOUBLE_CLICK_TICKS = 30
local GRID_COLUMNS = 10

local function state_of(player_index)
    return storage[player_index] and storage[player_index].module_picker
end

--What each kind of picker offers and how it stores. describe(button) returns nil for a stale button, else
--{choices = names in grid order, stored = {name, quality} or nil, clear = {sprite, tooltip} or nil when the button cannot be emptied}
local KINDS = {
    module = {
        title = {"hxrrc.module_picker_title"},
        confirm_tooltip = {"hxrrc.module_picker_confirm_tooltip"},
        sprite_prefix = "item/",
        prototypes = function() return prototypes.item end,
        describe = function(button)
            local setup, _, recipe_name, identifier = ModuleGUI.context(button)
            if not setup then
                return nil
            end
            local modules, entities = ModuleGUI.slot_target(button, setup, identifier)
            if not modules then
                return nil
            end
            return {choices = ModuleSetup.allowed_module_names(entities, prototypes.recipe[recipe_name]), stored = modules[button.tags.index],
                clear = {sprite = "utility/empty_module_slot", tooltip = {"", {"hxrrc.module_picker_clear"}, "\n", {"hxrrc.module_picker_clear_tooltip"}}}}
        end,
        store = function(button, picked) return ModuleGUI.pick_into(button, picked) end,
        clear = function(button) return ModuleGUI.pick_into(button, nil) end,
    },
    --a row or loop stage always has a machine: no clear
    machine = {
        title = {"hxrrc.machine_picker_title"},
        confirm_tooltip = {"hxrrc.machine_picker_confirm_tooltip"},
        sprite_prefix = "entity/",
        prototypes = function() return prototypes.entity end,
        describe = function(button)
            local context = Report.machine_context(button)
            if not context then
                return nil
            end
            local choices = {}
            for _, machine in ipairs(Utils.crafting_machines_for(context.recipe)) do
                local prototype = prototypes.entity[machine.name]
                if prototype and not prototype.hidden then
                    choices[#choices + 1] = machine.name
                end
            end
            return {choices = choices, stored = context.machine}
        end,
        store = function(button, picked) return Report.pick_machine(button, picked) end,
    },
}

ModulePicker.KIND_OF_BUTTON = {
    hxrrc_choose_module_button = "module",
    hxrrc_choose_beacon_module_button = "module",
    hxrrc_choose_crafting_machine_button = "machine",
    hxrrc_choose_loop_machine_button = "machine",
}
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
        button.toggled = button.tags.choice == state.selected_choice
    end
    for _, flow in ipairs(state.frame.picker_qualities.children) do
        local button = flow.children[1]
        button.toggled = button.tags.quality == state.selected_quality
    end
end

--Gives the player's focus back to the calculator when it is shown and nothing else holds the focus
local function restore_focus(player_index)
    local player = game.get_player(player_index)
    local calculator = storage[player_index] and storage[player_index].calculator
    if player and calculator and calculator.valid and calculator.visible and player.opened == nil then
        player.opened = calculator
    end
end

--Closes the player's picker without storing anything. The state goes first, so a close that raises another event finds nothing to act on.
--restore: whether the calculator gets the player's focus back afterwards; false when the calculator itself is closing, or when the engine is
--closing the picker (never open a GUI inside on_gui_closed: see ModulePicker.on_engine_closed)
function ModulePicker.close(player_index, restore)
    local state = state_of(player_index)
    if not state then
        return
    end
    storage[player_index].module_picker = nil
    if state.frame.valid then
        state.frame.destroy()
    end
    if restore then
        restore_focus(player_index)
    end
end

--on_gui_closed for the picker (Esc, E, or another GUI replacing it). Factorio 2.0.77 force-closes a GUI opened during this event, so nothing is
--opened here: the calculator's focus is restored on the next tick, and only if the player has not opened something else by then.
function ModulePicker.on_engine_closed(player_index)
    ModulePicker.close(player_index, false)
    storage.opened_restores = storage.opened_restores or {}
    table.insert(storage.opened_restores, player_index)
end

--Runs from on_tick: each queued player whose picker closed gets the calculator's focus back, or, when another GUI took the focus, the calculator
--is hidden the way a replaced calculator is
function ModulePicker.run_restores()
    local queue = storage.opened_restores
    if not queue then
        return
    end
    storage.opened_restores = nil --taken first, so a restore raising another close queues into a fresh list
    for _, player_index in ipairs(queue) do
        local player = game.get_player(player_index)
        local calculator = storage[player_index] and storage[player_index].calculator
        if player and player.valid and calculator and calculator.valid and calculator.visible and not state_of(player_index) then
            if player.opened == nil then
                player.opened = calculator
            elseif player.opened ~= calculator then
                calculator.visible = false
            end
        end
    end
end

--Drops a removed player's queued restores
function ModulePicker.forget_player(player_index)
    local queue = storage.opened_restores
    if not queue then
        return
    end
    for index = #queue, 1, -1 do
        if queue[index] == player_index then
            table.remove(queue, index)
        end
    end
end

--Opens the picker for a module slot, machine button or beacon button of a current report; returns false, opening nothing, when the button is
--stale or of no kind
function ModulePicker.open(button)
    local player_index = button.player_index
    local kind_name = ModulePicker.KIND_OF_BUTTON[button.name]
    local kind = KINDS[kind_name]
    local description = kind and kind.describe(button)
    if not description then
        return false
    end
    ModulePicker.close(player_index, false)

    local player = game.get_player(player_index)
    local stored = description.stored
    local offered = {}
    for _, name in ipairs(description.choices) do offered[name] = true end

    local frame = player.gui.screen.add{type = "frame", name = "hxrrc_module_picker", direction = "vertical", caption = kind.title}
    frame.auto_center = true
    local scroll = frame.add{type = "scroll-pane", name = "picker_scroll"}
    scroll.style.maximal_height = 400
    local grid = scroll.add{type = "table", name = "picker_grid", column_count = GRID_COLUMNS}
    local choice_prototypes = kind.prototypes()
    for _, name in ipairs(description.choices) do
        --each button in its own flow: the engine refuses two children with the same name under one parent
        grid.add{type = "flow"}.add{type = "sprite-button", name = "hxrrc_picker_choice_button", sprite = kind.sprite_prefix .. name,
            tooltip = choice_prototypes[name].localised_name, tags = {choice = name}}
    end
    local qualities = frame.add{type = "flow", name = "picker_qualities", direction = "horizontal"}
    for _, name in ipairs(offered_qualities(player.force)) do
        qualities.add{type = "flow"}.add{type = "sprite-button", name = "hxrrc_picker_quality_button", sprite = "quality/" .. name, style = "slot_button",
            tooltip = prototypes.quality[name].localised_name, tags = {quality = name}}
    end
    local footer = frame.add{type = "flow", name = "picker_footer", direction = "horizontal"}
    footer.style.horizontally_stretchable = true
    footer.style.horizontal_align = "right"
    if description.clear then
        footer.add{type = "sprite-button", name = "hxrrc_picker_clear_button", sprite = description.clear.sprite, style = "slot_button",
            tooltip = description.clear.tooltip}
    end
    footer.add{type = "sprite-button", name = "hxrrc_picker_confirm_button", sprite = "utility/check_mark_green", style = "item_and_count_select_confirm",
        tooltip = kind.confirm_tooltip}

    local stored_quality = stored and stored.quality and prototypes.quality[stored.quality] and stored.quality or "normal"
    local state = {
        frame = frame,
        button = button,
        kind = kind_name,
        --a stored choice the grid does not offer (hidden) is never preselected, so confirming cannot store it again
        selected_choice = stored and offered[stored.name] and stored.name or nil,
        selected_quality = stored_quality,
    }
    storage[player_index].module_picker = state
    repaint(state)
    --the picker takes the focus, so Esc and E close it; the calculator's close handler leaves the calculator open while a picker exists
    player.opened = frame
    return true
end

--Stores the selected choice at the selected quality through its kind and closes. With no picker open or nothing selected it does nothing,
--and the window stays open. Returns true when stored state changed.
function ModulePicker.confirm(player_index)
    local state = state_of(player_index)
    if not (state and state.selected_choice) then
        return false
    end
    --one identifier for every kind: normal quality is stored as none, as everywhere else
    local quality = state.selected_quality ~= "normal" and state.selected_quality or nil
    local changed = state.button.valid and KINDS[state.kind].store(state.button, {name = state.selected_choice, quality = quality}) or false
    ModulePicker.close(player_index, true)
    return changed
end

--Empties the slot (or removes the beacon group) and closes; the only picker path that stores nothing. A kind that cannot be emptied offers
--no clear button, and does nothing here. Returns true when stored state changed.
function ModulePicker.clear(player_index)
    local state = state_of(player_index)
    local clear = state and KINDS[state.kind].clear
    if not clear then
        return false
    end
    local changed = state.button.valid and clear(state.button) or false
    ModulePicker.close(player_index, true)
    return changed
end

--A click on a choice or quality button: selects it, or confirms on a double click. kind: "choice" or "quality"
local function on_choice_click(event, kind)
    local state = state_of(event.player_index)
    if not state then
        return false
    end
    local key = event.element.tags[kind]
    local last = state.last_click
    local double = last and last.kind == kind and last.key == key and event.tick - last.tick <= ModulePicker.DOUBLE_CLICK_TICKS
    if kind == "choice" then
        state.selected_choice = key
    else
        state.selected_quality = key
    end
    if double and state.selected_choice then
        return ModulePicker.confirm(event.player_index)
    end
    state.last_click = {kind = kind, key = key, tick = event.tick}
    repaint(state)
    return false
end

--A module slot button: a left click with a module in the hand (real or ghost) pastes it, as the pipette key does; any other left click opens the
--picker on it; a right click empties it. Chooser slots of reports built before 1.1.25 keep Factorio's own chooser and are left to their
--elem-changed handler. Returns true when the stored setup changed.
function ModulePicker.on_slot_click(event)
    local slot_button = event.element
    if slot_button.type ~= "sprite-button" then
        return false
    end
    if event.button == defines.mouse_button_type.right then
        return ModuleGUI.pick_into(slot_button, nil)
    end
    local player = game.get_player(event.player_index)
    local held = Pipette.held(player)
    if held and storage.module_names[held.name] then
        return Pipette.paste_module(player, slot_button, held)
    end
    ModulePicker.open(slot_button)
    return false
end

--A machine button of a row or loop stage: a left click opens the machine picker; a right click does nothing, as a row always has a machine.
--Choose-elem-buttons of reports built before 1.1.27 are left to their elem-changed handler. Never changes stored state itself.
function ModulePicker.on_machine_click(event)
    local button = event.element
    if button.type ~= "sprite-button" or event.button ~= defines.mouse_button_type.left then
        return false
    end
    ModulePicker.open(button)
    return false
end

function ModulePicker.on_choice_click(event)
    return on_choice_click(event, "choice")
end

function ModulePicker.on_quality_click(event)
    return on_choice_click(event, "quality")
end

return ModulePicker
