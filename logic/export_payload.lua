--The debug export's contents and its encoding.
--
--This module is deliberately a reader. It takes one sheet snapshot, the last plain-data calculation that belongs
--to that sheet, and the catalog projection of that calculation's dependencies. It never asks the solver to run,
--never repairs a sheet, and never changes a setting.
--Snapshot requires gui.sheet and gui.sheet reaches this module back, so Snapshot arrives through the registry;
--Catalog has no such cycle and is required at load. Neither may be required from a handler: Factorio refuses it.
local Catalog = require "logic.catalog"
local Registry = require "logic.registry"

--Read on use, never at load: gui.sheet is still loading when this module is required through the export dialog.
local function Snapshot()
    return Registry.need("snapshot")
end

local ExportPayload = {}

ExportPayload.FORMAT = "rrc-sheet-debug"
ExportPayload.SCHEMA_VERSION = 1
ExportPayload.ENCODING = "zlib+base64"

local RESULT_MAP_KEYS = {
    "calculation_results", "last_calculations", "results_by_sheet", "sheet_results", "last_results",
    "calculation_by_sheet_id", "last_calculation_by_sheet_id", "calculation_results_by_sheet_id",
}
local RESULT_KEYS = {"last_calculation", "last_calculation_result", "last_result", "calculation_result", "calculation"}
local LIST_FIELDS = {
    targets = true, selection = true, columns = true, modules = true, beacons = true, burners = true,
    quality_loops = true, crafts = true, tiers = true, stages = true, rejected_values = true,
    missing_prototypes = true, diagnostics = true, qualities = true, recipes = true,
    quality_loop_stage_results = true, fluid_boxes = true, connections = true, positions = true,
}

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function non_finite_tag(value)
    if value ~= value then return {rrc_non_finite = "nan"} end
    if value == math.huge then return {rrc_non_finite = "infinity"} end
    return {rrc_non_finite = "-infinity"}
end

local function safe_member(object, key)
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function identity_name(value)
    local value_type = type(value)
    if value == nil then return nil end
    if value_type == "string" then return value end
    if value_type == "table" then
        return value.name or value.prototype or value.id or value.full_name
    end
    if value_type == "userdata" then
        return safe_member(value, "name") or safe_member(value, "prototype") or safe_member(value, "id")
    end
    return nil
end

-- Factorio's JSON helper has no separate Lua value for an empty array. A small marker keeps an empty list distinct
-- from an empty object after an offline JSON round trip while retaining #list == 0 for callers of the Lua payload.
local function empty_list(key)
    return LIST_FIELDS[key] == true
end

local function copy_json(value, active, key_hint)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then
        return finite(value) and value or non_finite_tag(value)
    end
    if value_type == "userdata" then
        local name = identity_name(value)
        return {
            identity = name,
            available = false,
            explanation = "LuaObject was not available as plain export data",
        }
    end
    if value_type == "function" then return {rrc_unsupported = "function"} end
    if value_type ~= "table" then return {rrc_unsupported = value_type} end

    active = active or {}
    if active[value] then return {rrc_cycle = true} end
    active[value] = true
    local result = {}
    for key, child in pairs(value) do
        local key_type = type(key)
        if key_type == "string" or key_type == "number" then
            result[key] = copy_json(child, active, key)
        end
    end
    active[value] = nil

    if next(result) == nil and empty_list(key_hint) then result.rrc_empty_list = true end
    return result
end

local function sorted_values(set)
    local values = {}
    for value, _ in pairs(set) do values[#values + 1] = value end
    table.sort(values)
    return values
end

local function add_name(set, value)
    local name = identity_name(value)
    if name ~= nil then set[name] = true end
end

local function add_quality(set, value)
    local quality
    if type(value) == "table" then quality = value.quality end
    if quality == nil and type(value) == "string" then quality = value end
    if quality ~= nil then set[identity_name(quality) or quality] = true end
end

local function add_full_name(references, full_name, parts)
    if type(full_name) ~= "string" then return end
    local kind, name = full_name:match("^(item|fluid)/(.+)$")
    if kind == "item" then
        references.items[name] = true
        if parts then add_quality(references.qualities, parts) end
        return
    elseif kind == "fluid" then
        references.fluids[name] = true
        return
    end

    -- QualityId.encode is length-prefixed and deliberately has no slash. The parts table is preferred because a
    -- result already carries it; this fallback keeps removed, above-normal targets requestable too.
    local item_length, rest = full_name:match("^item%-quality:(%d+):(.+)$")
    item_length = tonumber(item_length)
    if item_length and rest then
        local item = rest:sub(1, item_length)
        local quality_length, quality = rest:sub(item_length + 1):match("^(%d+):(.+)$")
        quality_length = tonumber(quality_length)
        if quality_length and quality then
            references.items[item] = true
            references.qualities[quality:sub(1, quality_length)] = true
        end
    end
end

local function add_setup(references, setup)
    if type(setup) ~= "table" then return end
    for _, module in ipairs(setup.modules or {}) do
        add_name(references.modules, module)
        add_quality(references.qualities, module)
    end
    for _, group in ipairs(setup.beacons or {}) do
        add_name(references.entities, group)
        add_quality(references.qualities, group)
        add_setup(references, {modules = group.modules})
    end
end

local function add_selection_entry(references, entry)
    if type(entry) ~= "table" then return end
    add_name(references.entities, entry.machine)
    add_quality(references.qualities, entry.machine)
    add_setup(references, {modules = entry.modules, beacons = entry.beacons})
end

local function add_reference_values(set, values, qualities)
    if values == nil then return end
    local value_type = type(values)
    if value_type == "string" or value_type == "userdata" then
        add_name(set, values)
        return
    end
    if value_type ~= "table" then return end
    if #values > 0 then
        for _, value in ipairs(values) do
            add_name(set, value)
            if qualities then add_quality(qualities, value) end
        end
        return
    end
    for key, value in pairs(values) do
        if value == true or value == nil then
            add_name(set, key)
        elseif type(value) == "string" then
            add_name(set, key)
            if qualities then qualities[value] = true end
        elseif type(value) == "table" then
            add_name(set, value)
            if qualities then add_quality(qualities, value) end
        end
    end
end

local function add_direct_references(references, direct)
    if type(direct) ~= "table" then return end
    add_reference_values(references.entities, direct.entities or direct.entity, references.qualities)
    add_reference_values(references.items, direct.items or direct.item, references.qualities)
    add_reference_values(references.fluids, direct.fluids or direct.fluid, references.qualities)
    add_reference_values(references.modules, direct.modules or direct.module, references.qualities)
    add_reference_values(references.qualities, direct.qualities or direct.quality)
    add_reference_values(references.items, direct.item_names, nil)
    add_reference_values(references.fluids, direct.fluid_names, nil)
    add_reference_values(references.modules, direct.module_names, nil)
    add_reference_values(references.qualities, direct.quality_names, nil)
end

local function add_map_full_names(references, map)
    for full_name, _ in pairs(map or {}) do add_full_name(references, full_name) end
end

local function references_for(snapshot, result)
    local references = {entities = {}, items = {}, fluids = {}, modules = {}, qualities = {}}
    for _, target in ipairs(snapshot.targets or {}) do
        add_full_name(references, target.full_name, target.parts)
    end
    if type(result) ~= "table" then return references end

    add_direct_references(references, result.referenced)
    add_map_full_names(references, result.solved_rates)
    add_map_full_names(references, result.unsolved_rates)
    for full_name, parts in pairs(result.product_parts or {}) do add_full_name(references, full_name, parts) end

    local selected_by_recipe = {}
    for _, entry in ipairs(snapshot.selection or {}) do selected_by_recipe[entry.recipe_name] = entry end
    for _, column in ipairs(result.columns or {}) do
        add_full_name(references, column.product_full_name)
        add_full_name(references, column.binding_full_name)
        add_map_full_names(references, column.net_amounts)
        add_name(references.entities, column.machine)
        add_quality(references.qualities, column.machine)
        add_name(references.entities, column.burner)
        add_quality(references.qualities, column.burner)
        add_selection_entry(references, selected_by_recipe[column.recipe_name])
        local loop = column.quality_loop
        if type(loop) == "table" then
            add_name(references.items, loop.item)
            add_quality(references.qualities, loop.quality)
            add_setup(references, loop.config)
            for _, stage in ipairs({loop.recycle, loop.assist}) do
                if type(stage) == "table" then
                    add_name(references.entities, stage.machine)
                    add_quality(references.qualities, stage.machine)
                    add_setup(references, stage.setup or stage)
                end
            end
            for _, stage in pairs(loop.crafts or {}) do
                if type(stage) == "table" then
                    add_name(references.entities, stage.machine)
                    add_quality(references.qualities, stage.machine)
                    add_setup(references, stage.setup or stage)
                end
            end
        end
    end
    return references
end

local function reference_options(references)
    return {
        entities = sorted_values(references.entities),
        items = sorted_values(references.items),
        fluids = sorted_values(references.fluids),
        modules = sorted_values(references.modules),
        qualities = sorted_values(references.qualities),
    }
end

local function matches_sheet(candidate, sheet_id)
    if type(candidate) ~= "table" then return false end
    return candidate.sheet_id == nil or candidate.sheet_id == sheet_id
end

local function unwrap_result(candidate)
    if type(candidate) ~= "table" then return nil, nil end
    if type(candidate.result) == "table" then return candidate.result, candidate end
    if type(candidate.calculation) == "table" then return candidate.calculation, candidate end
    return candidate, candidate
end

local function map_value(map, sheet_id)
    if type(map) ~= "table" then return nil end
    return map[sheet_id] or map[tostring(sheet_id)]
end

--W3's job/publish lane can keep the result under any of these documented-safe per-player slots. Reading them
--defensively also lets an older save export before that lane has been installed.
local function stored_calculation(player_data, sheet_id)
    if type(player_data) ~= "table" then return nil, nil, nil end
    for _, key in ipairs(RESULT_MAP_KEYS) do
        local candidate = map_value(player_data[key], sheet_id)
        if matches_sheet(candidate, sheet_id) then
            local result, wrapper = unwrap_result(candidate)
            if result then return result, wrapper, nil end
        end
    end
    for _, key in ipairs(RESULT_KEYS) do
        local candidate = player_data[key]
        if matches_sheet(candidate, sheet_id) then
            local result, wrapper = unwrap_result(candidate)
            if result then return result, wrapper, nil end
        end
    end

    local job = map_value(player_data.calc_jobs, sheet_id)
    if type(job) == "table" and matches_sheet(job, sheet_id) then
        if type(job.result) == "table" then return job.result, job, job end
        if job.done and job.ok == false then return {status = "failed", errors = job.errors}, job, job end
    end
    return nil, nil, job
end

local function setting_fingerprint(settings)
    if not rawget(_G, "settings") then return nil end
    local fingerprint = settings.fingerprint
    if type(fingerprint) == "string" then return fingerprint end
    if type(fingerprint) == "table" then return fingerprint.input or fingerprint.result end
    if type(settings.input_fingerprint) == "string" then return settings.input_fingerprint end
    if settings.targets ~= nil and settings.options ~= nil and settings.selection ~= nil then
        local ok, value = pcall(Snapshot().fingerprint, settings)
        if ok then return value end
    end
    return nil
end

local function result_fingerprint(result, wrapper)
    local candidates = {}
    local function add(candidate)
        if candidate ~= nil then candidates[#candidates + 1] = candidate end
    end
    if result then
        add(result.input_fingerprint)
        add(result.settings_fingerprint)
        add(result.fingerprint)
        add(result.settings)
        add(result.snapshot)
        add(result.inputs)
        add(result.input)
    end
    if wrapper then
        add(wrapper.settings)
        add(wrapper.snapshot)
        add(wrapper.inputs)
    end
    for _, candidate in ipairs(candidates) do
        if type(candidate) == "string" then return candidate end
        local fingerprint = setting_fingerprint(candidate)
        if fingerprint then return fingerprint end
    end
    return nil
end

local function settings_copy(source, fingerprint)
    local settings = type(source) == "table" and copy_json(source) or {}
    if not rawget(_G, "settings") then settings = {} end
    if type(source) == "table" and type(source.fingerprint) == "table" then
        settings.fingerprint = fingerprint
    elseif fingerprint ~= nil then
        settings.fingerprint = fingerprint
    end
    return settings
end

local function current_settings(snapshot)
    return {
        fingerprint = snapshot.fingerprint and snapshot.fingerprint.input or Snapshot().fingerprint(snapshot),
        targets = copy_json(snapshot.targets, nil, "targets"),
        options = copy_json(snapshot.options, nil, "options"),
        selection = copy_json(snapshot.selection, nil, "selection"),
        revisions = copy_json(snapshot.revisions, nil, "revisions"),
    }
end

local function result_settings(result, wrapper, result_fp)
    local source = result and (result.settings or result.snapshot or result.inputs or result.input)
        or wrapper and (wrapper.settings or wrapper.snapshot or wrapper.inputs)
    if source then return settings_copy(source, result_fp) end
    if result_fp then return {fingerprint = result_fp} end
    return {}
end

local function state_of(snapshot, result, result_fp, pending)
    local state = Snapshot().state_of(snapshot, result_fp, pending)
    -- Solver diagnostics are still a calculation result. They are failed only when they match the current input;
    -- once the sheet changes, the older result is stale, never failed-current and never current.
    if state == "current" and type(result) == "table"
        and (result.status == "failed" or result.status == "error" or result.status == "infeasible"
            or result.status == "unsolvable" or result.ok == false) then
        return "failed"
    end
    return state
end

local function calculation_copy(result)
    if type(result) ~= "table" then return {status = "not_computed"} end
    local calculation = {}
    for key, value in pairs(result) do
        if key ~= "settings" and key ~= "snapshot" and key ~= "inputs" and key ~= "input"
            and key ~= "referenced" and key ~= "fingerprint" and key ~= "input_fingerprint" then
            calculation[key] = copy_json(value, nil, key)
        end
    end
    if calculation.status == nil then calculation.status = result.ok == false and "failed" or "unknown" end

    local stages = {}
    for _, column in ipairs(result.columns or {}) do
        if type(column) == "table" and type(column.quality_loop) == "table" then
            stages[#stages + 1] = {
                recipe_name = column.recipe_name,
                product_full_name = column.product_full_name,
                key = column.quality_loop.key,
                stages = copy_json(column.quality_loop, nil, "stages"),
            }
        end
    end
    calculation.quality_loop_stage_results = stages
    return calculation
end

local function environment_of(player_index, references)
    local active_mods = {}
    if script ~= nil and type(script.active_mods) == "table" then
        for name, version in pairs(script.active_mods) do active_mods[name] = version end
    end

    local mod_settings = {}
    if rawget(_G, "settings") and settings.get_player_settings then
        local ok, player_settings = pcall(settings.get_player_settings, player_index)
        if ok and type(player_settings) == "table" then
            for name, setting in pairs(player_settings) do
                if type(setting) == "table" and setting.value ~= nil then
                    mod_settings[name] = copy_json(setting.value, nil, name)
                else
                    mod_settings[name] = copy_json(setting, nil, name)
                end
            end
        end
    end

    local research, quality_unlocks = {}, {}
    local player = rawget(_G, "game") and game.get_player and game.get_player(player_index) or nil
    local force = player and player.force
    if force ~= nil then
        for recipe_name, _ in pairs(references.recipes or {}) do
            local recipe = force.recipes and force.recipes[recipe_name]
            if recipe then research[recipe_name] = recipe.productivity_bonus end
        end
        for _, quality_name in ipairs(sorted_values(references.qualities)) do
            local quality = prototypes.quality and prototypes.quality[quality_name]
            if quality and type(force.is_quality_unlocked) == "function" then
                local ok, unlocked = pcall(force.is_quality_unlocked, quality_name)
                if ok then quality_unlocks[quality_name] = unlocked == true end
            end
        end
    end

    local base_version = active_mods.base
    local mod_version = script ~= nil and type(script.mod_name) == "string"
        and active_mods[script.mod_name] or active_mods["RRC-Fork"]
    return {
        base_game_version = base_version,
        active_mods = active_mods,
        mod_settings = mod_settings,
        force = {research = research, quality_unlocks = quality_unlocks},
        mod_version = mod_version,
    }
end

local function collect_recipe_names(references, result)
    references.recipes = references.recipes or {}
    for _, column in ipairs(result and result.columns or {}) do
        if type(column) == "table" and type(column.recipe_name) == "string" then
            references.recipes[column.recipe_name] = true
        end
    end
end

local function rejected_values(snapshot)
    local rejected = {}
    for _, target in ipairs(snapshot.targets or {}) do
        if target.valid == false then
            rejected[#rejected + 1] = {
                index = target.index, full_name = target.full_name, raw_text = target.raw_text,
                reason = target.reason,
            }
        end
    end
    return rejected
end

local function sorted_diagnostics(diagnostics)
    local result = {}
    for _, diagnostic in ipairs(diagnostics or {}) do result[#result + 1] = diagnostic end
    table.sort(result, function(a, b)
        local ak = tostring(a.code) .. "\0" .. tostring(a.subject) .. "\0" .. tostring(a.detail)
        local bk = tostring(b.code) .. "\0" .. tostring(b.subject) .. "\0" .. tostring(b.detail)
        return ak < bk
    end)
    return result
end

local function blueprint_attempt(player_data)
    if type(player_data) ~= "table" then return nil end
    return player_data.last_blueprint_attempt or player_data.blueprint_attempt or player_data.last_blueprint
end

function ExportPayload.build(player_index, sheet_flow)
    local snapshot = Snapshot().of_sheet(sheet_flow)
    local player_data = (type(storage) == "table" and type(storage[player_index]) == "table") and storage[player_index] or {}
    local result, wrapper, job = stored_calculation(player_data, snapshot.sheet_id)
    local active_job = map_value(player_data.calc_jobs, snapshot.sheet_id) or job
    local pending = type(active_job) == "table" and active_job.done ~= true
    local result_fp = result_fingerprint(result, wrapper)
    local state = state_of(snapshot, result, result_fp, pending)

    local references = references_for(snapshot, result)
    collect_recipe_names(references, result)
    local catalog, catalog_diagnostics = Catalog.for_export(player_index, reference_options(references))
    local current = current_settings(snapshot)
    local result_setting = result_settings(result, wrapper, result_fp)
    local sheet = copy_json(snapshot)
    sheet.state = state

    local diagnostics = {
        missing_prototypes = {}, rejected_values = rejected_values(snapshot), catalog = sorted_diagnostics(catalog_diagnostics),
    }
    for _, diagnostic in ipairs(catalog_diagnostics or {}) do
        if diagnostic.code == "CATALOG_MISSING_PROTOTYPE" or diagnostic.code == "CATALOG_MISSING_QUALITY" then
            diagnostics.missing_prototypes[#diagnostics.missing_prototypes + 1] = copy_json(diagnostic)
        end
    end
    local attempt = blueprint_attempt(player_data)
    if attempt ~= nil then diagnostics.last_blueprint_attempt = copy_json(attempt) end

    local environment = environment_of(player_index, references)
    local payload = {
        format = ExportPayload.FORMAT,
        schema_version = ExportPayload.SCHEMA_VERSION,
        encoding = ExportPayload.ENCODING,
        rrc_version = environment.mod_version,
        environment = environment,
        sheet = sheet,
        selection = copy_json(snapshot.selection, nil, "selection"),
        settings = {current = current, result = result_setting},
        state = state,
        calculation_tick = (result and (result.calculation_tick or result.tick))
            or (wrapper and (wrapper.calculation_tick or wrapper.tick)) or nil,
        calculation = calculation_copy(result),
        prototypes = copy_json(catalog),
        diagnostics = diagnostics,
    }
    return payload, state
end

--Returns the string, or nil plus a reason: a failed encode says so instead of handing back a short string.
function ExportPayload.encode(payload)
    if helpers == nil then return nil, "helpers_unavailable" end
    local ok_json, json = pcall(helpers.table_to_json, payload)
    if not ok_json then return nil, "json_encode_failed: " .. tostring(json) end
    local ok_encoded, encoded = pcall(helpers.encode_string, json)
    if not ok_encoded then return nil, "string_encode_failed: " .. tostring(encoded) end
    if type(encoded) ~= "string" or encoded == "" then return nil, "string_encode_failed" end
    return encoded
end

return ExportPayload
