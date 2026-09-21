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

--`calc_results` is where contracts §19 says a finished calculation publishes its record. It is listed first, and
--the rest are older spellings kept so an export taken on a save from an older build still finds its numbers.
local RESULT_MAP_KEYS = {
    "calc_results",
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

local CAPTURE_VECTOR_FIELDS = {
    pickup_offset = true, drop_offset = true, drop_position = true,
    left_top = true, right_bottom = true, alt_position = true, position = true,
}

local function capture_error(errors, seen, path, reason)
    if seen[path] then return end
    seen[path] = true
    errors[#errors + 1] = {field = path, reason = reason}
end

local function capture_vector(value)
    if type(value) ~= "table" then return nil, "unsupported vector representation" end
    local x, y = value.x, value.y
    if x == nil and y == nil then x, y = value[1], value[2] end
    if type(x) ~= "number" or type(y) ~= "number"
        or not finite(x) or not finite(y) then
        if next(value) == nil then return nil, "empty vector" end
        return nil, "vector is missing a finite x or y component"
    end
    return {x = x, y = y}
end

--PreparedInput is normally already plain data, but old captures can contain the same malformed geometry that the
--catalog boundary used to publish. Normalize supported keyed/array vectors here too; invalid geometry is omitted
--from the replay payload and named as an incomplete capture, never turned into a default or an empty object.
local function capture_copy(value, key_hint, errors, seen, path)
    if CAPTURE_VECTOR_FIELDS[key_hint] then
        local vector, reason = capture_vector(value)
        if vector ~= nil then return vector end
        capture_error(errors, seen, path, reason)
        return nil
    end
    if key_hint == "positions" then
        if type(value) ~= "table" or #value == 0 then
            capture_error(errors, seen, path, type(value) == "table" and "empty vector list" or "missing vector list")
            return nil
        end
    elseif key_hint == "collision_box" then
        if type(value) ~= "table" or value.left_top == nil or value.right_bottom == nil then
            capture_error(errors, seen, path, "missing collision-box vector")
            return nil
        end
    end

    local value_type = type(value)
    if value == nil or value_type ~= "table" then return copy_json(value, nil, key_hint) end
    seen = seen or {}
    if seen[value] then return {rrc_cycle = true} end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local child_hint = key
            if key_hint == "positions" and type(key) == "number" then child_hint = "position" end
            local child_path = path .. "." .. tostring(key)
            result[key] = capture_copy(child, child_hint, errors, seen, child_path)
        end
    end
    seen[value] = nil
    return result
end

local function require_capture_field(container, field, path, errors, seen)
    if type(container) == "table" and container[field] == nil then
        capture_error(errors, seen, path .. "." .. field, "missing required geometry")
    end
end

local function capture_geometry_copy(prepared)
    local errors, seen = {}, {}
    local copied = capture_copy(prepared, nil, errors, seen, "prepared_input")
    local catalog = type(prepared) == "table" and prepared.catalog
    if type(catalog) == "table" then
        require_capture_field(catalog.inserter, "pickup_offset", "prepared_input.catalog.inserter", errors, seen)
        require_capture_field(catalog.inserter, "drop_offset", "prepared_input.catalog.inserter", errors, seen)
        require_capture_field(catalog.inserter, "drop_position", "prepared_input.catalog.inserter", errors, seen)
        for entity_name, entity in pairs(catalog.entity or {}) do
            local entity_path = "prepared_input.catalog.entity." .. tostring(entity_name)
            local box = type(entity) == "table" and entity.collision_box
            if type(box) == "table" then
                require_capture_field(box, "left_top", entity_path .. ".collision_box", errors, seen)
                require_capture_field(box, "right_bottom", entity_path .. ".collision_box", errors, seen)
            end
            for box_index, fluid_box in ipairs(type(entity) == "table" and entity.fluid_boxes or {}) do
                for connection_index, connection in ipairs(fluid_box.connections or {}) do
                    require_capture_field(connection, "positions",
                        entity_path .. ".fluid_boxes[" .. box_index .. "].connections[" .. connection_index .. "]",
                        errors, seen)
                end
            end
        end
    end
    return copied, errors
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

local function add_recipe_reference(references, value)
    local name = identity_name(value)
    if type(name) ~= "string" then return end
    if name:sub(1, 11) == "hxrrc-burn:" or name:sub(1, 13) == "quality-loop:" then return end
    references.recipes[name] = true
end

local function add_stage_references(references, stage)
    if type(stage) ~= "table" then return end
    add_recipe_reference(references, stage.recipe_name or stage.recipe)
    add_name(references.entities, stage.machine)
    add_quality(references.qualities, stage.machine)
    add_setup(references, stage.setup or stage)
end

local function add_quality_loop_references(references, loop)
    if type(loop) ~= "table" then return end
    add_recipe_reference(references, loop.craft_recipe_name)
    add_recipe_reference(references, loop.recycle_recipe_name)
    add_stage_references(references, loop.config)
    add_stage_references(references, loop.recycle)
    add_stage_references(references, loop.assist)
    for _, stage in pairs(loop.crafts or {}) do add_stage_references(references, stage) end
    for _, stage in pairs(loop.tiers or {}) do add_stage_references(references, stage) end
    if type(loop.config) == "table" then
        for _, stage in pairs(loop.config.crafts or {}) do add_stage_references(references, stage) end
    end
end

local function references_for(snapshot, result)
    local references = {entities = {}, items = {}, fluids = {}, modules = {}, qualities = {}, recipes = {}}
    for _, target in ipairs(snapshot.targets or {}) do
        add_full_name(references, target.full_name, target.parts)
    end
    --A current selection is a dependency even before a calculation exists.  Keeping this outside the result guard
    --prevents a no-result export from silently losing the recipe and setup the player selected.
    for _, entry in ipairs(snapshot.selection or {}) do
        if type(entry) == "table" then
            if type(entry.recipe_name) == "string" then references.recipes[entry.recipe_name] = true end
            add_selection_entry(references, entry)
        end
    end
    for _, loop in ipairs(snapshot.selection and snapshot.selection.quality_loops or {}) do
        add_quality_loop_references(references, loop)
    end
    if type(result) ~= "table" then return references end

    add_direct_references(references, result.referenced)
    add_map_full_names(references, result.solved_rates)
    add_map_full_names(references, result.unsolved_rates)
    for full_name, parts in pairs(result.product_parts or {}) do add_full_name(references, full_name, parts) end

    local selected_by_recipe = {}
    for _, entry in ipairs(snapshot.selection or {}) do
        selected_by_recipe[entry.recipe_name] = entry
        if entry.product_full_name ~= nil then selected_by_recipe[entry.product_full_name] = entry end
        if entry.row_id ~= nil then selected_by_recipe[entry.row_id] = entry end
    end
    for _, column in ipairs(result.columns or {}) do
        add_recipe_reference(references, column.recipe_name or column.recipe)
        add_full_name(references, column.product_full_name)
        add_full_name(references, column.binding_full_name)
        add_map_full_names(references, column.net_amounts)
        add_name(references.entities, column.machine)
        add_quality(references.qualities, column.machine)
        add_name(references.entities, column.burner)
        add_quality(references.qualities, column.burner)
        add_selection_entry(references, selected_by_recipe[column.product_full_name or column.binding_full_name]
            or selected_by_recipe[column.recipe_name])
        add_setup(references, column.setup or {modules = column.modules, beacons = column.beacons})
        local loop = column.quality_loop
        if type(loop) == "table" then
            add_quality_loop_references(references, loop)
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
            for _, stage in pairs(loop.tiers or {}) do
                if type(stage) == "table" then
                    add_name(references.entities, stage.machine)
                    add_quality(references.qualities, stage.machine)
                    add_setup(references, stage.setup or stage)
                    if type(stage.recipe_name) == "string" then references.recipes[stage.recipe_name] = true end
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
        recipes = sorted_values(references.recipes),
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
        --A contracts §19 record keeps the fingerprint it was computed against on the record itself, beside the
        --result. Without this the export finds the numbers and still calls the sheet not calculated.
        add(wrapper.input_fingerprint)
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
    if type(source) == "table" and type(source.fingerprint) == "table" then
        settings.fingerprint = fingerprint
    elseif fingerprint ~= nil then
        settings.fingerprint = fingerprint
    end
    return settings
end

local function counted_modules(modules)
    if modules == nil then return nil end
    local result = {}
    for _, module in ipairs(modules or {}) do
        local name = identity_name(module and (module.name or module))
        if name ~= nil then
            local quality = type(module) == "table" and module.quality or nil
            quality = identity_name(quality) or quality or "normal"
            local count = type(module) == "table" and module.count or nil
            count = type(count) == "number" and count or 1
            local previous = result[#result]
            if previous and previous.name == name and previous.quality == quality then
                previous.count = previous.count + count
            else
                result[#result + 1] = {name = name, quality = quality, count = count}
            end
        end
    end
    return result
end

--Snapshot is intentionally slot-shaped for the GUI. The export is replay-shaped: repeated slots and legacy
--counted entries are represented by one name/quality/count fact, while row order remains meaningful.
local function beacons_for_export(beacons)
    if beacons == nil then return nil end
    local result = {}
    for index, group in ipairs(beacons or {}) do
        local beacon = {}
        for key, value in pairs(group) do beacon[key] = value end
        beacon.name = identity_name(group.name or group.type)
        beacon.type = beacon.type or beacon.name
        beacon.quality = identity_name(group.quality) or group.quality or "normal"
        beacon.modules = counted_modules(group.modules)
        result[index] = beacon
    end
    return result
end

local function setup_for_export(setup)
    if type(setup) ~= "table" then return nil end
    local result = {}
    for key, value in pairs(setup) do result[key] = value end
    result.modules = counted_modules(setup.modules)
    result.beacons = beacons_for_export(setup.beacons)
    return result
end

local function stage_for_export(stage)
    if type(stage) ~= "table" then return stage end
    local result = {}
    for key, value in pairs(stage) do result[key] = value end
    result.modules = counted_modules(stage.modules)
    result.beacons = beacons_for_export(stage.beacons)
    if type(stage.setup) == "table" then result.setup = setup_for_export(stage.setup) end
    if type(stage.settings) == "table" then result.settings = stage_for_export(stage.settings) end
    return result
end

local function quality_loops_for_export(loops)
    local result = {}
    for index, loop in ipairs(loops or {}) do
        local copy = {}
        for key, value in pairs(loop) do copy[key] = value end
        copy.config = stage_for_export(loop.config)
        copy.recycle = stage_for_export(loop.recycle)
        copy.assist = stage_for_export(loop.assist)
        copy.crafts = {}
        for craft_index, craft in ipairs(loop.crafts or {}) do
            local craft_copy = {}
            for key, value in pairs(craft) do craft_copy[key] = value end
            craft_copy.settings = stage_for_export(craft.settings)
            copy.crafts[craft_index] = craft_copy
        end
        result[index] = copy
    end
    return result
end

local function selection_for_export(snapshot, player_data)
    local result = {}
    local setups = type(player_data) == "table" and player_data.module_setups_by_recipe_name or {}
    local row_setups = type(player_data) == "table" and (player_data.module_setups_by_product_full_name
        or player_data.module_setups_by_row_id) or {}
    for index, entry in ipairs(snapshot.selection or {}) do
        local copy = {}
        for key, value in pairs(entry) do copy[key] = value end
        local row_key = type(entry) == "table" and (entry.product_full_name or entry.row_id) or nil
        local setup = row_key and row_setups[row_key] or nil
        if setup == nil then setup = type(entry) == "table" and setups[entry.recipe_name] or nil end
        if type(setup) == "table" then
            copy.modules = setup.modules ~= nil and counted_modules(setup.modules) or nil
            copy.beacons = setup.beacons ~= nil and beacons_for_export(setup.beacons) or nil
        end
        result[index] = copy
    end
    --The auxiliary bindings are still part of the selection record; retaining them means a quality-loop replay
    --does not need to infer its stages from the visible rows.
    result.burners = snapshot.selection.burners
    result.quality_loops = quality_loops_for_export(snapshot.selection.quality_loops)
    return result
end

local function current_settings(snapshot, selection)
    return {
        sheet_id = snapshot.sheet_id,
        fingerprint = snapshot.fingerprint and snapshot.fingerprint.input or Snapshot().fingerprint(snapshot),
        targets = copy_json(snapshot.targets, nil, "targets"),
        options = copy_json(snapshot.options, nil, "options"),
        selection = copy_json(selection or snapshot.selection, nil, "selection"),
        revisions = copy_json(snapshot.revisions, nil, "revisions"),
    }
end

local function result_settings(result, wrapper, result_fp)
    local source = result and (result.settings or result.snapshot or result.inputs or result.input)
        or wrapper and (wrapper.settings or wrapper.snapshot or wrapper.inputs)
    if source then
        local settings = settings_copy(source, result_fp)
        local revisions = type(settings.revisions) == "table" and settings.revisions or {}
        local changed = false
        for _, owner in ipairs({result, wrapper}) do
            if type(owner) == "table" then
                if type(owner.revisions) == "table" then
                    for key, value in pairs(owner.revisions) do
                        if revisions[key] == nil and value ~= nil then revisions[key] = value; changed = true end
                    end
                end
                for _, pair in ipairs({
                    {name = "sheet", keys = {"sheet_revision"}},
                    {name = "config", keys = {"config_revision"}},
                    {name = "solver", keys = {"solver_revision", "calculation_revision"}},
                }) do
                    for _, key in ipairs(pair.keys) do
                        if owner[key] ~= nil and revisions[pair.name] == nil then
                            revisions[pair.name] = owner[key]; changed = true; break
                        end
                    end
                end
            end
        end
        if changed then settings.revisions = revisions end
        return settings
    end
    local settings = {fingerprint = result_fp}
    local sheet_id = result and result.sheet_id or wrapper and wrapper.sheet_id
    local sheet_revision = result and (result.sheet_revision or result.revisions and result.revisions.sheet)
        or wrapper and (wrapper.sheet_revision or wrapper.revisions and wrapper.revisions.sheet)
    local config_revision = result and (result.config_revision or result.revisions and result.revisions.config)
        or wrapper and (wrapper.config_revision or wrapper.revisions and wrapper.revisions.config)
    if sheet_id ~= nil then settings.sheet_id = sheet_id end
    local solver_revision = result and (result.solver_revision or result.calculation_revision)
        or wrapper and (wrapper.solver_revision or wrapper.calculation_revision)
    if sheet_revision ~= nil or config_revision ~= nil or solver_revision ~= nil then
        settings.revisions = {sheet = sheet_revision, config = config_revision, solver = solver_revision}
    end
    return settings
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

local function finite_number(value)
    return type(value) == "number" and finite(value) and value or nil
end

local EFFECT_NAMES = {"consumption", "speed", "productivity", "pollution", "quality"}

local function module_effect(name, quality, catalog)
    local item = rawget(_G, "prototypes") and prototypes.item and prototypes.item[name]
    if item and type(item.get_module_effects) == "function" then
        local ok, effects = pcall(item.get_module_effects, quality == "normal" and nil or quality)
        if ok and type(effects) == "table" then return effects, true end
    end
    local projected = catalog and catalog.module and catalog.module[name]
    if projected and projected.effects then return projected.effects, true end
    local projected_item = catalog and catalog.item and catalog.item[name]
    if projected_item and projected_item.module_effects then return projected_item.module_effects, true end
    return {}, false
end

local function setup_effects(setup, catalog)
    local totals = {}
    local known = true
    for _, effect in ipairs(EFFECT_NAMES) do totals[effect] = 0 end
    local function add_modules(modules, multiplier)
        for _, module in ipairs(modules or {}) do
            local count = finite_number(module.count) or 1
            local module_value = type(module) == "table" and module.name or module
            local module_quality = type(module) == "table" and module.quality or nil
            local effects, available = module_effect(identity_name(module_value), identity_name(module_quality) or module_quality or "normal", catalog)
            if not available then known = false end
            for _, effect in ipairs(EFFECT_NAMES) do
                totals[effect] = totals[effect] + (finite_number(effects[effect]) or 0) * count * multiplier
            end
        end
    end
    add_modules(setup and setup.modules, 1)
    local by_name, total = {}, 0
    for _, group in ipairs(setup and setup.beacons or {}) do
        local count = finite_number(group.count) or finite_number(group.count_per_machine) or 1
        local name = identity_name(group.name or group.type)
        by_name[name] = (by_name[name] or 0) + count
        total = total + count
    end
    for _, group in ipairs(setup and setup.beacons or {}) do
        local name = identity_name(group.name or group.type)
        local quality = identity_name(group.quality) or group.quality or "normal"
        local beacon = rawget(_G, "prototypes") and prototypes.entity and prototypes.entity[name]
        local projected = catalog and catalog.beacon and catalog.beacon[name] or {}
        if not beacon and next(projected) == nil then known = false end
        local level = 0
        local quality_prototype = rawget(_G, "prototypes") and prototypes.quality and prototypes.quality[quality]
        if quality_prototype then level = finite_number(quality_prototype.level) or 0 end
        local effectivity = finite_number(beacon and beacon.distribution_effectivity)
            or finite_number(projected.distribution_effectivity) or 1
        effectivity = effectivity + (finite_number(beacon and beacon.distribution_effectivity_bonus_per_quality_level) or 0) * level
        local reaching = (beacon and beacon.beacon_counter == "same_type") and by_name[name] or total
        local profile = beacon and beacon.profile or projected.profile
        local sample = 1
        if type(profile) == "table" and #profile > 0 then sample = profile[math.min(math.max(1, reaching), #profile)] or 1 end
        local count = finite_number(group.count) or finite_number(group.count_per_machine) or 1
        add_modules(group.modules, count * effectivity * sample)
    end
    return totals, known
end

local function selected_setup(player_data, selection_by_recipe, column)
    if type(column.setup) == "table" then return column.setup end
    if column.modules ~= nil or column.beacons ~= nil then
        return {modules = column.modules or {}, beacons = column.beacons or {}}
    end
    local row_setups = type(player_data) == "table" and (player_data.module_setups_by_product_full_name
        or player_data.module_setups_by_row_id) or nil
    local row_key = column.product_full_name or column.binding_full_name or column.row_id
    if type(row_setups) == "table" and row_key ~= nil and type(row_setups[row_key]) == "table" then
        return row_setups[row_key]
    end
    local stored = type(player_data) == "table" and player_data.module_setups_by_recipe_name
        and player_data.module_setups_by_recipe_name[column.recipe_name]
    if stored then return stored end
    local selected = selection_by_recipe[column.product_full_name or column.binding_full_name]
        or selection_by_recipe[column.recipe_name]
    return selected and {modules = selected.modules or {}, beacons = selected.beacons or {}} or {modules = {}, beacons = {}}
end

local function derived_calculation(result, snapshot, player_data, catalog)
    local derived = {columns = {}, machine_counts = {}, effects = {}, energy = 0, pollution = 0, energy_known = false, pollution_known = false}
    if type(result) ~= "table" then return derived end
    local selection_by_recipe = {}
    for _, entry in ipairs(snapshot.selection or {}) do
        selection_by_recipe[entry.recipe_name] = entry
        if entry.product_full_name ~= nil then selection_by_recipe[entry.product_full_name] = entry end
        if entry.row_id ~= nil then selection_by_recipe[entry.row_id] = entry end
    end
    for index, column in ipairs(result.columns or {}) do
        if type(column) == "table" and type(column.recipe_name) == "string" then
            local rate = result.recipe_rates and finite_number(result.recipe_rates[column.recipe_name])
                or finite_number(column.recipe_rate) or finite_number(column.rate)
            local recipe = catalog and catalog.recipe and catalog.recipe[column.recipe_name]
            local selected = selection_by_recipe[column.recipe_name]
            local machine = column.machine or (selected and selected.machine)
            local machine_name = identity_name(machine)
            local machine_quality = type(machine) == "table" and (identity_name(machine.quality) or machine.quality) or "normal"
            local setup = selected_setup(player_data, selection_by_recipe, column)
            local effects, effects_known = setup_effects(setup, catalog)
            if type(column.effects) == "table" then
                effects, effects_known = column.effects, true
            end
            local derived_column = {}
            if effects_known then derived_column.effects = effects end
            local entity = rawget(_G, "prototypes") and prototypes.entity and prototypes.entity[machine_name]
            local projected_entity = catalog and catalog.entity and catalog.entity[machine_name]
            local crafting_speed = projected_entity and projected_entity.crafting_speed
            local energy_w = projected_entity and projected_entity.energy_usage_w
            local pollution_per_min = projected_entity and projected_entity.pollution_per_min
            if entity then
                local quality_argument = machine_quality == "normal" and nil or machine_quality
                if type(entity.get_crafting_speed) == "function" then
                    local ok, value = pcall(entity.get_crafting_speed, quality_argument)
                    if ok then crafting_speed = value end
                end
                if type(entity.get_max_energy_usage) == "function" then
                    local ok, value = pcall(entity.get_max_energy_usage, quality_argument)
                    if ok then energy_w = value * 60 end
                end
                local source = entity.electric_energy_source_prototype or entity.burner_prototype
                local emissions = source and source.emissions_per_joule
                if emissions and energy_w then pollution_per_min = energy_w / 60 * (emissions.pollution or 0) * 60 end
            end
            local speed_multiplier = math.max(0.2, 1 + (finite_number(effects.speed) or 0))
            local machine_count = finite_number(column.machine_count or column.calculated_machine_count)
            local supplied_machine_rate = finite_number(column.crafts_per_second_per_machine or column.machine_rate)
            if machine_count == nil and rate and supplied_machine_rate and supplied_machine_rate > 0 then
                machine_count = rate / supplied_machine_rate
            elseif machine_count == nil and rate and recipe and finite_number(recipe.energy) and finite_number(crafting_speed) and crafting_speed > 0 then
                machine_count = rate * recipe.energy / (crafting_speed * speed_multiplier)
            end
            if machine_count then
                derived_column.machine_count = machine_count
                derived.machine_counts[column.recipe_name] = machine_count
            end
            if effects_known then derived.effects[column.recipe_name] = effects end
            local consumption_multiplier = math.max(0.2, 1 + (finite_number(effects.consumption) or 0))
            local pollution_multiplier = math.max(0.2, 1 + (finite_number(effects.pollution) or 0))
            local column_energy, column_pollution
            if machine_count and effects_known and finite_number(energy_w) then
                column_energy = energy_w * machine_count * consumption_multiplier
                for _, group in ipairs(setup.beacons or {}) do
                    local beacon_name = identity_name(group.name or group.type)
                    local beacon = rawget(_G, "prototypes") and prototypes.entity and prototypes.entity[beacon_name]
                    local beacon_energy = beacon and beacon.energy_usage and beacon.energy_usage * 60
                        or catalog and catalog.entity and catalog.entity[beacon_name] and catalog.entity[beacon_name].energy_usage_w
                    local count = finite_number(group.count) or finite_number(group.count_per_machine) or 1
                    local sharing = finite_number(group.sharing) or 1
                    local quality = identity_name(group.quality) or group.quality or "normal"
                    local quality_prototype = rawget(_G, "prototypes") and prototypes.quality and prototypes.quality[quality]
                    local power_multiplier = quality_prototype and finite_number(quality_prototype.beacon_power_usage_multiplier) or 1
                    if beacon_energy then column_energy = column_energy + count * machine_count / sharing * beacon_energy * power_multiplier end
                end
            end
            if machine_count and effects_known and finite_number(pollution_per_min) then
                column_pollution = pollution_per_min * machine_count * pollution_multiplier * consumption_multiplier
            end
            if column_energy then derived_column.energy = column_energy; derived.energy = derived.energy + column_energy; derived.energy_known = true end
            if column_pollution then derived_column.pollution = column_pollution; derived.pollution = derived.pollution + column_pollution; derived.pollution_known = true end
            derived.columns[index] = derived_column
        end
    end
    return derived
end

local function calculation_copy(result, snapshot, derived)
    if type(result) ~= "table" then
        return {status = "not_computed", round_up = snapshot and snapshot.options and snapshot.options.round_up == true}
    end
    local calculation = {}
    for key, value in pairs(result) do
        if key ~= "settings" and key ~= "snapshot" and key ~= "inputs" and key ~= "input"
            and key ~= "referenced" and key ~= "fingerprint" and key ~= "input_fingerprint" then
            calculation[key] = copy_json(value, nil, key)
        end
    end
    if calculation.status == nil then calculation.status = result.ok == false and "failed" or "unknown" end
    --The solver calls the world-side remainder unsolved_rates. The replay contract names its meaning so a reader
    --does not have to guess whether the rates were solved, external, or simply omitted.
    if calculation.external_rates == nil and result.unsolved_rates ~= nil then
        calculation.external_rates = copy_json(result.unsolved_rates, nil, "external_rates")
    end
    if calculation.round_up == nil and snapshot and snapshot.options then
        calculation.round_up = snapshot.options.round_up == true
    end
    if derived then
        if calculation.machine_counts == nil and next(derived.machine_counts) ~= nil then
            calculation.machine_counts = copy_json(derived.machine_counts)
        end
        if calculation.effects == nil and next(derived.effects) ~= nil then
            calculation.effects = copy_json(derived.effects)
        end
        if calculation.energy == nil and derived.energy_known then calculation.energy = derived.energy end
        if calculation.pollution == nil and derived.pollution_known then calculation.pollution = derived.pollution end
        for index, column in ipairs(calculation.columns or {}) do
            local facts = derived.columns[index]
            if facts then
                for _, key in ipairs({"machine_count", "effects", "energy", "pollution"}) do
                    if column[key] == nil and facts[key] ~= nil then column[key] = copy_json(facts[key], nil, key) end
                end
            end
        end
    end

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
    local surface = player and identity_name(safe_member(player, "surface")) or nil
    local force_name = force and identity_name(force) or nil
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
        force_name = force_name,
        surface = surface,
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

local function add_generation_id(ids, seen, value)
    if value == nil then return end
    local value_type = type(value)
    if value_type ~= "string" and value_type ~= "number" then return end
    if not seen[value] then
        seen[value] = true
        ids[#ids + 1] = value
    end
end

local function generation_id_from(value, ids, seen)
    if type(value) ~= "table" then return end
    for _, key in ipairs({"generation_id", "generation_job_id", "job_id", "id"}) do
        add_generation_id(ids, seen, value[key])
    end
    generation_id_from(value.input, ids, seen)
    generation_id_from(value.state, ids, seen)
end

--The generation service is loaded by control.lua after this module. It is therefore read through the registry at
--use time, never required from the export handler. Older saves and the focused export tests do not publish that
--entry; in those worlds there simply is no prepared capture to add.
--The service's own per-sheet lookup, when this build has one. It is asked first and by sheet, because every
--other route here is transient: logic/jobs.lua:405-407 clears data.blueprint_job while servicing a job and
--:423-426 restores it only for a job that is not terminal, which is exactly the moment a player exports a
--failure. A lookup that answers for a different sheet is refused rather than borrowed.
local function service_attempt(generation, player_index, sheet_id)
    if type(generation) ~= "table" then return nil end
    local reader = generation.lookup or generation.attempt or generation.attempt_for_sheet
    if type(reader) ~= "function" then return nil end
    local ok, attempt = pcall(reader, player_index, sheet_id)
    if not ok or type(attempt) ~= "table" then return nil end
    --The service answers for every sheet, including one that was never generated, and says so plainly. That
    --answer is not an attempt: the export keeps naming absence in its own vocabulary, so a reader never has to
    --know which module happened to report it.
    if attempt.present == false or attempt.found == false then return nil end
    if attempt.status == "absent" or attempt.state == "absent" then return nil end
    local owner = attempt.sheet_id
    if owner ~= nil and owner ~= sheet_id then return nil end
    return attempt
end

local function generation_capture(player_index, player_data, sheet_id)
    local ok_service, generation = pcall(Registry.need, "generation")
    if not ok_service or type(generation) ~= "table" or type(generation.capture) ~= "function" then return nil end

    local ids, seen = {}, {}
    local attempt = service_attempt(generation, player_index, sheet_id)
    if attempt ~= nil then
        add_generation_id(ids, seen, attempt.generation_id)
        add_generation_id(ids, seen, attempt.job_id)
    end
    for _, key in ipairs({"generation_id", "last_generation_id", "last_blueprint_generation_id"}) do
        add_generation_id(ids, seen, player_data[key])
    end
    for _, key in ipairs({"blueprint_job"}) do
        generation_id_from(player_data[key], ids, seen)
    end

    for _, generation_id in ipairs(ids) do
        local ok_capture, capture, source_kind, provenance = pcall(generation.capture, player_index, generation_id)
        if ok_capture and type(capture) == "table" then
            local prepared = type(capture.prepared_input) == "table" and capture.prepared_input
                or type(capture.prepared) == "table" and capture.prepared or capture
            local captured_sheet_id = type(prepared) == "table" and (prepared.sheet_id
                or type(prepared.snapshot) == "table" and prepared.snapshot.sheet_id) or nil
            if captured_sheet_id == nil or captured_sheet_id == sheet_id then
                return capture, source_kind, provenance
            end
        end
    end
    return nil
end

local function generation_attempt(player_index, player_data, sheet_id, capture, provenance)
    local function mark_missing_spacing(attempt)
        if type(attempt) ~= "table" or attempt.grid_spacing ~= nil then return attempt end
        local missing = type(attempt.missing) == "table" and attempt.missing or {}
        local named = false
        for _, fact in ipairs(missing) do
            if fact == "grid_spacing" then named = true break end
        end
        if not named then missing[#missing + 1] = "grid_spacing" end
        table.sort(missing, function(a, b) return tostring(a) < tostring(b) end)
        attempt.missing = missing
        return attempt
    end

    local function copied_attempt(attempt)
        return mark_missing_spacing(copy_json(attempt))
    end

    --Ask the service first. It answers for this sheet and keeps answering after the job is terminal, which the
    --transient queue slot below does not.
    local ok_service, generation = pcall(Registry.need, "generation")
    local attempt = ok_service and service_attempt(generation, player_index, sheet_id) or nil
    if attempt ~= nil then return copied_attempt(attempt) end

    local job = type(player_data) == "table" and player_data.blueprint_job or nil
    if type(job) == "table" and (job.sheet_id == nil or job.sheet_id == sheet_id) then
        return copied_attempt(job)
    end
    --A build without the per-sheet lookup may still carry the service's plain-data bridge for this sheet.
    local bridged = type(player_data) == "table" and type(player_data.blueprint_attempts) == "table"
        and player_data.blueprint_attempts[sheet_id] or nil
    if type(bridged) == "table" then return copied_attempt(bridged) end
    if type(capture) == "table" then
        --A capture is prepared-input provenance, not the generation attempt. It cannot manufacture spacing that
        --the attempt lookup did not carry.
        local carried = copy_json(provenance or capture)
        if type(carried) == "table" then
            carried.grid_spacing = nil
            return mark_missing_spacing(carried)
        end
    end
    --Absence is a fact the export names, never a fabricated last attempt and never another sheet's attempt.
    return {status = "absent", missing = {"generation_attempt"}}
end

local function source_export_name(value)
    if type(value) == "string" and value ~= "" then return value end
    if type(value) == "table" then
        if type(value.name) == "string" and value.name ~= "" then return value.name end
        if type(value.format) == "string" and value.format ~= "" then return value.format end
    end
    --A producer from the generation lane may still hold the in-memory payload here. The exported name is stable,
    --while copying that payload would nest the export inside itself.
    return ExportPayload.FORMAT
end

local function capture_projection(capture, source_kind, provenance)
    if type(capture) ~= "table" then return nil end
    local prepared = type(capture.prepared_input) == "table" and capture.prepared_input
        or type(capture.prepared) == "table" and capture.prepared or capture
    if type(prepared) ~= "table" then return nil end

    local kind = capture.source_kind or source_kind or prepared.source_kind
    local proof = capture.provenance or provenance or prepared.provenance
    local source_export = capture.source_export or prepared.source_export
    local name = source_export_name(source_export)
    --Generation.capture has already made PreparedInput plain data under the shared job budget. Carry a valid
    --capture directly, so opening the dialog does not synchronously copy a large plan a second time. Only the
    --legacy in-memory export shape needs a projection to remove a nested payload from source_export.
    local projected = prepared
    if type(prepared.source_export) ~= "string" or prepared.source_export ~= name then
        projected = {}
        for key, value in pairs(prepared) do
            if key ~= "source_export" then projected[key] = value end
        end
        projected.source_export = name
    end
    return projected, kind, proof, name
end

local function completeness_diagnostics(snapshot, result, result_setting, catalog, generation, derived)
    local missing = {}
    local function add(fact, reason)
        missing[#missing + 1] = {fact = fact, reason = reason}
    end
    if type(result) ~= "table" then
        add("calculation.result", "the runtime has no calculation result for this sheet")
        add("calculation.solved_rates", "no solved result exists")
        add("calculation.external_rates", "no solved result exists")
        add("calculation.machine_counts", "no calculated columns exist")
        add("calculation.effects", "no calculated columns exist")
        add("calculation.energy", "the runtime has no aggregate energy for an absent result")
        add("calculation.pollution", "the runtime has no aggregate pollution for an absent result")
    else
        if result.solved_rates == nil then add("calculation.solved_rates", "the calculation result did not supply solved rates") end
        if result.external_rates == nil and result.unsolved_rates == nil then
            add("calculation.external_rates", "the calculation result did not supply external rates")
        end
        local has_machine_count, has_effects = false, false
        local columns = result.columns or {}
        for index, column in ipairs(columns) do
            if type(column) == "table" then
                if column.machine_count ~= nil or column.calculated_machine_count ~= nil
                    or derived and derived.columns[index] and derived.columns[index].machine_count ~= nil then has_machine_count = true
                else add("calculation.columns[" .. index .. "].machine_count", "the runtime result did not supply a calculated machine count") end
                if column.effects ~= nil or derived and derived.columns[index] and derived.columns[index].effects ~= nil then has_effects = true
                else add("calculation.columns[" .. index .. "].effects", "the runtime result did not supply calculated effects") end
            end
        end
        if #columns == 0 then
            add("calculation.machine_counts", "the calculation result has no columns")
            add("calculation.effects", "the calculation result has no columns")
        elseif not has_machine_count then
            add("calculation.machine_counts", "the runtime result did not supply calculated machine counts")
        elseif not has_effects then
            add("calculation.effects", "the runtime result did not supply calculated effects")
        end
        if result.energy == nil and result.energy_consumption == nil and not (derived and derived.energy_known) then
            add("calculation.energy", "the calculation result did not supply aggregate energy")
        end
        if result.pollution == nil and result.pollution_per_min == nil and not (derived and derived.pollution_known) then
            add("calculation.pollution", "the calculation result did not supply aggregate pollution")
        end
    end
    if type(catalog) == "table" and type(catalog.recipe_coverage) == "table"
        and catalog.recipe_coverage.state ~= "complete" then
        add("prototypes.recipe", "recipe prototype coverage is " .. tostring(catalog.recipe_coverage.state))
    end
    if type(result_setting) ~= "table" or result_setting.sheet_id == nil then
        add("settings.result.sheet_id", "the calculation record has no sheet identity")
    end
    if type(result_setting) ~= "table" or type(result_setting.revisions) ~= "table"
        or result_setting.revisions.sheet == nil or result_setting.revisions.config == nil then
        add("settings.result.revisions", "the calculation record has no complete sheet/config revision identity")
    end
    if type(generation) == "table" and generation.status == "absent" then
        add("generation.attempt", "the current base has no durable generation attempt lookup")
    elseif type(generation) == "table" and generation.grid_spacing == nil then
        add("generation.grid_spacing", "the generation attempt did not supply a spacing record")
    end
    table.sort(missing, function(a, b) return a.fact < b.fact end)
    return missing
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
    local selection = selection_for_export(snapshot, player_data)
    local derived = derived_calculation(result, snapshot, player_data, catalog)
    local result_setting = result_settings(result, wrapper, result_fp)
    local sheet = copy_json(snapshot)
    sheet.state = state
    sheet.selection = copy_json(selection, nil, "selection")

    local capture, capture_source_kind, capture_provenance = generation_capture(player_index, player_data, snapshot.sheet_id)
    local prepared, source_kind, provenance, source_export = capture_projection(capture, capture_source_kind, capture_provenance)
    local capture_geometry_errors = {}
    if prepared ~= nil then prepared, capture_geometry_errors = capture_geometry_copy(prepared) end
    local generation = generation_attempt(player_index, player_data, snapshot.sheet_id, capture, provenance)

    local diagnostics = {
        missing_prototypes = {}, rejected_values = rejected_values(snapshot), catalog = sorted_diagnostics(catalog_diagnostics),
    }
    for _, diagnostic in ipairs(catalog_diagnostics or {}) do
        if diagnostic.code == "CATALOG_MISSING_PROTOTYPE" or diagnostic.code == "CATALOG_MISSING_QUALITY" then
            diagnostics.missing_prototypes[#diagnostics.missing_prototypes + 1] = copy_json(diagnostic)
        elseif diagnostic.code == "BP_CAP_INCOMPLETE" then
            capture_geometry_errors[#capture_geometry_errors + 1] = {
                field = tostring(diagnostic.subject) .. "." .. tostring(diagnostic.field),
                reason = diagnostic.detail,
            }
        end
    end
    diagnostics.missing_facts = completeness_diagnostics(snapshot, result, result_setting, catalog, generation, derived)
    if #capture_geometry_errors > 0 then
        diagnostics.incomplete_capture = {
            code = "BP_CAP_INCOMPLETE", fields = copy_json(capture_geometry_errors, nil, "diagnostics"),
        }
        for _, missing in ipairs(capture_geometry_errors) do
            diagnostics.missing_facts[#diagnostics.missing_facts + 1] = {
                fact = missing.field, reason = "incomplete capture: " .. tostring(missing.reason),
            }
        end
        table.sort(diagnostics.missing_facts, function(a, b) return a.fact < b.fact end)
    end

    local environment = environment_of(player_index, references)
    local payload = {
        format = ExportPayload.FORMAT,
        schema_version = ExportPayload.SCHEMA_VERSION,
        encoding = ExportPayload.ENCODING,
        rrc_version = environment.mod_version,
        environment = environment,
        sheet = sheet,
        selection = copy_json(selection, nil, "selection"),
        settings = {current = current_settings(snapshot, selection), result = result_setting},
        state = state,
        calculation_tick = (result and (result.calculation_tick or result.tick))
            or (wrapper and (wrapper.calculation_tick or wrapper.tick)) or nil,
        calculation = calculation_copy(result, snapshot, derived),
        prototypes = copy_json(catalog),
        diagnostics = diagnostics,
        generation = generation,
    }
    if #capture_geometry_errors > 0 then
        payload.capture = {status = "incomplete", reason_codes = {"BP_CAP_INCOMPLETE"},
            fields = copy_json(capture_geometry_errors, nil, "diagnostics")}
    end
    if prepared ~= nil then
        --Generation.capture has already performed the bounded preparation copy. This projection only crosses the
        --plain-data export boundary; it never starts preparation or waits for Search while a dialog opens.
        payload.prepared_input = prepared
        if source_kind ~= nil then payload.source_kind = copy_json(source_kind) end
        if provenance ~= nil then payload.provenance = copy_json(provenance) end
        payload.source_export = source_export
    end
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
