--The last successful solver answer for each sheet.
--
--Only this module knows the saved shape.  Callers receive copies, so a blueprint preparation or a test cannot
--mutate the record that belongs to the next reader.  The copy boundary also turns the small number of prototype
--objects that can occur in a live solver result into their stable names before anything reaches storage.
local Registry = require "logic.registry"

local Calculation = {}

Calculation.SCHEMA_VERSION = 1
Calculation.STALE_REASON = "BP_REJ_SNAPSHOT_STALE"

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function integer(value, fallback)
    if not finite(value) then return fallback end
    return math.max(0, math.floor(value))
end

local function object_name(value)
    local ok, name = pcall(function() return value.name end)
    return ok and type(name) == "string" and name or nil
end

--The saved result is deliberately stricter than the solver's live answer.  In particular, a mock or engine
--LuaObject is represented by its stable name and a table with a metatable is never copied into storage.
local function copy_plain(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then return finite(value) and value or nil end
    if value_type == "userdata" then
        local name = object_name(value)
        return name and {name = name} or nil
    end
    if value_type ~= "table" or getmetatable(value) ~= nil then return nil end

    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        local key_type = type(key)
        if key_type == "string" or key_type == "number" then
            local copied = copy_plain(child, seen)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local function storage_root()
    local saved = rawget(_G, "storage")
    return type(saved) == "table" and saved or nil
end

local function player_data(player_index, create)
    local saved = storage_root()
    if not saved then return nil end
    local data = saved[player_index]
    if type(data) ~= "table" or getmetatable(data) ~= nil then
        if not create then return nil end
        data = {}
        saved[player_index] = data
    end
    return data
end

local function results_of(data, create)
    if not data then return nil end
    if type(data.calc_results) ~= "table" or getmetatable(data.calc_results) ~= nil then
        if not create then return nil end
        data.calc_results = {}
    end
    return data.calc_results
end

local function current_sheet(player_index, sheet_id)
    local data = player_data(player_index, false)
    local pane = data and data.sheet_section and data.sheet_section.sheet_pane
    for _, tab in ipairs(pane and pane.tabs or {}) do
        local sheet = tab and tab.content
        local tags = sheet and sheet.tags
        if sheet and tags and tags.hxrrc_sheet_id == sheet_id then return sheet end

        --Old or test-created sheets may not have the tag exposed.  The sheet module is process-local and is
        --therefore safe to reach through the registry, which avoids a late require from this reader.
        local Sheet = Registry.sheet
        if sheet and Sheet and type(Sheet.id_of) == "function" then
            local ok, id = pcall(Sheet.id_of, sheet)
            if ok and id == sheet_id then return sheet end
        end
    end
end

local function live_input_fingerprint(player_index, sheet_id)
    local sheet = current_sheet(player_index, sheet_id)
    local Snapshot = Registry.snapshot
    if not sheet or not Snapshot or type(Snapshot.of_sheet) ~= "function" then return nil end
    local ok, snapshot = pcall(Snapshot.of_sheet, sheet)
    local fingerprint = snapshot and snapshot.fingerprint
    return ok and type(fingerprint) == "table" and type(fingerprint.input) == "string" and fingerprint.input or nil
end

local function stored_input_fingerprint(data, sheet_id)
    if not data then return nil end
    for _, key in ipairs({"calc_input_fingerprints", "calculation_input_fingerprints", "sheet_input_fingerprints"}) do
        local fingerprints = data[key]
        if type(fingerprints) == "table" and type(fingerprints[sheet_id]) == "string" then
            return fingerprints[sheet_id]
        end
    end
    if type(data.input_fingerprint) == "string" then return data.input_fingerprint end
    if type(data.current_input_fingerprint) == "string" then return data.current_input_fingerprint end
end

local function current_values(player_index, sheet_id, supplied)
    local data = player_data(player_index, false)
    local current = {}
    supplied = type(supplied) == "table" and supplied or {}

    local supplied_revisions = supplied.revisions or supplied.current_revisions
    if type(supplied_revisions) == "table" then
        current.sheet_revision = supplied_revisions.sheet
        current.config_revision = supplied_revisions.config
    else
        current.sheet_revision = supplied.sheet_revision
        current.config_revision = supplied.config_revision
    end
    if current.sheet_revision == nil and data and type(data.sheet_revision) == "table" then
        current.sheet_revision = data.sheet_revision[sheet_id]
    end
    if current.config_revision == nil and data and data.config_revision ~= nil then
        current.config_revision = data.config_revision
    end

    local snapshot = supplied.snapshot
    local fingerprint = supplied.input_fingerprint
    if fingerprint == nil and type(supplied.fingerprint) == "string" then fingerprint = supplied.fingerprint end
    if fingerprint == nil and type(supplied.fingerprint) == "table" then fingerprint = supplied.fingerprint.input end
    if fingerprint == nil and type(snapshot) == "table" and type(snapshot.fingerprint) == "table" then
        fingerprint = snapshot.fingerprint.input
    end
    current.input_fingerprint = fingerprint or stored_input_fingerprint(data, sheet_id)
    if current.input_fingerprint == nil then current.input_fingerprint = live_input_fingerprint(player_index, sheet_id) end
    return current
end

local function stale(record, current)
    if current.sheet_revision ~= nil and record.sheet_revision ~= current.sheet_revision then return true end
    if current.config_revision ~= nil and record.config_revision ~= current.config_revision then return true end
    if current.input_fingerprint ~= nil and record.input_fingerprint ~= current.input_fingerprint then return true end
    return false
end

local function consume(budget)
    if type(budget) ~= "table" or type(budget.ops) ~= "number" or budget.ops == math.huge then return end
    budget.ops = math.max(0, budget.ops - 1)
end

local function has_budget(budget)
    return type(budget) ~= "table" or budget.ops == math.huge or (type(budget.ops) == "number" and budget.ops > 0)
end

local function published_tick()
    local game_global = rawget(_G, "game")
    if not game_global then return 0 end
    local ok, tick = pcall(function() return game_global.tick end)
    return ok and finite(tick) and tick or 0
end

local function normalized_record(record)
    if type(record) ~= "table" or getmetatable(record) ~= nil then return nil end
    if not finite(record.player_index) or type(record.result) ~= "table" then return nil end
    if type(record.sheet_id) ~= "string" and not finite(record.sheet_id) then return nil end

    local result = copy_plain(record.result)
    if type(result) ~= "table" then return nil end
    return {
        schema_version = Calculation.SCHEMA_VERSION,
        player_index = integer(record.player_index, 0),
        sheet_id = record.sheet_id,
        sheet_revision = integer(record.sheet_revision, 0),
        config_revision = integer(record.config_revision, 0),
        input_fingerprint = type(record.input_fingerprint) == "string" and record.input_fingerprint or nil,
        result = result,
        published_tick = integer(record.published_tick, published_tick()),
    }
end

--Returns a fresh plain record.  The optional current value is accepted by preparation readers that already hold
--a snapshot; with no current value, revisions and the live sheet fingerprint are read from the normal registries.
--The optional budget charges one bounded copy operation, so a preparation job cannot read for free.
function Calculation.get(player_index, sheet_id, current, budget, input_fingerprint)
    if type(current) == "table" and current.ops ~= nil and current.revisions == nil and current.snapshot == nil then
        budget, current = current, nil
    elseif type(current) == "number" then
        current, budget = {sheet_revision = current, config_revision = budget, input_fingerprint = input_fingerprint}, nil
    elseif type(budget) == "string" and input_fingerprint == nil then
        local supplied_fingerprint = budget
        budget = nil
        local supplied_current = current
        current = {}
        if type(supplied_current) == "table" then
            for key, value in pairs(supplied_current) do current[key] = value end
        end
        current.input_fingerprint = supplied_fingerprint
    end

    local data = player_data(player_index, false)
    local results = results_of(data, false)
    local record = results and results[sheet_id]
    if type(record) ~= "table" then return nil end
    local current_values_now = current_values(player_index, sheet_id, current)
    if stale(record, current_values_now) then return nil, Calculation.STALE_REASON end
    if not has_budget(budget) then return nil, "budget" end
    local copied = copy_plain(record)
    if type(copied) ~= "table" then return nil end
    consume(budget)
    return copied
end

--Writes only a normalized, plain-data record.  The caller supplies the job budget when this is the terminal
--publication step; the report is already committed before this function is reached, so all successful paths use
--one bounded copy operation and all unsuccessful paths leave the previous record untouched.
function Calculation.publish(record, budget)
    if not has_budget(budget) then return false, "budget" end
    local normalized = normalized_record(record)
    if not normalized then return false, "invalid_record" end
    local data = player_data(normalized.player_index, true)
    local results = results_of(data, true)
    results[normalized.sheet_id] = normalized
    consume(budget)
    return true
end

function Calculation.forget(player_index, sheet_id)
    local data = player_data(player_index, false)
    local results = results_of(data, false)
    if not results or results[sheet_id] == nil then return false end
    results[sheet_id] = nil
    return true
end

--Coordinator-owned reset, configuration-change and player-removal handlers use this convenience operation.  It
--does not copy anything and leaves the player's other saved data intact.
function Calculation.forget_player(player_index)
    local data = player_data(player_index, false)
    if not data or data.calc_results == nil then return false end
    data.calc_results = nil
    return true
end

--A configuration change rewrites the prototypes every stored result was computed from, so every record of every
--player goes at once. Walking storage is the only way to reach players who are offline right now.
function Calculation.forget_all()
    local dropped = 0
    for key, data in pairs(storage) do
        if type(key) == "number" and type(data) == "table" and data.calc_results ~= nil then
            data.calc_results = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

Registry.calculation = Calculation

return Calculation
