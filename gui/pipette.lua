--The pipette key (Q, or whatever the player bound the pipette to) over the calculator: copies the module under the cursor into the hand as a ghost.
--Factorio 2.0.77 gives the custom input event the GUI element under the cursor; anything that is not one of the calculator's controls is left to
--the vanilla pipette, which runs on the same press.
local ModuleGUI = require "gui.modulegui"

local Pipette = {}

local MODULE_SLOTS = {hxrrc_choose_module_button = true, hxrrc_choose_beacon_module_button = true}

--A quality given as a prototype or a name, as a name; nil for normal
local function quality_name(quality)
    local name = type(quality) == "table" and quality.name or quality
    return name ~= "normal" and name or nil
end

--What the player holds as {name, quality, real | ghost}, names only, quality nil for normal; nil for an empty hand.
--A real item in the cursor stack comes first: Factorio 2.0.77 gives it priority over the cursor ghost. Both reads return prototypes.
function Pipette.held(player)
    local stack = player.cursor_stack
    if stack and stack.valid_for_read then
        return {name = stack.name, quality = quality_name(stack.quality), real = true}
    end
    local ghost = player.cursor_ghost
    if ghost then
        local name = type(ghost.name) == "table" and ghost.name.name or ghost.name
        return {name = name, quality = quality_name(ghost.quality), ghost = true}
    end
end

--The module stored in the slot a button shows, or nil for an empty slot or a stale cell. The stored setup is read, never the button's own value.
local function stored_module(button)
    local setup, _, _, identifier = ModuleGUI.context(button)
    if not setup then
        return nil
    end
    local modules = ModuleGUI.slot_target(button, setup, identifier)
    return modules and modules[button.tags.index]
end

--Returns true when stored sheet state changed (so the caller recomputes)
function Pipette.on_pipette(event)
    local element = event.element
    if not (element and element.valid) then
        return false
    end
    local player = game.get_player(event.player_index)
    if MODULE_SLOTS[element.name] then
        if Pipette.held(player) == nil then
            local module = stored_module(element)
            if module then
                player.cursor_ghost = {name = module.name, quality = module.quality}
            end
        end
        return false
    end
    return false
end

return Pipette
