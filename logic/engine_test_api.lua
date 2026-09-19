--The interface the in-game test companion drives, and the build identity it checks first.
--
--Owned by lane W4-golden. Engine evidence has to exercise this candidate's own generation, rejection and export
--paths; a companion that builds a blueprint out of its own fixture would prove nothing about the mod under test.
--
--remote interface "rrc-engine-test":
--  build_id()                  -> {candidate_sha, mod_version, factorio_branch, packaged}
--  start_generation(context)   -> job_id
--  generation_status(job_id)  -> {state = "pending"|"success"|"failure", progress, phase,
--                                  blueprint_string?, canonical_sha256?, canonical_version?, reason_codes?}
--  cancel_generation(job_id)  -> {state = "cancelled"}
--  preflight(case)             -> reason codes        (a cheap pre-check, never a substitute for a real run)
--  export(sheet_id)            -> debug string
--  canonical(blueprint_string) -> {canonical_sha256, canonical_version}
--
--Generation is a job, not a function call: remote.call returns inside the tick it was made, while the search
--runs across ticks under the same budget and cancellation the player's own button uses. The companion polls, so
--what it measures is the path a player takes.
--
--logic/build_id.lua exists only in a packaged copy, written by generate_release.sh. In a source checkout it is
--absent and this module reports {candidate_sha = "dev", packaged = false}, which the companion refuses to write
--evidence for: a development checkout can never be mistaken for a release candidate.
local EngineTestApi = {}

local INTERFACE_NAME = "rrc-engine-test"
local DEV_ERROR = "rrc-engine-test requires a packaged release candidate"

--Every dependency is loaded while control.lua is being parsed. Factorio refuses require from a remote
--interface handler, even though an offline Lua interpreter permits it. Keep these references out of the
--runtime callbacks below; the module registry is already populated by control.lua before this file loads.
local Generation = require "logic.bp.generation"
local Preflight = require "logic.bp.preflight"
local ExportPayload = require "logic.export_payload"
local Serialize = require "logic.bp.serialize"

--This table is runtime-only. The actual work is held by Jobs/storage; it contains only handles and completed
--plain results so that the interface itself cannot put executable values in a save.
local engine_jobs = {}
local next_job_id = 0
local registered = false

local function copy_plain(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" or value_type == "number" then
        return value
    end
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

local function packaged_or_error()
    if not EngineTestApi.build_id().packaged then error(DEV_ERROR, 2) end
end

--Read while control.lua is parsed: Factorio refuses require later, and a missing file is not an error here.
local ok_build, packaged_build = pcall(require, "logic.build_id")

function EngineTestApi.build_id()
    local ok, build = ok_build, packaged_build
    if ok and type(build) == "table" and build.packaged == true
        and type(build.candidate_sha) == "string" and build.candidate_sha ~= "" then
        return {
            candidate_sha = build.candidate_sha,
            mod_version = build.mod_version or "unknown",
            factorio_branch = build.factorio_branch or "unknown",
            packaged = true,
        }
    end
    return {candidate_sha = "dev", mod_version = "dev", factorio_branch = "dev", packaged = false}
end

local function bit32_or_error()
    local bit = rawget(_G, "bit32")
    if not bit then error("rrc-engine-test needs bit32 for canonical digests", 3) end
    return bit
end

--A small SHA-256 implementation keeps the remote result independent of non-existent Factorio crypto helpers.
local function sha256(text)
    local bit = bit32_or_error()
    local band, bor, bxor = bit.band, bit.bor, bit.bxor
    local rshift, rrotate = bit.rshift, bit.rrotate
    local k = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
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

local function canonical_from_string(blueprint_string)
    if type(blueprint_string) ~= "string" or blueprint_string == "" then error("blueprint_string is required", 3) end
    if blueprint_string:sub(1, 1) == "0" then blueprint_string = blueprint_string:sub(2) end
    local decoded = helpers.decode_string(blueprint_string)
    if type(decoded) ~= "string" then error("blueprint string could not be decoded", 3) end
    local blueprint = helpers.json_to_table(decoded)
    if type(blueprint) ~= "table" then error("decoded blueprint is not an object", 3) end
    local canonical, version = Serialize.canonical(blueprint)
    local json = helpers.table_to_json(canonical)
    return canonical, {canonical_sha256 = sha256(json), canonical_version = version}
end

local function find_sheet(player_index, sheet_id)
    if type(storage) ~= "table" then return nil end
    local data = storage[player_index]
    local pane = data and data.sheet_section and data.sheet_section.sheet_pane
    for _, tab in ipairs(pane and pane.tabs or {}) do
        local sheet = tab and tab.content
        local tags = sheet and sheet.tags
        if sheet and tags and tags.hxrrc_sheet_id == sheet_id then return sheet end
    end
end

local function locate_sheet(sheet_id)
    if type(storage) ~= "table" then return nil, nil end
    local players = {}
    for player_index, _ in pairs(storage) do
        if type(player_index) == "number" then players[#players + 1] = player_index end
    end
    table.sort(players)
    for _, player_index in ipairs(players) do
        local sheet = find_sheet(player_index, sheet_id)
        if sheet then return player_index, sheet end
    end
end

local function reason_codes(value)
    local result = {}
    local function add(item)
        if type(item) == "string" then result[#result + 1] = item
        elseif type(item) == "table" then
            if item.code or item.reason_code or item.reason then
                add(item.code or item.reason_code or item.reason)
            elseif #item > 0 then
                for _, child in ipairs(item) do add(child) end
            else
                for key, child in pairs(item) do
                    if child and type(key) == "string" and key:match("^BP_") then add(key)
                    else add(child) end
                end
            end
        end
    end
    if type(value) == "table" then
        if value.code or value.reason_code or value.reason then
            add(value)
        elseif value.reason_codes or value.reasons then
            add(value.reason_codes or value.reasons)
        elseif #value > 0 then
            for _, item in ipairs(value) do add(item) end
        else
            for key, item in pairs(value) do
                if item and type(key) == "string" and key:match("^BP_") then add(key) end
            end
        end
    else add(value) end
    table.sort(result)
    local unique = {}
    for _, code in ipairs(result) do
        if not unique[code] then unique[code] = true end
    end
    result = {}
    for code, _ in pairs(unique) do result[#result + 1] = code end
    table.sort(result)
    return result
end

local function start_generation(context)
    packaged_or_error()
    context = copy_plain(context) or {}
    local player_index = context.player_index or 1
    local sheet_id = context.sheet_id
    if sheet_id == nil then error("generation context needs sheet_id", 2) end
    --The player and engine paths share the service and its one registered blueprint kind.
    context.schema_version = 1
    context.player_index, context.sheet_id, context.deliver = player_index, sheet_id, false
    local generation_id, reason = Generation.start(context)
    if not generation_id then error(reason or "generation request refused", 2) end
    next_job_id = next_job_id + 1
    local id = next_job_id
    engine_jobs[id] = {state = "pending", player_index = player_index, sheet_id = sheet_id,
        generation_id = generation_id, progress = {done_units = 0, total_units = nil}, phase = "queued"}
    return id
end

local function generation_status(id)
    packaged_or_error()
    local handle = engine_jobs[id]
    if not handle then error("unknown generation job " .. tostring(id), 2) end
    if handle.terminal then return copy_plain(handle.terminal) end
    local terminal = Generation.status(handle.player_index, handle.generation_id)
    if not terminal then error("unknown generation job " .. tostring(id), 2) end
    handle.state, handle.progress, handle.phase = terminal.state, copy_plain(terminal.progress) or handle.progress,
        terminal.phase or handle.phase
    local result = {
        state = terminal.state, progress = handle.progress, phase = handle.phase,
    }
    if terminal.state == "success" then
        result.blueprint_string = terminal.blueprint_string
        result.canonical_sha256 = terminal.canonical_sha256
        result.canonical_version = terminal.canonical_version
    elseif terminal.state == "failure" then
        result.reason_codes = copy_plain(terminal.reason_codes) or {}
        result.stage = terminal.stage
    end
    if terminal.state ~= "pending" then handle.terminal = copy_plain(result) end
    return result
end

local function cancel_generation(id)
    packaged_or_error()
    local handle = engine_jobs[id]
    if not handle then error("unknown generation job " .. tostring(id), 2) end
    if handle.state == "pending" then
        local cancelled = Generation.cancel(handle.player_index, handle.generation_id)
        if cancelled then
            handle.state = "cancelled"
            handle.phase = "cancelled"
            handle.terminal = {state = "cancelled", progress = copy_plain(handle.progress) or {done_units = 0, total_units = nil}, phase = "cancelled"}
        else
            --A terminal service result wins a late cancel call.  Do not overwrite success or failure merely
            --because this interface handle had not polled it yet.
            local terminal = Generation.status(handle.player_index, handle.generation_id)
            if terminal and terminal.state ~= "pending" then
                handle.state = terminal.state
                handle.phase = terminal.phase or handle.phase
                handle.progress = copy_plain(terminal.progress) or handle.progress
                handle.terminal = copy_plain(generation_status(id))
            end
        end
    end
    return copy_plain(handle.terminal) or {state = "cancelled", phase = "cancelled", progress = handle.progress}
end

local function preflight(case)
    packaged_or_error()
    case = copy_plain(case) or {}
    local reasons = Preflight.check(case.snapshot or case.sheet or {}, case.calculation or case.result or {},
        case.catalog or {}, case.options or case.settings or {})
    local codes = {}
    for _, reason in ipairs(reasons) do codes[#codes + 1] = reason.code end
    return codes
end

local function export_sheet(sheet_id)
    packaged_or_error()
    local player_index, sheet = locate_sheet(sheet_id)
    if not sheet then error("unknown sheet " .. tostring(sheet_id), 2) end
    local payload = ExportPayload.build(player_index, sheet)
    local encoded, reason = ExportPayload.encode(payload)
    if not encoded then error(reason or "debug export failed", 2) end
    return encoded
end

local function canonical(blueprint_string)
    packaged_or_error()
    local _, result = canonical_from_string(blueprint_string)
    return result
end

function EngineTestApi.register()
    if registered then return true end
    local remote = rawget(_G, "remote")
    if not remote then return false end
    local functions = {
        build_id = EngineTestApi.build_id,
        start_generation = start_generation,
        generation_status = generation_status,
        cancel_generation = cancel_generation,
        preflight = preflight,
        export = export_sheet,
        canonical = canonical,
    }
    local ok = pcall(function() remote.add_interface(INTERFACE_NAME, functions) end)
    if ok then registered = true end
    return ok
end

return EngineTestApi
