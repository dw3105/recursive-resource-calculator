--Putting one player's recipe setups back to what a new player starts with.
--
--Owned by lane W2-reset, which also owns logic/player_data.lua for this round.
--
--Resets: recipe bindings both ways, consumer and burner bindings, chosen machines and their qualities, machine
--modules, beacon groups with their modules, count and sharing, and every quality loop. Through the same
--initializers a fresh player goes through, so a recipe that is bound automatically today is bound again.
--
--Keeps: every sheet, tab, target row, rate, unit and quality, the round-up and solver options, and the blueprint
--infrastructure choices. storage[player_index] is not wiped: it also holds the GUI handles.
--
--Before anything else it invalidates that player's running work, advances the configuration revision, closes
--pickers and drops pending pastes, so no result computed against the old setup can commit afterwards. Then every
--sheet is queued for recalculation, the visible one first.
local Jobs = require "logic.jobs"
local ModulePicker = require "gui.module_picker"
local PlayerData = require "logic.player_data"

local Reset = {}

local function remove_legacy_work(player_index)
    if type(storage) ~= "table" then
        return
    end
    if storage[player_index] then
        storage[player_index].backlogged_computation_count = 0
    end
    if type(storage.computation_stack) ~= "table" then
        return
    end
    for index = #storage.computation_stack, 1, -1 do
        if storage.computation_stack[index].player_index == player_index then
            table.remove(storage.computation_stack, index)
        end
    end
end

function Reset.run(player_index)
    local player_storage = storage[player_index]
    if not player_storage then
        return 0
    end

    --Drop saved jobs and old queue entries before changing any setup. The revision also protects a job that is
    --already in a scheduler call and reaches its publish check after this handler returns.
    Jobs.forget_player(player_index)
    remove_legacy_work(player_index)
    player_storage.config_revision = (type(player_storage.config_revision) == "number" and player_storage.config_revision or 0) + 1

    ModulePicker.close(player_index, false)
    ModulePicker.forget_player(player_index)
    player_storage.pipette = nil
    player_storage.pipette_requests = nil

    PlayerData.initialize_chosen_crafting_machines(player_index)
    PlayerData.initialize_module_setups(player_index)
    PlayerData.initialize_recipe_bindings(player_index)

    return Jobs.request_all_sheets(player_index)
end

function Reset.forget_player(player_index)
    ModulePicker.forget_player(player_index)
end

function Reset.on_reset_clicked(event)
    Reset.run(event.player_index)
    local player = game.get_player(event.player_index)
    if player and player.valid ~= false then
        player.create_local_flying_text{text = {"hxrrc.reset_setups_done"}, create_at_cursor = true}
    end
end

return Reset
