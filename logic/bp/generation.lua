--One service for every blueprint request, whether it came from the player's dialog or the engine companion.
--
--The first job slice captures the sheet and its calculation.  Search then owns the remaining slices, while this
--module owns publication, delivery and the terminal result.  The saved state contains only plain data; the live
--handle table is process-local and is rebuilt from the saved lifecycle records after a fresh interface load.
local Generation = {}

local Jobs = require "logic.jobs"
local Registry = require "logic.registry"
local Catalog = require "logic.catalog"
local ExportPayload = require "logic.export_payload"
local Search = require "logic.bp.search"
local Serialize = require "logic.bp.serialize"
local BlueprintDelivery = require "gui.blueprint_delivery"
local Settings = require "logic.bp.settings"

Generation.SCHEMA_VERSION = 1

local PERSISTENCE_KEY = "blueprint_generations"
local registered = false
local next_job_id = 0
local handles = {}

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then return value end
    return fallback
end

local function copy_plain(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then return finite(value, nil) end
    if value_type ~= "table" or getmetatable(value) ~= nil then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local copied = copy_plain(child, seen)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local function integer(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return math.max(0, math.floor(value))
    end
    return fallback
end

local function prepared_input_identity(prepared, fallback_sheet_id, fallback_revisions)
    prepared = type(prepared) == "table" and prepared or {}
    local snapshot = type(prepared.snapshot) == "table" and prepared.snapshot or {}
    local fingerprint = type(snapshot.fingerprint) == "table" and snapshot.fingerprint or {}
    local revisions = type(prepared.revisions) == "table" and prepared.revisions or fallback_revisions or {}
    local sheet_id = prepared.sheet_id or snapshot.sheet_id or fallback_sheet_id
    if sheet_id == nil and revisions.sheet == nil and revisions.config == nil and fingerprint.input == nil then return nil end
    return {
        sheet_id = sheet_id,
        sheet_revision = finite(revisions.sheet, nil),
        config_revision = finite(revisions.config, nil),
        input_fingerprint = fingerprint.input,
    }
end

--This table is deliberately separate from the queued job.  Jobs owns resumable work; Generation owns the public
--identity, capture and terminal result that must remain addressable after the queued job has been published.
--The false form is read-only so rebuilding process-local callbacks during a save load never writes storage.
local function persistence(create)
    local saved = rawget(_G, "storage")
    if type(saved) ~= "table" then return nil end
    local state = saved[PERSISTENCE_KEY]
    if type(state) ~= "table" or getmetatable(state) ~= nil then
        if not create then return nil end
        state = {next_job_id = 0, jobs = {}}
        saved[PERSISTENCE_KEY] = state
    end
    if type(state.jobs) ~= "table" or getmetatable(state.jobs) ~= nil then
        if not create then return nil end
        state.jobs = {}
    end
    if type(state.lookup) ~= "table" or getmetatable(state.lookup) ~= nil then
        if create then state.lookup = {} end
    end
    if create then state.next_job_id = integer(state.next_job_id, 0) end
    return state
end

local function saved_record(job_id)
    local state = persistence(false)
    return state and state.jobs and state.jobs[job_id]
end

local function persist_handle(handle)
    if type(handle) ~= "table" or type(handle.job_id) ~= "number" then return end
    local state = persistence(true)
    if not state then return end
    local record = {
        schema_version = Generation.SCHEMA_VERSION,
        job_id = handle.job_id, state = handle.state, phase = handle.phase,
        progress = copy_plain(handle.progress) or {done_units = 0, total_units = nil},
        player_index = handle.player_index, sheet_id = handle.sheet_id,
        revisions = copy_plain(handle.revisions) or {}, deliver = handle.deliver == true,
        settings = copy_plain(handle.settings) or {},
        prepared_input_identity = copy_plain(handle.prepared_input_identity),
        grid_spacing = copy_plain(handle.grid_spacing),
        interim = copy_plain(handle.interim), delivered_sequence = handle.delivered_sequence,
    }
    if handle.reason_codes then record.reason_codes = copy_plain(handle.reason_codes) or {} end
    if handle.reason_details then record.reason_details = copy_plain(handle.reason_details) or {} end
    if handle.result then record.result = copy_plain(handle.result) or {} end
    if handle.blueprint_string ~= nil then record.blueprint_string = handle.blueprint_string end
    if handle.canonical_sha256 ~= nil then record.canonical_sha256 = handle.canonical_sha256 end
    if handle.canonical_version ~= nil then record.canonical_version = handle.canonical_version end
    if handle.canonical then record.canonical = copy_plain(handle.canonical) or {} end
    if handle.capture then record.capture = copy_plain(handle.capture) or {} end
    if handle.delivery_reason ~= nil then record.delivery_reason = handle.delivery_reason end
    state.jobs[handle.job_id] = copy_plain(record) or {}
    state.next_job_id = math.max(integer(state.next_job_id, 0), integer(handle.job_id, 0))
end

local function forget_persisted(job_id)
    local state = persistence(false)
    if state and state.jobs then state.jobs[job_id] = nil end
end

local function handle_from_record(record)
    if type(record) ~= "table" or getmetatable(record) ~= nil then return nil end
    local job_id = integer(record.job_id, nil)
    if not job_id or record.player_index == nil or record.sheet_id == nil then return nil end
    local state = record.state
    if state ~= "success" and state ~= "failure" and state ~= "cancelled" and state ~= "pending" then
        state = "pending"
    end
    local handle = {
        job_id = job_id, state = state,
        phase = type(record.phase) == "string" and record.phase or "queued",
        progress = copy_plain(record.progress) or {done_units = 0, total_units = nil},
        player_index = record.player_index, sheet_id = record.sheet_id,
        revisions = copy_plain(record.revisions) or {}, deliver = record.deliver == true,
        settings = copy_plain(record.settings) or {},
        prepared_input_identity = copy_plain(record.prepared_input_identity),
        grid_spacing = copy_plain(record.grid_spacing),
    }
    if record.reason_codes then handle.reason_codes = copy_plain(record.reason_codes) or {} end
    if record.reason_details then handle.reason_details = copy_plain(record.reason_details) or {} end
    if record.result then handle.result = copy_plain(record.result) or {} end
    if record.blueprint_string ~= nil then handle.blueprint_string = record.blueprint_string end
    if record.canonical_sha256 ~= nil then handle.canonical_sha256 = record.canonical_sha256 end
    if record.canonical_version ~= nil then handle.canonical_version = record.canonical_version end
    if record.canonical then handle.canonical = copy_plain(record.canonical) or {} end
    if record.capture then handle.capture = copy_plain(record.capture) or {} end
    if record.delivery_reason ~= nil then handle.delivery_reason = record.delivery_reason end
    if record.interim then handle.interim = copy_plain(record.interim) end
    handle.delivered_sequence = integer(record.delivered_sequence, nil)
    return handle
end

local function bridge_record(handle)
    if type(handle) ~= "table" then return nil end
    local result = {
        generation_id = handle.job_id, job_id = handle.job_id, player_index = handle.player_index,
        sheet_id = handle.sheet_id, state = handle.state, phase = handle.phase,
        revisions = copy_plain(handle.revisions) or {}, settings = copy_plain(handle.settings) or {},
        prepared_input_identity = copy_plain(handle.prepared_input_identity),
        grid_spacing = copy_plain(handle.grid_spacing),
    }
    if handle.reason_codes then result.reason_codes = copy_plain(handle.reason_codes) or {} end
    if handle.reason_details then result.reason_details = copy_plain(handle.reason_details) or {} end
    return result
end

--The exporter is deliberately frozen in this lane. Keep a small, plain-data identity on player storage for its
--existing generation-id walk, while the complete per-sheet index below remains owned by this service.
local function bridge_attempt(handle, remember)
    if type(storage) ~= "table" or type(handle) ~= "table" then return end
    local data = storage[handle.player_index]
    if type(data) ~= "table" then return end
    if type(data.blueprint_attempts) ~= "table" then data.blueprint_attempts = {} end
    data.blueprint_attempts[handle.sheet_id] = bridge_record(handle)
    if remember then
        data.blueprint_attempt = {
            generation_id = handle.job_id, job_id = handle.job_id, sheet_id = handle.sheet_id,
            state = data.blueprint_attempt,
        }
    end
    data.last_blueprint_attempt = bridge_record(handle)
end

local function index_handle(handle)
    if type(handle) ~= "table" or handle.player_index == nil or handle.sheet_id == nil then return end
    local state = persistence(true)
    if not state then return end
    state.lookup[handle.player_index] = state.lookup[handle.player_index] or {}
    local previous = integer(state.lookup[handle.player_index][handle.sheet_id], nil)
    if previous == nil or handle.job_id >= previous then
        state.lookup[handle.player_index][handle.sheet_id] = handle.job_id
    end
end

local function attempt_state(state)
    return state == "pending" or state == "success" or state == "failure" or state == "cancelled"
end

local function latest_handle(player_index, sheet_id)
    local latest, latest_id
    local state = persistence(false)
    local indexed = state and type(state.lookup) == "table" and state.lookup[player_index]
    local indexed_id = indexed and integer(indexed[sheet_id], nil)
    if indexed_id ~= nil then
        local indexed_handle = handles[indexed_id] or handle_from_record(saved_record(indexed_id))
        if indexed_handle and indexed_handle.player_index == player_index and indexed_handle.sheet_id == sheet_id
            and attempt_state(indexed_handle.state) then
            latest, latest_id = indexed_handle, indexed_id
        end
    end

    local function consider(job_id, candidate)
        job_id = integer(job_id, nil)
        if not candidate or job_id == nil or candidate.player_index ~= player_index or candidate.sheet_id ~= sheet_id
            or not attempt_state(candidate.state) then return end
        if latest_id == nil or job_id > latest_id then latest, latest_id = candidate, job_id end
    end
    for job_id, handle in pairs(handles) do consider(job_id, handle) end
    for job_id, record in pairs(state and state.jobs or {}) do
        if type(job_id) == "number" then consider(job_id, handles[job_id] or handle_from_record(record)) end
    end
    return latest
end

local function number(value, fallback)
    return finite(value, fallback)
end

local function current_revisions(player_index, sheet_id)
    local data = type(storage) == "table" and storage[player_index] or nil
    local revisions = data and data.sheet_revision or {}
    return {
        sheet = number(revisions and revisions[sheet_id], 0),
        config = number(data and data.config_revision, 0),
    }
end

local function player_of(player_index)
    if not rawget(_G, "game") then return nil end
    local player = game.get_player and game.get_player(player_index) or game.players and game.players[player_index]
    return player and player.valid ~= false and player or nil
end

local function name_of(value)
    if type(value) == "string" then return value end
    if type(value) == "table" then return value.name or value.id or value.prototype end
    if type(value) == "userdata" then
        local ok, name = pcall(function() return value.name end)
        return ok and name or nil
    end
end

local function member_of(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function sheet_for(player_index, sheet_id)
    local data = type(storage) == "table" and storage[player_index] or nil
    local pane = data and data.sheet_section and data.sheet_section.sheet_pane
    for _, tab in ipairs(pane and pane.tabs or {}) do
        local sheet = tab and tab.content
        local tags = sheet and sheet.tags
        if sheet and sheet.valid ~= false and tags and tags.hxrrc_sheet_id == sheet_id then return sheet end
    end
end

local function add_name(set, value, quality_set)
    if type(value) == "table" and value.name == nil and value.id == nil and value.prototype == nil then
        for _, child in ipairs(value) do add_name(set, child, quality_set) end
        return
    end
    local name = name_of(value)
    if name then set[name] = true end
    if quality_set and type(value) == "table" and value.quality then
        local quality = name_of(value.quality)
        if quality then quality_set[quality] = true end
    end
end

local function add_full_name(references, full_name, parts)
    if type(full_name) ~= "string" then return end
    local kind, name = full_name:match("^(item)/(.+)$")
    if not kind then kind, name = full_name:match("^(fluid)/(.+)$") end
    if kind == "item" then
        references.items[name] = true
        if parts and parts.quality then references.qualities[name_of(parts.quality) or parts.quality] = true end
        return
    elseif kind == "fluid" then
        references.fluids[name] = true
        return
    end
    local item_length, rest = full_name:match("^item%-quality:(%d+):(.+)$")
    item_length = tonumber(item_length)
    if item_length and rest then
        local item = rest:sub(1, item_length)
        local quality_length, quality = rest:sub(item_length + 1):match("^(%d+):(.+)$")
        quality_length = tonumber(quality)
        if quality_length and quality then
            references.items[item] = true
            references.qualities[quality:sub(1, quality_length)] = true
        end
    end
end

local function append_map_names(set, map, references)
    for full_name, _ in pairs(map or {}) do add_full_name(references, full_name) end
end

local function add_recipe_name(set, value)
    if type(value) == "table" and value.name == nil and value.id == nil and value.prototype == nil then
        for key, child in pairs(value) do
            if child == true then
                add_recipe_name(set, key)
            elseif child ~= nil then
                add_recipe_name(set, child)
            end
        end
        return
    end
    local name = name_of(value)
    if type(name) ~= "string" then return end
    --Solver columns for burners and quality loops are identities, not prototype recipes.
    if name:sub(1, 11) == "hxrrc-burn:" or name:sub(1, 13) == "quality-loop:" then return end
    set[name] = true
end

local function add_stage_recipe_name(set, stage)
    if type(stage) ~= "table" then return end
    add_recipe_name(set, stage.recipe_name or stage.recipe)
end

local function add_quality_loop_recipes(set, loop)
    if type(loop) ~= "table" then return end
    add_recipe_name(set, loop.craft_recipe_name)
    add_recipe_name(set, loop.recycle_recipe_name)
    add_stage_recipe_name(set, loop.recycle)
    add_stage_recipe_name(set, loop.assist)
    add_stage_recipe_name(set, loop.config)
    for _, stage in pairs(loop.crafts or {}) do add_stage_recipe_name(set, stage) end
    if type(loop.config) == "table" then
        for _, stage in pairs(loop.config.crafts or {}) do add_stage_recipe_name(set, stage) end
    end
end

local function references_for(snapshot, calculation, settings)
    local references = {entities = {}, items = {}, fluids = {}, modules = {}, qualities = {}, recipes = {}}
    for _, target in ipairs(snapshot and snapshot.targets or {}) do
        add_full_name(references, target.full_name, target.parts)
        add_recipe_name(references.recipes, target.recipe_name or target.recipe)
    end
    for _, entry in ipairs(snapshot and snapshot.selection or {}) do
        add_recipe_name(references.recipes, entry.recipe_name or entry.recipe)
        add_name(references.entities, entry.machine, references.qualities)
        add_name(references.modules, entry.modules, references.qualities)
        for _, beacon in ipairs(entry.beacons or {}) do
            add_name(references.entities, beacon, references.qualities)
            add_name(references.modules, beacon.modules, references.qualities)
        end
    end
    for _, key in ipairs({"roboport", "pole", "belt", "inserter", "long_inserter", "pipe", "underground_pipe"}) do
        local choice = settings and settings[key]
        add_name(references.entities, choice, references.qualities)
        if key == "belt" and type(choice) == "table" then
            add_name(references.entities, choice.underground, references.qualities)
            add_name(references.entities, choice.splitter, references.qualities)
        elseif key == "pipe" and type(settings and settings.underground_pipe) == "table" then
            add_name(references.entities, settings.underground_pipe, references.qualities)
        end
    end
    for _, column in ipairs(calculation and calculation.columns or {}) do
        add_recipe_name(references.recipes, column.recipe_name or column.recipe)
        add_quality_loop_recipes(references.recipes, column.quality_loop)
        add_name(references.entities, column.machine, references.qualities)
        add_name(references.entities, column.burner, references.qualities)
        append_map_names(references.items, column.net_amounts, references)
        local loop = column.quality_loop
        if type(loop) == "table" then
            add_name(references.items, loop.item, references.qualities)
            add_name(references.entities, loop.config and loop.config.machine, references.qualities)
            for _, stage in ipairs({loop.recycle, loop.assist}) do
                if type(stage) == "table" then
                    add_name(references.entities, stage.machine, references.qualities)
                    add_name(references.modules, stage.setup and stage.setup.modules, references.qualities)
                end
            end
            for _, stage in pairs(loop.crafts or {}) do
                if type(stage) == "table" then
                    add_name(references.entities, stage.machine, references.qualities)
                    add_name(references.modules, stage.setup and stage.setup.modules, references.qualities)
                end
            end
        end
    end
    for full_name, _ in pairs(calculation and calculation.solved_rates or {}) do add_full_name(references, full_name) end
    for full_name, _ in pairs(calculation and calculation.unsolved_rates or {}) do add_full_name(references, full_name) end
    for full_name, parts in pairs(calculation and calculation.product_parts or {}) do add_full_name(references, full_name, parts) end
    return references
end

local function sorted_set(set)
    local result = {}
    for value, _ in pairs(set or {}) do result[#result + 1] = value end
    table.sort(result)
    return result
end

local function catalog_options(references, settings)
    local infrastructure = {
        belt = settings and settings.belt,
        pipe = {
            base = settings and settings.pipe and settings.pipe.name,
            underground = settings and settings.underground_pipe and settings.underground_pipe.name,
            quality = settings and settings.pipe and settings.pipe.quality,
        },
        inserter = settings and settings.inserter,
        long_inserter = settings and settings.long_inserter,
        pole = settings and settings.pole,
        robo = settings and settings.roboport,
    }
    return {
        infrastructure = infrastructure,
        entities = sorted_set(references.entities),
        items = sorted_set(references.items),
        fluids = sorted_set(references.fluids),
        modules = sorted_set(references.modules),
        qualities = sorted_set(references.qualities),
        recipes = sorted_set(references.recipes),
    }
end

local function map_value(map, key)
    if type(map) ~= "table" then return nil end
    return map[key] or map[tostring(key)]
end

local function fingerprint_of(snapshot_module, value)
    if type(value) == "string" then return value end
    if type(value) ~= "table" then return nil end
    local fingerprint = value.fingerprint
    if type(fingerprint) == "string" then return fingerprint end
    if type(fingerprint) == "table" then return fingerprint.input or fingerprint.result end
    if type(value.input_fingerprint) == "string" then return value.input_fingerprint end
    if value.targets ~= nil and value.options ~= nil and value.selection ~= nil then
        local ok, result = pcall(snapshot_module.fingerprint, value)
        if ok then return result end
    end
end

local function mark_snapshot_result(snapshot_module, snapshot, result, wrapper)
    local candidates = {
        result and (result.input_fingerprint or result.settings_fingerprint or result.fingerprint),
        result and (result.settings or result.snapshot or result.inputs or result.input),
        wrapper and (wrapper.input_fingerprint or wrapper.settings or wrapper.snapshot or wrapper.inputs),
    }
    local result_fingerprint
    for index = 1, 3 do
        local candidate = candidates[index]
        result_fingerprint = fingerprint_of(snapshot_module, candidate)
        if result_fingerprint then break end
    end
    snapshot.fingerprint.result = result_fingerprint
    if not result_fingerprint then
        snapshot.state = "not_computed"
    elseif result_fingerprint == snapshot.fingerprint.input then
        snapshot.state = "current"
    else
        snapshot.state = "stale"
    end
end

local function copy_keys(value)
    local keys = {}
    for key, _ in pairs(value or {}) do
        if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys
end

--Large plain-data projections cross the job boundary one child at a time. The cursor itself is plain data, so a
--save can resume this walk without putting a function, LuaObject or metatable in storage.
local function copy_cursor(value)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" or value_type == "number" then
        return {done = true, value = value_type == "number" and finite(value, nil) or value}
    end
    if value_type ~= "table" or getmetatable(value) ~= nil then return {done = true, value = nil} end
    local target = {}
    --Frames keep a path into value rather than a target-table alias. Jobs copies the cursor at every tick and
    --deliberately does not preserve aliases, so an alias here would make the resumed copy write into a detached
    --table after the first save boundary.
    return {done = false, value = target, stack = {{source = value, path = {}, keys = copy_keys(value), index = 1}}}
end

local function consume(budget)
    if budget.ops > 0 then budget.ops = budget.ops - 1 end
end

local function target_at(root, path)
    local target = root
    for _, key in ipairs(path or {}) do
        if type(target[key]) ~= "table" or getmetatable(target[key]) ~= nil then target[key] = {} end
        target = target[key]
    end
    return target
end

local function append_path(path, key)
    local result = {}
    for index, value in ipairs(path or {}) do result[index] = value end
    result[#result + 1] = key
    return result
end

local function copy_cursor_step(cursor, budget)
    if cursor.done then return true end
    while budget.ops > 0 and #cursor.stack > 0 do
        local frame = cursor.stack[#cursor.stack]
        local target = target_at(cursor.value, frame.path or {})
        local key = frame.keys[frame.index]
        if key == nil then
            table.remove(cursor.stack)
        else
            frame.index = frame.index + 1
            local child = frame.source[key]
            local child_type = type(child)
            if child == nil or child_type == "boolean" or child_type == "string" or child_type == "number" then
                target[key] = child_type == "number" and finite(child, nil) or child
            elseif child_type == "table" and getmetatable(child) == nil then
                local nested = {}
                target[key] = nested
                cursor.stack[#cursor.stack + 1] = {
                    source = child, path = append_path(frame.path, key), keys = copy_keys(child), index = 1,
                }
            end
            consume(budget)
        end
    end
    if #cursor.stack == 0 then cursor.done = true end
    return cursor.done
end

local function merge_plain(target, source)
    for key, value in pairs(source or {}) do
        if type(value) == "table" and getmetatable(value) == nil then
            if type(target[key]) ~= "table" then target[key] = {} end
            merge_plain(target[key], value)
        else
            target[key] = value
        end
    end
end

local function empty_catalog()
    return {schema_version = Catalog.SCHEMA_VERSION, entity = {}, item = {}, fluid = {}, quality = {}, quality_level = {},
        module = {}, beacon = {}, recipe = {}, recipe_coverage = {state = "complete", active = {}, missing = {}}}
end

local function calculation_for(player_index, sheet_id, revisions, snapshot)
    local calculation = Registry.need("calculation")
    local get = calculation and calculation.get
    if type(get) ~= "function" then return nil, "not_computed" end
    local ok, record = pcall(get, player_index, sheet_id)
    if not ok or type(record) ~= "table" or type(record.result) ~= "table" then return nil, "not_computed" end
    if record.player_index ~= nil and record.player_index ~= player_index then return nil, "stale" end
    if record.sheet_id ~= nil and record.sheet_id ~= sheet_id then return nil, "stale" end
    if record.sheet_revision ~= revisions.sheet or record.config_revision ~= revisions.config then return nil, "stale" end
    if record.input_fingerprint ~= snapshot.fingerprint.input then return nil, "stale" end
    return record.result, record
end

local function source_name(sheet_id)
    return "blueprint-export/" .. tostring(sheet_id)
end

local function preparation_context(input, job)
    local sheet = sheet_for(input.player_index, input.sheet_id)
    if not sheet then return nil, "deleted" end
    local revisions = copy_plain(job.revisions) or current_revisions(input.player_index, input.sheet_id)
    local raw_snapshot, raw_calculation, wrapper, supplied_catalog, supplied_export, recalculate_snapshot
    if type(input.prepared_input) == "table" then
        local supplied = input.prepared_input
        raw_snapshot, raw_calculation, wrapper = supplied.snapshot or {}, supplied.solver_result, nil
        supplied_catalog, supplied_export = supplied.catalog, supplied.source_export
        revisions = copy_plain(supplied.revisions) or revisions
        recalculate_snapshot = false
    else
        local snapshot_module = Registry.need("snapshot")
        raw_snapshot = snapshot_module.of_sheet(sheet)
        raw_calculation, wrapper = calculation_for(input.player_index, input.sheet_id, revisions, raw_snapshot)
        if not raw_calculation then return nil, wrapper end
        recalculate_snapshot = true
    end
    local sheet_reader = Registry.need("sheet")
    local read = sheet_reader.read_inputs(sheet)
    local raw_settings = input.settings or Settings.of_sheet(input.player_index, input.sheet_id)
    local raw_options = input.options or read.options or {}
    raw_options.input_edge = raw_options.input_edge or raw_settings.input_edge
    raw_options.output_edge = raw_options.output_edge or raw_settings.output_edge
    local references = references_for(raw_snapshot, raw_calculation, raw_settings)
    local options = catalog_options(references, raw_settings)
    --Catalog.build remains the authoritative projection. Its result crosses the preparation boundary through the
    --same cursor as the snapshot and export, so a large prototype projection cannot consume one unbounded step.
    local catalog_parts = supplied_catalog and {} or {options}
    local fields = {
        snapshot = raw_snapshot, solver_result = raw_calculation, settings = raw_settings, options = raw_options,
        revisions = revisions,
    }
    local copy_order = {"snapshot", "solver_result", "settings", "options", "revisions"}
    return {
        input = input, sheet_id = input.sheet_id, wrapper = wrapper,
        raw_calculation = raw_calculation, fields = {}, raw_fields = fields, copy_order = copy_order, copy_index = 1,
        catalog_parts = catalog_parts, catalog_index = 1, catalog = empty_catalog(), catalog_diagnostics = {},
        catalog_prebuilt = supplied_catalog ~= nil, catalog_cursor = copy_cursor(supplied_catalog or {}),
        source_export = supplied_export or {name = source_name(input.sheet_id)},
        source_export_cursor = copy_cursor(supplied_export or {name = source_name(input.sheet_id)}),
        recalculate_snapshot = recalculate_snapshot, catalog_part = nil,
        catalog_part_diagnostics = nil,
    }
end

local function finish_preparation(prep, input, job)
    local snapshot = prep.fields.snapshot or {}
    if prep.recalculate_snapshot then
        mark_snapshot_result(Registry.need("snapshot"), snapshot, prep.raw_calculation, prep.wrapper)
    end
    prep.fields.options.catalog_diagnostics = copy_plain(prep.catalog_diagnostics) or {}
    local raw_export = prep.source_export or {}
    local exported = {name = source_name(input.sheet_id), format = raw_export.format, schema_version = raw_export.schema_version}
    return {
        schema_version = Generation.SCHEMA_VERSION,
        snapshot = snapshot,
        solver_result = prep.fields.solver_result or {status = "not_computed", columns = {}},
        catalog = prep.catalog,
        settings = prep.fields.settings or {}, options = prep.fields.options or {}, revisions = prep.fields.revisions or copy_plain(job.revisions) or {},
        surface = input.surface or name_of(member_of(player_of(input.player_index), "surface")),
        force = input.force or name_of(member_of(player_of(input.player_index), "force")), source_export = exported,
    }
end

local function preparation_step(prep, input, job, budget)
    while budget.ops > 0 do
        if prep.copy_index <= #prep.copy_order then
            local name = prep.copy_order[prep.copy_index]
            if not prep.copy_cursor then prep.copy_cursor = copy_cursor(prep.raw_fields[name]) end
            if copy_cursor_step(prep.copy_cursor, budget) then
                prep.fields[name] = prep.copy_cursor.value
                prep.copy_cursor, prep.copy_index = nil, prep.copy_index + 1
            end
        elseif prep.catalog_prebuilt then
            if prep.catalog_cursor.done then
                prep.catalog = prep.catalog_cursor.value or empty_catalog()
                prep.catalog_prebuilt = false
            else
                copy_cursor_step(prep.catalog_cursor, budget)
            end
        elseif prep.catalog_index <= #prep.catalog_parts then
            if not prep.catalog_part then
                local part, diagnostics = Catalog.build(input.player_index, prep.catalog_parts[prep.catalog_index])
                prep.catalog_part, prep.catalog_part_diagnostics = part, diagnostics
                prep.catalog_cursor = copy_cursor(prep.catalog_part)
            end
            if copy_cursor_step(prep.catalog_cursor, budget) then
                local part = prep.catalog_cursor.value
                merge_plain(prep.catalog, part)
                for _, diagnostic in ipairs(prep.catalog_part_diagnostics or {}) do
                    prep.catalog_diagnostics[#prep.catalog_diagnostics + 1] = diagnostic
                end
                prep.catalog_part, prep.catalog_cursor, prep.catalog_part_diagnostics = nil, nil, nil
                prep.catalog_index = prep.catalog_index + 1
            end
        elseif not prep.source_export then
            local sheet = sheet_for(input.player_index, input.sheet_id)
            prep.source_export = ExportPayload.build(input.player_index, sheet)
            prep.source_export_cursor = copy_cursor(prep.source_export)
        elseif not prep.source_export_cursor.done then
            copy_cursor_step(prep.source_export_cursor, budget)
        else
            return finish_preparation(prep, input, job)
        end
        if budget.ops <= 0 then return nil end
    end
end

local function prepared_input(input, job, state, budget)
    if not state.prepare then
        local prep, reason = preparation_context(input, job)
        if not prep then return nil, reason end
        state.prepare = prep
    end
    return preparation_step(state.prepare, input, job, budget)
end

local function failure_code(errors)
    if type(errors) ~= "table" then return nil end
    if errors.code then return errors.code end
    for _, error_record in ipairs(errors) do
        if type(error_record) == "table" and error_record.code then return error_record.code end
    end
end

local function codes(errors)
    local result, seen = {}, {}
    local function add(value)
        if type(value) == "string" and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        elseif type(value) == "table" then
            if value.code then add(value.code) else for _, child in ipairs(value) do add(child) end end
        end
    end
    add(errors)
    table.sort(result)
    return result
end

local function stage_for(errors, job)
    --The stage a failure records wins: a raised error names where it was raised, which a code prefix cannot.
    local recorded = type(job) == "table" and type(job.progress) == "table" and job.progress.phase
    if type(recorded) == "string" and recorded ~= "" and recorded ~= "failed" then return recorded end
    local code = failure_code(errors) or ""
    if code:match("^BP_REJ_") then return "preflight" end
    if code:match("^BP_V_") then return "validate" end
    return "search"
end

local function set_failure(job, state, code, stage)
    job.done, job.ok = true, false
    job.result = nil
    job.errors = {{code = code}}
    job.phase = "failed"
    job.progress = {phase = stage or "search", done_units = 1, total_units = 1}
    state.phase = "failed"
end

local function result_progress(progress)
    progress = type(progress) == "table" and progress or {}
    return {done_units = number(progress.done_units, 0), total_units = progress.total_units}
end

local function capture_source_kind(input, prepared)
    local requested = input.source_kind or prepared.source_kind
    if requested == "runtime" or requested == "harness" or requested == "handwritten_fixture" then return requested end
    return type(input.prepared_input) == "table" and "harness" or "runtime"
end

local function initial_provenance(input, job)
    local supplied = type(input.provenance) == "table" and input.provenance or Registry.generation_provenance
    supplied = type(supplied) == "table" and supplied or {}
    local provenance = {
        candidate_sha = supplied.candidate_sha or "dev", mod_version = supplied.mod_version or "dev",
        factorio_branch = supplied.factorio_branch or "unknown", packaged = supplied.packaged == true,
        sheet_revision = job.revisions and job.revisions.sheet or 0, config_revision = job.revisions and job.revisions.config or 0,
        outcome = "pending",
    }
    return copy_plain(provenance) or {}
end

local function update_capture(handle, state, outcome, errors, stage)
    if not handle then return end
    if type(handle.capture) ~= "table" then
        persist_handle(handle)
        return
    end
    handle.capture.provenance = handle.capture.provenance or {}
    handle.capture.provenance.outcome = outcome
    if errors then handle.capture.provenance.reason_codes = copy_plain(codes(errors)) or {} end
    if stage then handle.capture.provenance.stage = stage end
    state = state or {}
    handle.capture.provenance.revisions = copy_plain(state.revisions or handle.revisions) or {}
    persist_handle(handle)
end

local function search_grid_spacing(job)
    local search = type(job) == "table" and type(job.state) == "table" and job.state.search or nil
    if type(search) ~= "table" then return nil end
    local spacing = search.grid_spacing or (type(search.work) == "table" and search.work.grid_spacing)
    return copy_plain(spacing)
end

--Every code the player sees carries whatever the stage said about it: a raised Lua error's message, the blocked
--cell and its owner, the prototype that failed to resolve. A code with no detail explains nothing.
local function reason_details(errors)
    local details, seen = {}, {}
    local function add(record)
        if type(record) ~= "table" then return end
        if record.code ~= nil or record.detail ~= nil then
            local detail = record.detail
            if type(detail) ~= "string" then detail = detail ~= nil and tostring(detail) or nil end
            local candidate_size = record.candidate_size or {}
            local grid_size = record.grid_size or {}
            local key = table.concat({tostring(record.code), tostring(detail), tostring(record.flow_id),
                tostring(record.block_id), tostring(record.available_ports), tostring(record.requested_ports),
                tostring(candidate_size.area), tostring(candidate_size.width), tostring(candidate_size.height),
                tostring(grid_size.w), tostring(grid_size.h)}, "\0")
            if not seen[key] and (record.code ~= nil or detail ~= nil) then
                seen[key] = true
                local copied = {}
                for key_name, value in pairs(record) do
                    if key_name ~= "reason_details" then copied[key_name] = copy_plain(value) end
                end
                copied.code = record.code ~= nil and tostring(record.code) or nil
                copied.detail = detail
                copied.flow_id = record.flow_id ~= nil and tostring(record.flow_id) or nil
                details[#details + 1] = copied
            end
        end
        for _, child in ipairs(record) do add(child) end
        --A stage may carry its own breakdown under a named field rather than as array children.  Search puts the
        --validator rejection counts there, and without this they never reach the failure caption or the export.
        if type(record.reason_details) == "table" then
            for _, child in ipairs(record.reason_details) do add(child) end
        end
    end
    add(errors)
    return details
end

local function terminal_failure(handle, job)
    if not handle or handle.state ~= "pending" then return end
    local code_list = codes(job.errors)
    handle.state = "failure"
    handle.phase = stage_for(job.errors, job)
    handle.progress = result_progress(job.progress)
    handle.reason_codes = code_list
    handle.reason_details = reason_details(job.errors)
    handle.grid_spacing = search_grid_spacing(job) or handle.grid_spacing
    update_capture(handle, job.state and job.state.prepare and job.state.prepare.fields, "failure", job.errors, handle.phase)
    persist_handle(handle)
    bridge_attempt(handle, false)
    local report = Registry.generation_failure
    if type(report) == "function" then
        pcall(report, handle.player_index, {
            job_id = handle.job_id, state = "failure", phase = handle.phase, stage = handle.phase,
            progress = result_progress(handle.progress), reason_codes = copy_plain(code_list) or {},
            reason_details = copy_plain(handle.reason_details) or {},
        })
    end
end

local function terminal_cancel(handle, phase)
    if not handle or handle.state ~= "pending" then return end
    handle.state = "cancelled"
    handle.phase = phase or "cancelled"
    handle.progress = result_progress(handle.progress)
    update_capture(handle, nil, "cancelled", nil, handle.phase)
    persist_handle(handle)
    bridge_attempt(handle, false)
end

local function pending_handle_from_job(job)
    local state = job and job.state
    local input = state and state.input
    local job_id = input and integer(input.generation_job_id, nil)
    if job_id == nil then return nil end
    local handle = handle_from_record(saved_record(job_id))
    if not handle then
        handle = {
            job_id = job_id, state = "pending", phase = job.phase or "queued",
            progress = copy_plain(job.progress) or {done_units = 0, total_units = nil},
            player_index = job.player_index, sheet_id = job.sheet_id,
            revisions = copy_plain(job.revisions) or {}, deliver = input.deliver == true,
            settings = copy_plain(input.settings or state and state.prepared and state.prepared.settings) or {},
            prepared_input_identity = prepared_input_identity(state and state.prepared, job.sheet_id, job.revisions),
        }
    end
    if not handle.grid_spacing then handle.grid_spacing = search_grid_spacing(job) end

    --A save can be taken just after preparation completed and before this module writes the public copy. The job
    --itself already contains the plain PreparedInput, so recover the capture locally without changing storage.
    if not handle.capture and state and type(state.prepared) == "table" then
        handle.capture = copy_plain(state.prepared) or {}
        if type(handle.settings) ~= "table" or next(handle.settings) == nil then
            handle.settings = copy_plain(state.prepared.settings) or {}
        end
        handle.prepared_input_identity = prepared_input_identity(state.prepared, handle.sheet_id, handle.revisions)
        handle.capture.source_kind = capture_source_kind(input, state.prepared)
        handle.capture.provenance = initial_provenance(input, job)
    end
    handles[job_id] = handle
    next_job_id = math.max(next_job_id, job_id)
    return handle
end

local function rebind_handles()
    local state = persistence(false)
    for job_id, record in pairs(state and state.jobs or {}) do
        if type(job_id) == "number" then
            local handle = handle_from_record(record)
            if handle then
                handles[handle.job_id] = handle
                index_handle(handle)
                next_job_id = math.max(next_job_id, handle.job_id)
            end
        end
    end

    --The queued job is the authoritative owner while it is running. A record may be absent in a save produced by
    --an older build, but a generation id in the queued input is enough to rebuild the process-local owner before
    --the scheduler can execute the next slice.
    local saved = rawget(_G, "storage")
    if type(saved) ~= "table" then return end
    for player_index, data in pairs(saved) do
        if type(player_index) == "number" and type(data) == "table" and type(data.blueprint_job) == "table" then
            local input = data.blueprint_job.state and data.blueprint_job.state.input
            local job_id = input and integer(input.generation_job_id, nil)
            if job_id ~= nil and not handles[job_id] then pending_handle_from_job(data.blueprint_job) end
            if job_id ~= nil and handles[job_id] then index_handle(handles[job_id]) end
            if job_id ~= nil then next_job_id = math.max(next_job_id, job_id) end
        end
    end
end

local function handle_for(job)
    local state = job and job.state
    local input = state and state.input
    local id = input and input.generation_job_id
    return id and (handles[id] or pending_handle_from_job(job)) or nil
end

local function encode_blueprint(result)
    if type(result) ~= "table" or not rawget(_G, "helpers") then return nil end
    local ok_json, json = pcall(helpers.table_to_json, result)
    if not ok_json then return nil end
    local ok_encoded, encoded = pcall(helpers.encode_string, json)
    if not ok_encoded or type(encoded) ~= "string" or encoded == "" then return nil end
    return encoded
end

local function bit32_or_arithmetic()
    local bit = rawget(_G, "bit32")
    if bit then return bit.band, bit.bor, bit.bxor, bit.rshift, bit.rrotate end

    local function binary(a, b, operation)
        a, b = a % 4294967296, b % 4294967296
        local result, place = 0, 1
        for _ = 1, 32 do
            local abit, bbit = a % 2, b % 2
            if operation(abit, bbit) ~= 0 then result = result + place end
            a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
        end
        return result
    end
    local function band(a, b, ...)
        local function both(x, y) return x == 1 and y == 1 and 1 or 0 end
        local result = binary(a, b, both)
        for _, value in ipairs({...}) do result = binary(result, value, both) end
        return result
    end
    local function bor(a, b, ...)
        local function either(x, y) return x == 1 or y == 1 and 1 or 0 end
        local result = binary(a, b, either)
        for _, value in ipairs({...}) do result = binary(result, value, either) end
        return result
    end
    local function bxor(a, b, ...)
        local function different(x, y) return x ~= y and 1 or 0 end
        local result = binary(a, b, different)
        for _, value in ipairs({...}) do result = binary(result, value, different) end
        return result
    end
    local function rshift(value, count) return math.floor((value % 4294967296) / 2 ^ count) end
    local function rrotate(value, count)
        count = count % 32
        if count == 0 then return value % 4294967296 end
        return (rshift(value, count) + (value % 2 ^ count) * 2 ^ (32 - count)) % 4294967296
    end
    return band, bor, bxor, rshift, rrotate
end

local function sha256(text)
    local band, bor, bxor, rshift, rrotate = bit32_or_arithmetic()
    local k = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2a748f, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee,
        0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    }
    local h = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}
    local bit_length = #text * 8
    text = text .. string.char(128)
    while (#text + 8) % 64 ~= 0 do text = text .. string.char(0) end
    local high = math.floor(bit_length / 4294967296)
    local low = bit_length % 4294967296
    text = text .. string.char(
        band(rshift(high, 24), 255), band(rshift(high, 16), 255), band(rshift(high, 8), 255), band(high, 255),
        band(rshift(low, 24), 255), band(rshift(low, 16), 255), band(rshift(low, 8), 255), band(low, 255))
    local function word(offset)
        return band(text:byte(offset) * 16777216 + text:byte(offset + 1) * 65536
            + text:byte(offset + 2) * 256 + text:byte(offset + 3), 0xffffffff)
    end
    local function add(a, b, c, d, e)
        return band((a or 0) + (b or 0) + (c or 0) + (d or 0) + (e or 0), 0xffffffff)
    end
    for offset = 1, #text, 64 do
        local w = {}
        for index = 0, 15 do w[index] = word(offset + index * 4) end
        for index = 16, 63 do
            local x, y = w[index - 15], w[index - 2]
            local s0 = bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3))
            local s1 = bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10))
            w[index] = add(w[index - 16], s0, w[index - 7], s1)
        end
        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for index = 0, 63 do
            local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
            local choose = bxor(band(e, f), band(bxor(e, 0xffffffff), g))
            local temp1 = add(hh, s1, choose, k[index + 1], w[index])
            local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
            local majority = bxor(band(a, b), band(a, c), band(b, c))
            local temp2 = add(s0, majority)
            hh, g, f, e, d, c, b, a = g, f, e, add(d, temp1), d, c, b, add(temp1, temp2)
        end
        h[1], h[2], h[3], h[4] = add(h[1], a), add(h[2], b), add(h[3], c), add(h[4], d)
        h[5], h[6], h[7], h[8] = add(h[5], e), add(h[6], f), add(h[7], g), add(h[8], hh)
    end
    local result = {}
    for _, value in ipairs(h) do result[#result + 1] = string.format("%08x", value) end
    return table.concat(result)
end

local function canonical_digest(canonical)
    if not rawget(_G, "helpers") or type(canonical) ~= "table" then return nil end
    local ok, json = pcall(helpers.table_to_json, canonical)
    if not ok or type(json) ~= "string" then return nil end
    return sha256(json)
end

local function begin(context)
    return {
        phase = "queued",
        input = copy_plain(context) or {},
        prepared = nil,
        search = nil,
        progress = {phase = "queued", done_units = 0, total_units = nil},
    }
end

local function search_options(input, context)
    local result = copy_plain(input.options) or {}
    local settings = copy_plain(input.settings) or {}
    context = type(context) == "table" and context or {}
    --Preflight receives the selected settings through its documented options.settings field. Keep the selected
    --infrastructure out of the flat option namespace: catalog.pipe is the projection for both pipe choices, so
    --flattening underground_pipe would make preflight look for a non-existent catalog. Search receives settings
    --separately for edges and infrastructure geometry.
    result.settings = result.settings or settings
    --A caller that spells search_budget at the top level gets the documented option rather than silence. A
    --written number that the search never sees is worse than a refused one: the run looks budgeted and is not.
    for _, control in ipairs({"search_budget"}) do
        if result[control] == nil then
            local supplied = input[control]
            if supplied == nil then supplied = context[control] end
            if supplied == nil then supplied = type(context.options) == "table" and context.options[control] or nil end
            if supplied ~= nil then result[control] = copy_plain(supplied) end
        end
    end
    if input.surface ~= nil and result.surface == nil then result.surface = input.surface end
    if input.force ~= nil and result.force == nil then result.force = input.force end
    return result
end

local function search_input_for(input, job, context)
    local options = search_options(input, context)
    local result = {
        snapshot = input.snapshot,
        solver_result = input.solver_result,
        catalog = input.catalog,
        settings = input.settings,
        options = options,
        surface = input.surface,
        force = input.force,
        revisions = input.revisions or job.revisions,
        player_index = job.player_index,
        sheet_id = job.sheet_id,
        generation_job_id = input.generation_job_id or job.state and job.state.input and job.state.input.generation_job_id,
    }
    --Search has a deliberately flat input for bounded grids and limits. Keep GenerationInput's options field as
    --the public shape, while forwarding those data-only controls to the search boundary.
    for key, value in pairs(options) do
        if result[key] == nil and key ~= "settings" then result[key] = copy_plain(value) end
    end
    return result
end

local function step(job, budget)
    local state = type(job.state) == "table" and job.state or begin{}
    job.state = state
    budget = type(budget) == "table" and budget or {ops = 0}
    budget.ops = math.max(0, math.floor(number(budget.ops, 0)))
    if job.done or budget.ops <= 0 then return job end

    local owner = handle_for(job)
    if not owner or owner.state ~= "pending" then
        job.done, job.ok, job.phase = true, false, "cancelled"
        job.errors = {{code = "BP_FAIL_CANCELLED"}}
        state.phase = "cancelled"
        return job
    end

    if state.phase == "queued" or state.phase == "prepare" then
        state.phase = "prepare"
        local ok, prepared_or_reason, preparation_reason = pcall(prepared_input, state.input, job, state, budget)
        if not ok then
            --A raised error is never a budget: the code says so and the detail carries the raised message, which
            --names the file and the line (contracts §11).
            set_failure(job, state, "BP_FAIL_INTERNAL_ERROR", "prepare")
            job.errors[1].detail = tostring(prepared_or_reason)
            terminal_failure(handle_for(job), job)
            budget.ops = math.max(0, budget.ops - 1)
            return job
        end
        if prepared_or_reason == nil and preparation_reason ~= nil then
            if preparation_reason == "deleted" then
                job.done, job.ok, job.phase = true, false, "cancelled"
                job.errors = {{code = "BP_FAIL_CANCELLED"}}
                state.phase = "cancelled"
                terminal_cancel(handle_for(job), "cancelled")
            else
                set_failure(job, state, "BP_REJ_SNAPSHOT_STALE", "preflight")
                job.errors[1].detail = preparation_reason
                terminal_failure(handle_for(job), job)
            end
            budget.ops = math.max(0, budget.ops - 1)
            return job
        end
        if prepared_or_reason ~= nil then
            state.prepared = prepared_or_reason
            local handle = handle_for(job)
            if handle and not handle.capture then
                handle.capture = copy_plain(prepared_or_reason) or {}
                if type(handle.settings) ~= "table" or next(handle.settings) == nil then
                    handle.settings = copy_plain(prepared_or_reason.settings) or {}
                end
                handle.prepared_input_identity = prepared_input_identity(prepared_or_reason, handle.sheet_id, handle.revisions)
                handle.capture.source_kind = capture_source_kind(state.input, prepared_or_reason)
                handle.capture.provenance = initial_provenance(state.input, job)
                persist_handle(handle)
                bridge_attempt(handle, false)
            end
            local input = prepared_or_reason
            local search_input = search_input_for(input, job, state.input)
            state.search = Search.begin(search_input)
            state.search.player_index, state.search.sheet_id = job.player_index, job.sheet_id
            state.search.generation_job_id = input.generation_job_id or job.state.input.generation_job_id
            state.search.revisions = copy_plain(job.revisions) or {}
            state.phase = "search"
            job.phase = state.search.phase
            job.progress = result_progress(state.search.progress)
        end
    end

    if state.phase == "search" and budget.ops > 0 then
        Search.step(state.search, budget)
        job.phase = state.search.phase
        job.progress = copy_plain(state.search.progress) or job.progress
        local active_handle = handle_for(job)
        local interim = state.search.interim
        if active_handle and type(interim) == "table" and type(interim.result) == "table"
            and type(interim.sequence) == "number"
            and (not active_handle.interim or interim.sequence > active_handle.interim.sequence) then
            local candidate = copy_plain(interim.result)
            local encoded = encode_blueprint(candidate)
            if candidate and encoded then
                local first = active_handle.interim == nil
                active_handle.interim = {sequence = interim.sequence, entities = integer(interim.entities, #candidate.entities),
                    result = candidate, blueprint_string = encoded}
                active_handle.phase = first and "improving" or active_handle.phase
                if first then job.phase = "improving" end
                if first and active_handle.deliver then
                    local ok = BlueprintDelivery.deliver(active_handle.player_index, candidate)
                    if ok then active_handle.delivered_sequence = interim.sequence end
                end
                persist_handle(active_handle)
                bridge_attempt(active_handle, false)
            end
        end
        local spacing = search_grid_spacing(job)
        if active_handle and spacing and not active_handle.grid_spacing then
            active_handle.grid_spacing = spacing
            persist_handle(active_handle)
            bridge_attempt(active_handle, false)
        end
        if state.search.done then
            local handle = handle_for(job)
            if handle then
                handle.grid_spacing = search_grid_spacing(job) or handle.grid_spacing
                persist_handle(handle)
                bridge_attempt(handle, false)
            end
            job.done, job.ok = true, state.search.ok == true
            job.result = copy_plain(state.search.result)
            job.errors = copy_plain(state.search.errors)
            state.phase = state.search.ok and "done" or "failed"
            if not job.ok and failure_code(job.errors) == "BP_FAIL_REVISION_CHANGED" then
                terminal_failure(handle_for(job), job)
            end
        end
    end
    return job
end

local function publish(job)
    local handle = handle_for(job)
    if not handle or handle.state ~= "pending" then return end
    handle.progress = result_progress(job.progress)
    if job.ok ~= true or type(job.result) ~= "table" then
        if failure_code(job.errors) == "BP_FAIL_CANCELLED" then terminal_cancel(handle, "cancelled")
        else terminal_failure(handle, job) end
        return
    end

    local blueprint = copy_plain(job.result)
    local encoded = encode_blueprint(blueprint)
    local canonical, version = Serialize.canonical(blueprint)
    handle.state = "success"
    handle.phase = "done"
    handle.progress = {done_units = 1, total_units = 1}
    handle.result = blueprint
    handle.grid_spacing = search_grid_spacing(job) or handle.grid_spacing
    handle.blueprint_string = encoded
    handle.canonical_version = version
    handle.canonical = canonical
    handle.canonical_sha256 = canonical_digest(canonical)
    update_capture(handle, nil, "success", nil, "done")
    bridge_attempt(handle, false)

    local final_sequence = type(job.state) == "table" and type(job.state.search) == "table"
        and job.state.search.interim and job.state.search.interim.sequence
    local final_entities = type(blueprint.entities) == "table" and #blueprint.entities or 0
    local had_interim = handle.interim ~= nil
    local equal_delivered = handle.delivered_sequence ~= nil and handle.interim
        and handle.interim.sequence == final_sequence and handle.interim.entities == final_entities
    if equal_delivered then
        --The cursor already received this exact best result while the search was running.
    else
        handle.interim = {sequence = final_sequence or (had_interim and (handle.interim.sequence + 1) or 1), entities = final_entities,
            result = blueprint, blueprint_string = encoded}
    end
    if handle.deliver and not equal_delivered and not had_interim then
        local ok, reason = BlueprintDelivery.deliver(handle.player_index, blueprint)
        if not ok and reason ~= "blueprint_cursor_busy" then
            handle.delivery_reason = reason
        end
    end
    persist_handle(handle)
    bridge_attempt(handle, false)
end

function Generation.deliver_interim(player_index, job_id, sequence)
    local handle = handles[job_id] or handle_from_record(saved_record(job_id))
    if handle then handles[job_id] = handle end
    local interim = handle and handle.interim
    if not handle or handle.player_index ~= player_index or not interim or interim.sequence ~= sequence then
        return false, "stale_offer"
    end
    local ok, reason = BlueprintDelivery.deliver(player_index, interim.result)
    if ok then
        handle.delivered_sequence = interim.sequence
        persist_handle(handle)
    end
    return ok, reason
end

function Generation.register()
    rebind_handles()
    if registered then return true end
    Jobs.register("blueprint", {begin = begin, step = step, publish = publish})
    registered = true
    return true
end

function Generation.start(input)
    input = copy_plain(input) or {}
    if input.schema_version ~= nil and input.schema_version ~= Generation.SCHEMA_VERSION then
        return nil, "BP_FAIL_ENTITY_BUDGET"
    end
    local player_index, sheet_id = input.player_index or 1, input.sheet_id
    if sheet_id == nil then return nil, "BP_FAIL_REVISION_CHANGED" end
    input.schema_version = Generation.SCHEMA_VERSION
    input.player_index, input.sheet_id = player_index, sheet_id
    input.revisions = input.revisions or current_revisions(player_index, sheet_id)
    input.deliver = input.deliver == true
    input.kind = "blueprint"

    for id, handle in pairs(handles) do
        if handle.player_index == player_index and handle.sheet_id == sheet_id and handle.state == "pending" then
            terminal_cancel(handle, "superseded")
        end
    end

    local saved = persistence(true)
    local highest = integer(saved and saved.next_job_id, 0)
    for id, _ in pairs(handles) do highest = math.max(highest, integer(id, 0)) end
    next_job_id = math.max(next_job_id, highest) + 1
    local id = next_job_id
    input.generation_job_id = id
    handles[id] = {
        job_id = id, state = "pending", phase = "queued", progress = {done_units = 0, total_units = nil},
        player_index = player_index, sheet_id = sheet_id, revisions = copy_plain(input.revisions), deliver = input.deliver,
        settings = copy_plain(input.settings or input.prepared_input and input.prepared_input.settings) or {},
        prepared_input_identity = prepared_input_identity(input.prepared_input, sheet_id, input.revisions),
    }
    persist_handle(handles[id])
    index_handle(handles[id])
    bridge_attempt(handles[id], true)
    Generation.register()
    local job = Jobs.request_sheet(player_index, sheet_id, input)
    if not job then
        handles[id] = nil
        forget_persisted(id)
        return nil, "BP_FAIL_REVISION_CHANGED"
    end
    return id, nil
end

local function public_status(handle)
    local result = {
        job_id = handle.job_id, state = handle.state, phase = handle.phase,
        progress = result_progress(handle.progress),
        grid_spacing = copy_plain(handle.grid_spacing),
    }
    if handle.state == "success" then
        result.blueprint_string = handle.blueprint_string
        result.canonical_sha256 = handle.canonical_sha256
        result.canonical_version = handle.canonical_version
    elseif handle.state == "failure" then
        result.reason_codes, result.stage = copy_plain(handle.reason_codes) or {}, handle.phase
        result.reason_details = copy_plain(handle.reason_details) or {}
    end
    result.interim = handle.interim and {sequence = handle.interim.sequence, entities = handle.interim.entities,
        blueprint_string = handle.interim.blueprint_string} or nil
    return result
end

local function public_attempt(handle, player_index, sheet_id)
    if not handle then
        return {
            schema_version = Generation.SCHEMA_VERSION, present = false, found = false,
            player_index = player_index, sheet_id = sheet_id, state = "absent", terminal_state = "absent",
            status = "absent", outcome = "absent", terminal_outcome = "absent", phase = "absent",
            revisions = {}, settings = {}, reason_codes = {}, reason_details = {},
            diagnostics = {state = "absent"},
        }
    end
    local capture = type(handle.capture) == "table" and handle.capture or nil
    local settings = handle.settings
    if type(settings) ~= "table" or next(settings) == nil then settings = capture and capture.settings or {} end
    local identity = handle.prepared_input_identity
        or prepared_input_identity(capture, handle.sheet_id, handle.revisions)
    local reasons = copy_plain(handle.reason_codes) or {}
    local details = copy_plain(handle.reason_details) or {}
    local diagnostics = {
        state = handle.state, phase = handle.phase, progress = copy_plain(handle.progress) or {},
        reason_codes = copy_plain(reasons) or {}, reason_details = copy_plain(details) or {},
    }
    if capture and capture.provenance then diagnostics.provenance = copy_plain(capture.provenance) or {} end
    local result = {
        schema_version = Generation.SCHEMA_VERSION, present = true, found = true,
        job_id = handle.job_id, generation_id = handle.job_id, player_index = handle.player_index,
        sheet_id = handle.sheet_id, state = handle.state, status = handle.state, outcome = handle.state,
        terminal_outcome = handle.state ~= "pending" and handle.state or nil,
        terminal_state = handle.state ~= "pending" and handle.state or nil, phase = handle.phase,
        progress = result_progress(handle.progress), revisions = copy_plain(handle.revisions) or {},
        sheet_revision = handle.revisions and handle.revisions.sheet,
        config_revision = handle.revisions and handle.revisions.config,
        settings = copy_plain(settings) or {}, actual_settings = copy_plain(settings) or {},
        prepared_input_identity = copy_plain(identity), reason_codes = reasons, reason_details = details,
        grid_spacing = copy_plain(handle.grid_spacing),
        diagnostics = diagnostics, search_diagnostics = copy_plain(diagnostics) or {},
    }
    result.interim = handle.interim and {sequence = handle.interim.sequence, entities = handle.interim.entities,
        blueprint_string = handle.interim.blueprint_string} or nil
    result.input_fingerprint = identity and identity.input_fingerprint or nil
    if capture then
        result.prepared_input = copy_plain(capture) or {}
        result.capture = copy_plain(capture) or {}
    end
    if handle.result then result.result = copy_plain(handle.result) or {} end
    return result
end

--Returns a plain record even when the player has never generated this sheet. The scan is intentionally per sheet:
--a newer attempt on another sheet is not a valid fallback.
function Generation.lookup(player_index, sheet_id)
    return public_attempt(latest_handle(player_index, sheet_id), player_index, sheet_id)
end

Generation.attempt = Generation.lookup
Generation.attempt_for_sheet = Generation.lookup
Generation.lookup_attempt = Generation.lookup

function Generation.status(player_index, job_id)
    local handle = handles[job_id] or handle_from_record(saved_record(job_id))
    if handle then handles[job_id] = handle end
    if not handle or handle.player_index ~= player_index then return nil end
    if handle.state == "pending" and type(storage) == "table" then
        local data = storage[player_index]
        local job = data and data.blueprint_job
        local input = job and job.state and job.state.input
        if job and input and input.generation_job_id == job_id then
            handle.phase = job.phase or handle.phase
            handle.progress = copy_plain(job.progress) or handle.progress
        elseif not sheet_for(player_index, handle.sheet_id) then
            terminal_cancel(handle, "cancelled")
        elseif not job then
            local revisions = current_revisions(player_index, handle.sheet_id)
            if revisions.sheet ~= (handle.revisions and handle.revisions.sheet)
                or revisions.config ~= (handle.revisions and handle.revisions.config) then
                handle.state = "failure"
                handle.phase = "search"
                handle.reason_codes = {"BP_FAIL_REVISION_CHANGED"}
                update_capture(handle, nil, "failure", handle.reason_codes, handle.phase)
                persist_handle(handle)
                bridge_attempt(handle, false)
            else
                terminal_cancel(handle, "cancelled")
            end
        else
            local revisions = current_revisions(player_index, handle.sheet_id)
            if revisions.sheet ~= (handle.revisions and handle.revisions.sheet)
                or revisions.config ~= (handle.revisions and handle.revisions.config) then
                handle.state = "failure"
                handle.phase = "search"
                handle.reason_codes = {"BP_FAIL_REVISION_CHANGED"}
                update_capture(handle, nil, "failure", handle.reason_codes, handle.phase)
                persist_handle(handle)
                bridge_attempt(handle, false)
            end
        end
    end
    return public_status(handle)
end

function Generation.capture(player_index, generation_id)
    local handle = handles[generation_id] or handle_from_record(saved_record(generation_id))
    if handle then handles[generation_id] = handle end
    if not handle or handle.player_index ~= player_index or type(handle.capture) ~= "table" then return nil end
    local capture = copy_plain(handle.capture)
    if capture then
        capture.provenance = copy_plain(handle.capture.provenance) or {}
        local current = current_revisions(player_index, handle.sheet_id)
        local revisions = capture.revisions or capture.provenance.revisions or {}
        local current_state = current.sheet == number(revisions.sheet, current.sheet)
            and current.config == number(revisions.config, current.config)
        local snapshot = capture.snapshot
        local fingerprint = snapshot and snapshot.fingerprint and snapshot.fingerprint.input
        if current_state and type(fingerprint) == "string" then
            local sheet = sheet_for(player_index, handle.sheet_id)
            local snapshot_module = Registry.snapshot
            if sheet and snapshot_module and type(snapshot_module.of_sheet) == "function" then
                local ok, live = pcall(snapshot_module.of_sheet, sheet)
                local live_fingerprint = live and live.fingerprint and live.fingerprint.input
                current_state = ok and live_fingerprint == fingerprint
            end
        end
        if not current_state and type(capture.snapshot) == "table" then
            capture.snapshot.state = "stale"
        end
    end
    return capture
end

function Generation.cancel(player_index, job_id)
    local handle = handles[job_id] or handle_from_record(saved_record(job_id))
    if handle then handles[job_id] = handle end
    if not handle or handle.player_index ~= player_index or handle.state ~= "pending" then return false end
    Jobs.cancel(player_index, handle.sheet_id)
    terminal_cancel(handle, "cancelled")
    return true
end

Registry.generation = Generation
Generation.register()

return Generation
