--The pipette key (Q, or whatever the player bound the pipette to) over the calculator: copies the module under the cursor into the hand as a ghost.
--Factorio 2.0.77 gives the custom input event the GUI element under the cursor; anything that is not one of the calculator's controls is left to
--the vanilla pipette, which runs on the same press.
local ModuleGUI = require "gui.modulegui"
local ModuleSetup = require "logic.module_setup"
local Report = require "gui.report"
local QualityLoops = require "logic.quality_loops"
local Utils = require "logic.utils"

local Pipette = {}

local MODULE_SLOTS = {hxrrc_choose_module_button = true, hxrrc_choose_beacon_module_button = true}
local MACHINE_BUTTONS = {hxrrc_choose_crafting_machine_button = true, hxrrc_choose_loop_machine_button = true}

--The item that places an entity, never assumed to share the entity's name; nil when the entity has none (items_to_place_this is optional)
local function placing_item(entity_name)
    local prototype = prototypes.entity[entity_name]
    local items = prototype and prototype.items_to_place_this
    return items and items[1] and items[1].name
end

--Remembers a fresh row's or loop stage's machine and a copy of its setup that shares no table with it, and puts the machine's item in the hand.
--The clipboard forgives exactly one cursor notification, in this tick: the one this ghost write raises (see gui/pipette.lua N13).
local function copy_machine(player, button, tick)
    local context = Report.machine_context(button)
    if not context then
        return
    end
    local item = placing_item(context.machine.name)
    if not item then
        player.create_local_flying_text{text = {"hxrrc.machine_has_no_item_error"}, create_at_cursor = true}
        return
    end
    local id = storage.pipette_next_id or 1
    storage.pipette_next_id = id + 1
    storage[player.index].pipette = {
        id = id,
        kind = "machine",
        item = {name = item, quality = context.machine.quality},
        machine = {name = context.machine.name, quality = context.machine.quality},
        setup = QualityLoops.fitted_setup_copy(context.setup, context.machine, context.recipe),
        own_notifications = 1,
        copied_tick = tick,
    }
    player.cursor_ghost = {name = item, quality = context.machine.quality}
end

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

--Pastes the module in the hand (real or ghost) into the slot under the cursor, through the path every pick takes (so an empty row fills).
--A module the slot's entities or recipe refuse is refused with a flying text, as a manual pick could not choose it. Returns true when stored.
local function paste_module(player, button, held)
    if not storage.module_names[held.name] then
        return false
    end
    local setup, _, recipe_name, identifier = ModuleGUI.context(button)
    if not setup then
        return false
    end
    local modules, entities = ModuleGUI.slot_target(button, setup, identifier)
    if not modules then
        return false
    end
    if not ModuleSetup.fits(held.name, entities, prototypes.recipe[recipe_name]) then
        player.create_local_flying_text{text = {"hxrrc.module_does_not_fit_error"}, create_at_cursor = true}
        return false
    end
    local quality = held.quality and prototypes.quality[held.quality] and held.quality or nil --a quality a mod removed falls back to normal
    return ModuleGUI.pick_into(button, {name = held.name, quality = quality})
end

--Whether the hand still holds the clipboard's own ghost: a ghost (no real item) of the same item at the same quality
function Pipette.still_held(player, clipboard)
    local held = Pipette.held(player)
    return held ~= nil and held.ghost == true and held.name == clipboard.item.name and held.quality == clipboard.item.quality
end

--A machine paste is only recorded here and written by Pipette.run_requests in a later tick. Factorio 2.0.77 raises cursor notifications
--"in the same tick that the change happens, but not instantly" and promises nothing about their order against this input, so waiting a tick
--lets every notification for a change made up to this press drop the clipboard first. The target is kept as a tags snapshot, so a report
--rebuilt meanwhile does not lose the request.
local function request_machine_paste(player, button, held, tick)
    local clipboard = storage[player.index].pipette
    if not (clipboard and clipboard.kind == "machine") then
        return
    end
    if held.real then --a real item in the hand is not the copied machine's ghost
        storage[player.index].pipette = nil
        return
    end
    if not (held.name == clipboard.item.name and held.quality == clipboard.item.quality) then
        return
    end
    local target = Report.machine_target(button)
    if not Report.machine_context_of(player.index, target) then
        return
    end
    local requests = storage[player.index].pipette_requests or {}
    storage[player.index].pipette_requests = requests
    requests[#requests + 1] = {clipboard_id = clipboard.id, tick = tick, target = target}
end

local function module_count(setup)
    local count = #setup.modules
    for _, group in ipairs(setup.beacons) do count = count + 1 + #group.modules end
    return count
end

--Writes one request if the same clipboard is still in the hand and the target is still fresh. Returns true when stored state changed.
local function run_request(player, request)
    local clipboard = storage[player.index].pipette
    if not (clipboard and clipboard.id == request.clipboard_id and Pipette.still_held(player, clipboard)) then
        return false
    end
    local context = Report.machine_context_of(player.index, request.target)
    if not context then
        return false
    end
    if not Utils.can_craft(clipboard.machine.name, context.recipe) then
        player.create_local_flying_text{text = {"hxrrc.machine_cannot_craft_error"}, create_at_cursor = true}
        return false
    end
    local machine = {name = clipboard.machine.name, quality = clipboard.machine.quality}
    --what the new machine or recipe refuses is dropped, as picking that machine by hand does; saying so, since a paste should not lose silently
    local setup = QualityLoops.fitted_setup_copy(clipboard.setup, machine, context.recipe)
    if module_count(setup) < module_count(clipboard.setup) then
        player.create_local_flying_text{text = {"hxrrc.pasted_setup_partly_refused"}, create_at_cursor = true}
    end
    context.write(machine, setup)
    return true
end

--Runs from on_tick before the computation queue: every request recorded before this tick, in order. Returns the indexes of the players whose
--sheets changed, for the caller to recompute.
function Pipette.run_requests(tick)
    local changed = {}
    for _, player in pairs(game.players) do
        local player_storage = storage[player.index]
        local requests = player_storage and player_storage.pipette_requests
        if requests then
            local kept, wrote = {}, false
            for _, request in ipairs(requests) do
                if request.tick < tick then
                    wrote = run_request(player, request) or wrote
                else
                    kept[#kept + 1] = request
                end
            end
            player_storage.pipette_requests = #kept > 0 and kept or nil
            if wrote then
                changed[#changed + 1] = player.index
            end
        end
    end
    return changed
end

--Returns true when stored sheet state changed (so the caller recomputes)
function Pipette.on_pipette(event)
    local element = event.element
    if not (element and element.valid) then
        return false
    end
    local player = game.get_player(event.player_index)
    if MODULE_SLOTS[element.name] then
        local held = Pipette.held(player)
        if held then
            return paste_module(player, element, held)
        end
        local module = stored_module(element)
        if module then
            player.cursor_ghost = {name = module.name, quality = module.quality}
        end
        return false
    end
    if MACHINE_BUTTONS[element.name] then
        local held = Pipette.held(player)
        if held == nil then
            copy_machine(player, element, event.tick)
        else
            request_machine_paste(player, element, held, event.tick)
        end
        return false
    end
    return false
end

return Pipette
