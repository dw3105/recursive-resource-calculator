--One service for every blueprint request, whether it came from the player's dialog or the engine companion.
--
--The first job slice captures the sheet and its calculation.  Search then owns the remaining slices, while this
--module owns publication, delivery and the terminal result.  The saved state contains only plain data; the live
--handle table is deliberately process-local and is rebuilt by callers after a fresh interface load.
local Generation = {}

local Jobs = require "logic.jobs"
local Registry = require "logic.registry"
local Catalog = require "logic.catalog"
local ExportPayload = require "logic.export_payload"
local Search = require "logic.bp.search"
local Serialize = require "logic.bp.serialize"
local BlueprintDelivery = require "gui.blueprint_delivery"
local Settings = require "logic.bp.settings"
local Solver = require "logic.solver"

Generation.SCHEMA_VERSION = 1

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
    local kind, name = full_name:match("^(item|fluid)/(.+)$")
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

local function references_for(snapshot, calculation, settings)
    local references = {entities = {}, items = {}, fluids = {}, modules = {}, qualities = {}}
    for _, target in ipairs(snapshot and snapshot.targets or {}) do
        add_full_name(references, target.full_name, target.parts)
    end
    for _, entry in ipairs(snapshot and snapshot.selection or {}) do
        add_name(references.entities, entry.machine, references.qualities)
        add_name(references.modules, entry.modules, references.qualities)
        for _, beacon in ipairs(entry.beacons or {}) do
            add_name(references.entities, beacon, references.qualities)
            add_name(references.modules, beacon.modules, references.qualities)
        end
    end
    for _, key in ipairs({"roboport", "pole", "belt", "inserter", "pipe", "underground_pipe"}) do
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
    }
end

local RESULT_MAP_KEYS = {
    "calculation_results", "last_calculations", "results_by_sheet", "sheet_results", "last_results",
    "calculation_by_sheet_id", "last_calculation_by_sheet_id", "calculation_results_by_sheet_id",
}
local RESULT_KEYS = {"last_calculation", "last_calculation_result", "last_result", "calculation_result", "calculation"}

local function map_value(map, sheet_id)
    if type(map) ~= "table" then return nil end
    return map[sheet_id] or map[tostring(sheet_id)]
end

local function result_wrapper(candidate, sheet_id)
    if type(candidate) ~= "table" then return nil, nil end
    if candidate.sheet_id ~= nil and candidate.sheet_id ~= sheet_id then return nil, nil end
    if type(candidate.result) == "table" then return candidate.result, candidate end
    if type(candidate.calculation) == "table" then return candidate.calculation, candidate end
    return candidate, candidate
end

local function stored_calculation(player_index, sheet_id)
    local data = type(storage) == "table" and storage[player_index] or nil
    if type(data) ~= "table" then return nil, nil end
    for _, key in ipairs(RESULT_MAP_KEYS) do
        local result, wrapper = result_wrapper(map_value(data[key], sheet_id), sheet_id)
        if result then return result, wrapper end
    end
    for _, key in ipairs(RESULT_KEYS) do
        local result, wrapper = result_wrapper(data[key], sheet_id)
        if result then return result, wrapper end
    end
    local job = map_value(data.calc_jobs, sheet_id)
    if type(job) == "table" and type(job.result) == "table" and job.done then
        return job.result, job
    end
end

local function current_report(sheet)
    local output = sheet and sheet.output_flow
    for _, child in ipairs(output and output.children or {}) do
        if child.name == "report" and child.valid ~= false then
            local tags = child.tags or {}
            return tags.hxrrc_report_stale ~= true and tags.stale ~= true
        end
    end
    return false
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
        wrapper and (wrapper.settings or wrapper.snapshot or wrapper.inputs),
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

local function prepare_from_sheet(input, job)
    local sheet = sheet_for(input.player_index, input.sheet_id)
    if not sheet then return nil, "deleted" end

    local snapshot_module = Registry.need("snapshot")
    local raw_snapshot = snapshot_module.of_sheet(sheet)
    local raw_calculation, wrapper = stored_calculation(input.player_index, input.sheet_id)
    local sheet_reader = Registry.need("sheet")
    local read = sheet_reader.read_inputs(sheet)

    --The sliced calculation path leaves the finished result in its report staging state and then removes the
    --job.  When that path has published a current report, recapture its real inputs with the same solver kernel
    --inside this job.  A sheet without a current report remains an honest preflight rejection below; this fallback
    --does not turn an uncalculated sheet into a supported request.
    if raw_calculation == nil and current_report(sheet) then
        raw_calculation = Solver.solve_for(read.rates, input.player_index, read.product_parts, read.options)
        wrapper = {sheet_id = input.sheet_id, result = raw_calculation}
    end
    local snapshot = copy_plain(raw_snapshot) or {}
    local calculation = copy_plain(raw_calculation) or {status = "not_computed", columns = {}}
    mark_snapshot_result(snapshot_module, snapshot, raw_calculation, wrapper)
    if raw_calculation ~= nil and snapshot.state == "not_computed" and current_report(sheet) then
        --The fallback above is a fresh calculation of the report's current sheet inputs.  The result is plain data
        --after the copy boundary, so it is safe to carry through the remaining job stages.
        snapshot.fingerprint.result = snapshot.fingerprint.input
        snapshot.state = "current"
    end
    local settings = copy_plain(input.settings) or Settings.of_sheet(input.player_index, input.sheet_id)
    local options = copy_plain(input.options) or copy_plain(read.options) or {}
    options.input_edge = options.input_edge or settings.input_edge
    options.output_edge = options.output_edge or settings.output_edge
    local references = references_for(snapshot, calculation, settings)
    local catalog, diagnostics = Catalog.build(input.player_index, catalog_options(references, settings))
    options.catalog_diagnostics = copy_plain(diagnostics) or {}
    local source_export = ExportPayload.build(input.player_index, sheet)
    return {
        schema_version = Generation.SCHEMA_VERSION,
        snapshot = snapshot,
        solver_result = calculation,
        catalog = catalog,
        settings = settings,
        options = options,
        revisions = copy_plain(job.revisions) or current_revisions(input.player_index, input.sheet_id),
        surface = input.surface or name_of(member_of(player_of(input.player_index), "surface")),
        force = input.force or name_of(member_of(player_of(input.player_index), "force")),
        source_export = source_export,
    }
end

local function prepared_input(input, job)
    if type(input.prepared_input) == "table" then
        local prepared = copy_plain(input.prepared_input) or {}
        prepared.schema_version = prepared.schema_version or Generation.SCHEMA_VERSION
        prepared.revisions = prepared.revisions or copy_plain(job.revisions) or {}
        return prepared
    end
    return prepare_from_sheet(input, job)
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

local function stage_for(errors)
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

local function terminal_failure(handle, job)
    if not handle or handle.state ~= "pending" then return end
    local code_list = codes(job.errors)
    handle.state = "failure"
    handle.phase = stage_for(job.errors)
    handle.progress = result_progress(job.progress)
    handle.reason_codes = code_list
    local report = Registry.generation_failure
    if type(report) == "function" then
        pcall(report, handle.player_index, {
            job_id = handle.job_id, state = "failure", phase = handle.phase, stage = handle.phase,
            progress = result_progress(handle.progress), reason_codes = copy_plain(code_list) or {},
        })
    end
end

local function terminal_cancel(handle, phase)
    if not handle or handle.state ~= "pending" then return end
    handle.state = "cancelled"
    handle.phase = phase or "cancelled"
    handle.progress = result_progress(handle.progress)
end

local function handle_for(job)
    local state = job and job.state
    local input = state and state.input
    local id = input and input.generation_job_id
    return id and handles[id] or nil
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

local function search_options(input)
    local result = copy_plain(input.options) or {}
    local settings = copy_plain(input.settings) or {}
    --Preflight receives the selected settings through its documented options.settings field. Keep the selected
    --infrastructure out of the flat option namespace: catalog.pipe is the projection for both pipe choices, so
    --flattening underground_pipe would make preflight look for a non-existent catalog. Search receives settings
    --separately for edges and infrastructure geometry.
    result.settings = result.settings or settings
    if input.surface ~= nil and result.surface == nil then result.surface = input.surface end
    if input.force ~= nil and result.force == nil then result.force = input.force end
    return result
end

local function search_input_for(input, job)
    local options = search_options(input)
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

    if state.phase == "queued" or state.phase == "prepare" then
        state.phase = "prepare"
        local ok, prepared_or_reason, preparation_reason = pcall(prepared_input, state.input, job)
        if not ok then
            set_failure(job, state, "BP_FAIL_ENTITY_BUDGET", "search")
            job.errors[1].detail = tostring(prepared_or_reason)
            terminal_failure(handle_for(job), job)
            budget.ops = math.max(0, budget.ops - 1)
            return job
        end
        if prepared_or_reason == nil then
            if preparation_reason == "deleted" then
                job.done, job.ok, job.phase = true, false, "cancelled"
                job.errors = {{code = "BP_FAIL_CANCELLED"}}
                state.phase = "cancelled"
                terminal_cancel(handle_for(job), "cancelled")
            else
                set_failure(job, state, "BP_FAIL_ENTITY_BUDGET", "search")
                terminal_failure(handle_for(job), job)
            end
            budget.ops = math.max(0, budget.ops - 1)
            return job
        end
        state.prepared = prepared_or_reason
        local input = prepared_or_reason
        local search_input = search_input_for(input, job)
        state.search = Search.begin(search_input)
        state.search.player_index, state.search.sheet_id = job.player_index, job.sheet_id
        state.search.revisions = copy_plain(job.revisions) or {}
        state.phase = "search"
        job.phase = state.search.phase
        job.progress = result_progress(state.search.progress)
        budget.ops = math.max(0, budget.ops - 1)
    end

    if state.phase == "search" and budget.ops > 0 then
        Search.step(state.search, budget)
        job.phase = state.search.phase
        job.progress = copy_plain(state.search.progress) or job.progress
        if state.search.done then
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
    handle.blueprint_string = encoded
    handle.canonical_version = version
    handle.canonical = canonical
    handle.canonical_sha256 = canonical_digest(canonical)

    if handle.deliver then
        local ok, reason = BlueprintDelivery.deliver(handle.player_index, blueprint)
        if not ok and reason ~= "blueprint_cursor_busy" then
            handle.delivery_reason = reason
        end
    end
end

function Generation.register()
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
        if handle.player_index == player_index and handle.state == "pending" then
            terminal_cancel(handle, "superseded")
        end
    end

    next_job_id = next_job_id + 1
    local id = next_job_id
    input.generation_job_id = id
    handles[id] = {
        job_id = id, state = "pending", phase = "queued", progress = {done_units = 0, total_units = nil},
        player_index = player_index, sheet_id = sheet_id, revisions = copy_plain(input.revisions), deliver = input.deliver,
    }
    Generation.register()
    local job = Jobs.request_sheet(player_index, sheet_id, input)
    if not job then
        handles[id] = nil
        return nil, "BP_FAIL_REVISION_CHANGED"
    end
    return id, nil
end

local function public_status(handle)
    local result = {
        job_id = handle.job_id, state = handle.state, phase = handle.phase,
        progress = result_progress(handle.progress),
    }
    if handle.state == "success" then
        result.blueprint_string = handle.blueprint_string
        result.canonical_sha256 = handle.canonical_sha256
        result.canonical_version = handle.canonical_version
    elseif handle.state == "failure" then
        result.reason_codes, result.stage = copy_plain(handle.reason_codes) or {}, handle.phase
    end
    return result
end

function Generation.status(player_index, job_id)
    local handle = handles[job_id]
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
        else
            local revisions = current_revisions(player_index, handle.sheet_id)
            if revisions.sheet ~= (handle.revisions and handle.revisions.sheet)
                or revisions.config ~= (handle.revisions and handle.revisions.config) then
                handle.state = "failure"
                handle.phase = "search"
                handle.reason_codes = {"BP_FAIL_REVISION_CHANGED"}
            end
        end
    end
    return public_status(handle)
end

function Generation.cancel(player_index, job_id)
    local handle = handles[job_id]
    if not handle or handle.player_index ~= player_index or handle.state ~= "pending" then return false end
    Jobs.cancel(player_index, handle.sheet_id)
    terminal_cancel(handle, "cancelled")
    return true
end

Generation.register()

return Generation
