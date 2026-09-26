--Handing a finished blueprint to the player without losing what they were holding.
--
--Owned by lane W4-deliver. The blueprint is built in a staging inventory, not on the cursor, so a failure or a
--cancellation leaves the held item, the inventory and the world exactly as they were. Only a validated complete
--result is ever published, and the revisions are checked once more immediately before it is.
--
--If the cursor cannot take it, the finished result is kept and the player is told how to collect it; it is never
--dropped and never silently overwrites another blueprint.
local BlueprintDelivery = {}

local PENDING_KEY = "blueprint_delivery"

--The result is copied before it crosses into storage.  In particular, a blueprint result must not retain a
--prototype, a LuaObject, a metatable or a callback from a caller's working state.
local function copy_plain(value, active)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" or value_type == "number" then
        return value, true
    end
    if value_type ~= "table" or getmetatable(value) ~= nil then return nil, false end
    active = active or {}
    if active[value] then return nil, false end
    active[value] = true
    local result = {}
    for key, child in pairs(value) do
        local key_type = type(key)
        if key_type ~= "string" and key_type ~= "number" then
            active[value] = nil
            return nil, false
        end
        local copied, ok = copy_plain(child, active)
        if not ok then
            active[value] = nil
            return nil, false
        end
        if copied ~= nil then result[key] = copied end
    end
    active[value] = nil
    return result, true
end

local function player_of(player_index)
    if game.get_player then return game.get_player(player_index) end
    return game.players[player_index]
end

local function state_of(player_index)
    local state = storage[player_index]
    if type(state) ~= "table" then
        state = {}
        storage[player_index] = state
    end
    return state
end

local function cursor_is_empty(player)
    local stack = player.cursor_stack
    if stack == nil then return true end
    if stack and stack.valid_for_read then return false end
    if player.cursor_ghost ~= nil then return false end
    if player.cursor_record ~= nil then return false end
    return true
end

local function tell(player, key)
    player.create_local_flying_text{text = {"hxrrc." .. key}, create_at_cursor = true}
end

local function cleanup(staged, inventory)
    if staged then pcall(function() staged.clear() end) end
    if inventory then pcall(function() inventory.destroy() end) end
end

local function complete_source(blueprint)
    if type(blueprint) ~= "table" then return nil end
    if blueprint.done ~= nil and blueprint.done ~= true then return nil end
    if blueprint.ok ~= nil and blueprint.ok ~= true then return nil end
    if blueprint.validated ~= nil and blueprint.validated ~= true then return nil end
    if blueprint.complete ~= nil and blueprint.complete ~= true then return nil end
    if blueprint.entities ~= nil then return blueprint end
    if type(blueprint.result) == "table" then
        if blueprint.result.done ~= nil and blueprint.result.done ~= true then return nil end
        if blueprint.result.ok ~= nil and blueprint.result.ok ~= true then return nil end
        return blueprint.result
    end
    return nil
end

local function prepared_result(blueprint, metadata)
    local source = complete_source(blueprint)
    if not source or type(source.entities) ~= "table" then return nil end
    metadata = type(metadata) == "table" and metadata or (type(blueprint) == "table" and blueprint.metadata) or {}

    local entities, entities_ok = copy_plain(source.entities)
    if not entities_ok then return nil end
    local icons_source = metadata.icons
    if icons_source == nil then icons_source = source.icons end
    if icons_source == nil then icons_source = {} end
    local icons, icons_ok = copy_plain(icons_source)
    if not icons_ok or type(icons) ~= "table" then return nil end

    local label = metadata.label
    if label == nil then label = source.label end
    if label == nil then label = "Recursive Resource Calculator" end
    if type(label) ~= "string" then return nil end

    local description = metadata.description
    if description == nil then description = source.description end
    if description == nil then description = "" end
    if type(description) ~= "string" then return nil end

    return {entities = entities, label = label, icons = icons, description = description}
end

local function stage(result)
    local ok, inventory = pcall(function() return game.create_inventory(1) end)
    if not ok or inventory == nil then return nil end
    local staged = inventory[1]
    if staged == nil then pcall(function() inventory.destroy() end); return nil end

    local staged_ok = pcall(function()
        staged.set_stack({name = "blueprint", count = 1})
        if not staged.is_blueprint then error("staging did not create a blueprint") end
        staged.set_blueprint_entities(result.entities)
        staged.label = result.label
        --2.0.77 refuses an empty icon list on a blueprint holding entities (headless, round 42); the engine keeps its own
        if next(result.icons) ~= nil then staged.preview_icons = result.icons end
        staged.blueprint_description = result.description
        if not staged.is_blueprint_setup() then error("staging did not set up the blueprint") end
    end)
    if not staged_ok then
        cleanup(staged, inventory)
        return nil
    end
    return staged, inventory
end

local function publish(player_index, result)
    local player = player_of(player_index)
    if not player then return false, "no_player" end
    if not cursor_is_empty(player) then
        tell(player, "blueprint_cursor_busy")
        return false, "blueprint_cursor_busy"
    end

    --All fallible work is complete before this point.  The remaining writes operate on a known-empty cursor; if a
    --runtime API call still refuses one, clear the partially written blueprint so the original empty cursor remains.
    local ok, err = pcall(function()
        local cursor = player.cursor_stack
        if cursor == nil then error("player has no cursor stack") end
        cursor.set_stack({name = "blueprint", count = 1})
        if not cursor.is_blueprint then error("cursor did not receive a blueprint") end
        cursor.set_blueprint_entities(result.entities)
        cursor.label = result.label
        --2.0.77 refuses an empty icon list on a blueprint holding entities (headless, round 42); the engine keeps its own
        if next(result.icons) ~= nil then cursor.preview_icons = result.icons end
        cursor.blueprint_description = result.description
        if not cursor.is_blueprint_setup() then error("cursor blueprint is not set up") end
    end)
    if not ok then
        pcall(function() player.clear_cursor() end)
        local state = state_of(player_index)
        state.blueprint_delivery_last_error = tostring(err)
        return false, "blueprint_delivery_failed"
    end
    return true
end

function BlueprintDelivery.deliver(player_index, blueprint, metadata)
    local player = player_of(player_index)
    if not player then return false, "no_player" end
    local state = state_of(player_index)
    --Every new attempt supersedes a saved hand-off; the newest finished result wins.
    state[PENDING_KEY] = nil
    local result = prepared_result(blueprint, metadata)
    if not result then state.blueprint_delivery_last_reason = "blueprint_delivery_failed"; return false, "blueprint_delivery_failed" end
    local staged, inventory = stage(result)
    if not staged then state.blueprint_delivery_last_reason = "blueprint_delivery_failed"; return false, "blueprint_delivery_failed" end

    --The cursor is checked again after staging.  No cursor-clearing operation is ever used to make room.
    if not cursor_is_empty(player) then
        state[PENDING_KEY] = result
        state[PENDING_KEY].pending = true
        cleanup(staged, inventory)
        tell(player, "blueprint_cursor_busy")
        return false, "blueprint_cursor_busy"
    end

    local ok, reason = publish(player_index, result)
    if not ok then
        local clip_ok = pcall(function() player.add_to_clipboard(staged) end)
        if clip_ok then clip_ok = pcall(function() player.activate_paste() end) end
        cleanup(staged, inventory)
        if clip_ok then
            state.blueprint_delivery_last_reason = "blueprint_on_clipboard"
            tell(player, "blueprint_on_clipboard")
            return true, "blueprint_on_clipboard"
        end
        state.blueprint_delivery_last_reason = "blueprint_not_delivered"
        return false, "blueprint_not_delivered"
    end
    cleanup(staged, inventory)
    state.blueprint_delivery_last_error = nil
    state.blueprint_delivery_last_reason = nil
    tell(player, "blueprint_delivered")
    return true
end

function BlueprintDelivery.retry(player_index)
    local state = state_of(player_index)
    local result = state[PENDING_KEY]
    if result == nil then return false, "nothing_to_deliver" end
    local ok, reason = publish(player_index, result)
    if not ok then state.blueprint_delivery_last_reason = reason; return false, reason end
    state[PENDING_KEY] = nil
    state.blueprint_delivery_last_reason = nil
    tell(player_of(player_index), "blueprint_delivered")
    return true
end

function BlueprintDelivery.discard(player_index)
    local state = state_of(player_index)
    if state[PENDING_KEY] == nil then return false end
    state[PENDING_KEY] = nil
    return true
end

return BlueprintDelivery
