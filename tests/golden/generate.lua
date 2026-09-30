#!/usr/bin/env lua
-- Run the repository's real blueprint search over a captured PreparedInput.
-- This file deliberately owns only the JSON/process boundary; planning, packing,
-- routing, validation and serialization remain the production Lua modules.

local function script_directory()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    return source:match("^(.*)[/\\][^/\\]+$") or "."
end

local SCRIPT_DIR = script_directory()
local ROOT = SCRIPT_DIR .. "/../.."
package.path = ROOT .. "/?.lua;" .. ROOT .. "/?/init.lua;" .. package.path
require("tools.lib.slow_guard").check("golden generate", (function() for i=1,#arg do if arg[i]=="--input" then return arg[i+1] end end end)())

local function fail(message)
    io.stderr:write("golden generate: " .. tostring(message) .. "\n")
    os.exit(2)
end

-- A small JSON reader is kept here so this command can run with the same stock
-- Lua interpreter used by the offline tests.  It accepts the plain data shape
-- of PreparedInput and does not invent a Python-side generator.
local JSON = {}

local function utf8_char(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    if code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40,
            0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function json_reader(text)
    local index = 1
    local length = #text

    local function skip_space()
        while index <= length and text:sub(index, index):match("%s") do index = index + 1 end
    end

    local parse_value
    local function parse_string()
        index = index + 1
        local result = {}
        while index <= length do
            local character = text:sub(index, index)
            if character == '"' then
                index = index + 1
                return table.concat(result)
            end
            if character == "\\" then
                index = index + 1
                local escaped = text:sub(index, index)
                local replacements = {['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}
                if escaped == "u" then
                    local digits = text:sub(index + 1, index + 4)
                    if not digits:match("^%x%x%x%x$") then error("invalid unicode escape") end
                    local code = tonumber(digits, 16)
                    index = index + 5
                    if code >= 0xD800 and code <= 0xDBFF and text:sub(index + 1, index + 2) == "\\u" then
                        local low_digits = text:sub(index + 3, index + 6)
                        local low = tonumber(low_digits, 16)
                        if low and low >= 0xDC00 and low <= 0xDFFF then
                            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                            index = index + 6
                        end
                    end
                    result[#result + 1] = utf8_char(code)
                elseif replacements[escaped] then
                    result[#result + 1] = replacements[escaped]
                    index = index + 1
                else
                    error("invalid string escape")
                end
            else
                if string.byte(character) < 0x20 then error("control character in string") end
                result[#result + 1] = character
                index = index + 1
            end
        end
        error("unterminated string")
    end

    local function parse_number()
        local start = index
        if text:sub(index, index) == "-" then index = index + 1 end
        if text:sub(index, index) == "0" then
            index = index + 1
        else
            if not text:sub(index, index):match("%d") then error("invalid number") end
            while text:sub(index, index):match("%d") do index = index + 1 end
        end
        if text:sub(index, index) == "." then
            index = index + 1
            if not text:sub(index, index):match("%d") then error("invalid number fraction") end
            while text:sub(index, index):match("%d") do index = index + 1 end
        end
        if text:sub(index, index):match("[eE]") then
            index = index + 1
            if text:sub(index, index):match("[+-]") then index = index + 1 end
            if not text:sub(index, index):match("%d") then error("invalid number exponent") end
            while text:sub(index, index):match("%d") do index = index + 1 end
        end
        local value = tonumber(text:sub(start, index - 1))
        if value == nil then error("invalid number") end
        return value
    end

    local function parse_array()
        index = index + 1
        local result = {}
        skip_space()
        if text:sub(index, index) == "]" then index = index + 1; return result end
        while true do
            result[#result + 1] = parse_value()
            skip_space()
            local delimiter = text:sub(index, index)
            if delimiter == "]" then index = index + 1; return result end
            if delimiter ~= "," then error("expected array delimiter") end
            index = index + 1
            skip_space()
        end
    end

    local function parse_object()
        index = index + 1
        local result = {}
        skip_space()
        if text:sub(index, index) == "}" then index = index + 1; return result end
        while true do
            if text:sub(index, index) ~= '"' then error("object key is not a string") end
            local key = parse_string()
            skip_space()
            if text:sub(index, index) ~= ":" then error("expected object colon") end
            index = index + 1
            result[key] = parse_value()
            skip_space()
            local delimiter = text:sub(index, index)
            if delimiter == "}" then index = index + 1; return result end
            if delimiter ~= "," then error("expected object delimiter") end
            index = index + 1
            skip_space()
        end
    end

    parse_value = function()
        skip_space()
        local character = text:sub(index, index)
        if character == '"' then return parse_string() end
        if character == "{" then return parse_object() end
        if character == "[" then return parse_array() end
        if text:sub(index, index + 3) == "true" then index = index + 4; return true end
        if text:sub(index, index + 4) == "false" then index = index + 5; return false end
        if text:sub(index, index + 3) == "null" then index = index + 4; return nil end
        return parse_number()
    end

    local value = parse_value()
    skip_space()
    if index <= length then error("trailing JSON data") end
    return value
end

local function json_escape(value)
    local replacements = {['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
        ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
    return (value:gsub('[%z\1-\31"\\]', function(character)
        return replacements[character] or string.format("\\u%04x", string.byte(character))
    end))
end

local function number_text(value)
    if value ~= value or value == math.huge or value == -math.huge then error("non-finite JSON number") end
    if value == math.floor(value) then return string.format("%.0f", value) end
    return string.format("%.17g", value)
end

local function object_keys(value)
    local keys = {}
    for key, _ in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function is_array(value)
    local count = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
        count = math.max(count, key)
    end
    for index = 1, count do if value[index] == nil then return false end end
    return true, count
end

local function json_encode(value)
    local value_type = type(value)
    if value == nil then return "null" end
    if value_type == "boolean" then return value and "true" or "false" end
    if value_type == "number" then return number_text(value) end
    if value_type == "string" then return '"' .. json_escape(value) .. '"' end
    if value_type ~= "table" then error("cannot encode " .. value_type) end
    local array, count = is_array(value)
    local result = {}
    if array then
        for index = 1, count do result[#result + 1] = json_encode(value[index]) end
        return "[" .. table.concat(result, ",") .. "]"
    end
    for _, key in ipairs(object_keys(value)) do
        result[#result + 1] = json_encode(tostring(key)) .. ":" .. json_encode(value[key])
    end
    return "{" .. table.concat(result, ",") .. "}"
end

JSON.decode = json_reader
JSON.encode = json_encode

-- Lua 5.2 provides bit32 (as Factorio does).  Lua 5.4 does not, so the
-- fallback keeps the standalone conformance command usable with both runtimes.
local bit = rawget(_G, "bit32")
if not bit then
    local UINT = 4294967296
    local function norm(value) return value % UINT end
    local function binary(a, b, operation)
        a, b = norm(a), norm(b)
        local result, place = 0, 1
        for _ = 1, 32 do
            local aa, bb = a % 2, b % 2
            if operation(aa, bb) then result = result + place end
            a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
        end
        return result
    end
    bit = {
        band = function(a, b) return binary(a, b, function(x, y) return x == 1 and y == 1 end) end,
        bxor = function(a, b, c)
            local result = binary(a, b, function(x, y) return x ~= y end)
            if c ~= nil then result = binary(result, c, function(x, y) return x ~= y end) end
            return result
        end,
        rshift = function(a, amount) return math.floor(norm(a) / 2 ^ amount) end,
        rrotate = function(a, amount)
            amount = amount % 32
            local value = norm(a)
            return math.floor(value / 2 ^ amount) + (value % 2 ^ amount) * 2 ^ (32 - amount) % UINT
        end,
    }
end

local function sha256_lua(text)
    local band, bxor = bit.band, bit.bxor
    local rshift, rrotate = bit.rshift, bit.rrotate
    local k = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e,
        0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585,
        0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    }
    local h = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}
    local bit_length = #text * 8
    text = text .. string.char(128)
    while (#text + 8) % 64 ~= 0 do text = text .. string.char(0) end
    local high, low = math.floor(bit_length / 4294967296), bit_length % 4294967296
    text = text .. string.char(
        band(rshift(high, 24), 255), band(rshift(high, 16), 255), band(rshift(high, 8), 255), band(high, 255),
        band(rshift(low, 24), 255), band(rshift(low, 16), 255), band(rshift(low, 8), 255), band(low, 255))
    local function word(offset)
        return band(text:byte(offset) * 16777216 + text:byte(offset + 1) * 65536
            + text:byte(offset + 2) * 256 + text:byte(offset + 3), 0xffffffff)
    end
    local function add(a, b, c, d, e) return band((a or 0) + (b or 0) + (c or 0) + (d or 0) + (e or 0), 0xffffffff) end
    for offset = 1, #text, 64 do
        local w = {}
        for index = 0, 15 do w[index] = word(offset + index * 4) end
        for index = 16, 63 do
            local x, y = w[index - 15], w[index - 2]
            w[index] = add(w[index - 16], bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3)),
                w[index - 7], bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10)))
        end
        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for index = 0, 63 do
            local choose = bxor(band(e, f), band(bxor(e, 0xffffffff), g))
            local temp1 = add(hh, bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25)), choose, k[index + 1], w[index])
            local majority = bxor(band(a, b), band(a, c), band(b, c))
            local temp2 = add(bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22)), majority)
            hh, g, f, e, d, c, b, a = g, f, e, add(d, temp1), d, c, b, add(temp1, temp2)
        end
        h[1], h[2], h[3], h[4] = add(h[1], a), add(h[2], b), add(h[3], c), add(h[4], d)
        h[5], h[6], h[7], h[8] = add(h[5], e), add(h[6], f), add(h[7], g), add(h[8], hh)
    end
    local result = {}
    for _, value in ipairs(h) do result[#result + 1] = string.format("%08x", value) end
    return table.concat(result)
end

-- The game-side interface has its own digest implementation.  The offline
-- bridge uses the host's standard SHA-256 primitive so the receipt is the
-- same digest Python computes for the canonical JSON bytes.  The Lua fallback
-- above keeps the module self-contained on hosts without sha256sum.
local function sha256(text)
    if io.popen and os and os.tmpname then
        local path = os.tmpname()
        local handle = io.open(path, "wb")
        if handle then
            handle:write(text)
            handle:close()
            local quoted = "'" .. path:gsub("'", "'\\''") .. "'"
            local pipe = io.popen("sha256sum " .. quoted, "r")
            local line = pipe and pipe:read("*l") or nil
            if pipe then pipe:close() end
            os.remove(path)
            local digest = line and line:match("^([0-9a-fA-F]+)")
            if digest then return digest:lower() end
        end
    end
    return sha256_lua(text)
end

local function read_file(path)
    local handle, error_message = io.open(path, "rb")
    if not handle then fail(error_message) end
    local value = handle:read("*a")
    handle:close()
    return value
end

local function write_output(value, path)
    local encoded = JSON.encode(value)
    if path then
        local handle, error_message = io.open(path, "wb")
        if not handle then fail(error_message) end
        handle:write(encoded, "\n")
        handle:close()
    else
        io.write(encoded, "\n")
    end
end

local function plan_complete(value)
    return type(value) == "table" and type(value.steps) == "table" and #value.steps > 0
end

local function verified_plan(value, prepared, input_digest)
    if not plan_complete(value) then return nil, "captured planning result is missing or empty" end
    local declared_digest = prepared.plan_sha256 or prepared.plan_digest
    if declared_digest and string.lower(tostring(declared_digest)) ~= sha256(JSON.encode(value)) then
        return nil, "captured planning result digest does not match its content"
    end
    local declared_input = prepared.plan_input_sha256 or prepared.prepared_input_sha256
    if declared_input and (not input_digest or string.lower(tostring(declared_input)) ~= input_digest) then
        return nil, "captured planning result is bound to a different input"
    end
    return value
end

local function captured_plan(prepared, input_digest)
    local supplied = prepared.plan_result
    if supplied == nil then supplied = prepared.plan end
    if supplied ~= nil then
        return verified_plan(supplied, prepared, input_digest)
    end
    local artifact = prepared.plan_artifact
    if type(artifact) == "table" then
        local artifact_plan = artifact.plan_result or artifact.plan or artifact.result
        local artifact_digest = artifact.plan_sha256 or artifact.plan_digest or artifact.sha256
        local artifact_input = artifact.prepared_input_sha256 or artifact.input_sha256
        if type(artifact_plan) ~= "table" or not artifact_digest or not artifact_input then
            return nil, "plan artifact is not verified against this input"
        end
        if string.lower(tostring(artifact_input)) ~= tostring(input_digest or "")
            or string.lower(tostring(artifact_digest)) ~= sha256(JSON.encode(artifact_plan)) then
            return nil, "plan artifact does not match this input or its content"
        end
        return verified_plan(artifact_plan, prepared, input_digest)
    end

    -- A PreparedInput normally carries the solver facts, not a second copy of the
    -- planner's IR.  Rebuild that IR through the production planner so validation
    -- sees the same steps the search saw, rather than an empty table or candidate
    -- supplied plan.
    if type(prepared.solver_result) ~= "table" and type(prepared.solver) ~= "table"
        and type(prepared.result) ~= "table" and type(prepared.columns) ~= "table" then
        return nil, "captured input has no planning result"
    end
    local Plan = require "logic.bp.plan"
    local state = Plan.begin(prepared)
    while not state.done do Plan.step(state, {ops = 1000000}) end
    if state.ok ~= true or not plan_complete(state.result) then
        return nil, "captured input did not produce a complete planning result"
    end
    return state.result
end

local function validation_error(code, detail)
    return {ok = false, errors = {{code = code, detail = detail}}}
end

local function run_physical_validation(Validate, candidate, plan, catalog)
    local began, state = pcall(function()
        return Validate.begin({candidate = candidate, plan = plan, catalog = catalog})
    end)
    if not began then return validation_error("BP_V_ARTIFACT_PHYSICAL", tostring(state)) end
    local stepped, step_error = pcall(function()
        while not state.done do Validate.step(state, {ops = 1000000}) end
    end)
    if not stepped then return validation_error("BP_V_ARTIFACT_PHYSICAL", tostring(step_error)) end
    return {ok = state.ok == true, result = state.result, errors = state.errors}
end

local function artifact_validation(Validate, candidate, prepared, internal_candidate)
    -- The artifact carries no step identity: that is internal bookkeeping the game never sees. The internal
    -- candidate is supplied only to bind a decoded artifact entity to its plan step by physical position.
    local plan = prepared.plan_result
    local catalog = prepared.catalog or {}
    -- Keep this assignment as a named boundary: the lane mutation oracle replaces its value to prove that the
    -- golden tests fail when physical validation is bypassed.
    -- The physical pass needs the producer's bindings (step_id, ports and segments) to walk obligations. The
    -- decoded artifact is still the only object sent to reconciliation below; reconciliation binds those fields
    -- back to the producer candidate by position and catches serialization loss or mutation.
    local physical_candidate = internal_candidate or candidate
    local physical = run_physical_validation(Validate, physical_candidate, plan, catalog)

    local reconciliation_input = {artifact = candidate, plan = plan, catalog = catalog, internal = internal_candidate}
    local reconciliation
    if not plan_complete(plan) then
        reconciliation = validation_error("BP_CAP_INCOMPLETE", "validation plan is missing")
    elseif type(Validate.reconcile_artifact) ~= "function" then
        reconciliation = validation_error("BP_V_ARTIFACT_RECONCILE", "reconciliation entry point is missing")
    else
        local reconciled, result = pcall(Validate.reconcile_artifact, reconciliation_input)
        if reconciled and type(result) == "table" then
            reconciliation = result
        elseif reconciled then
            reconciliation = validation_error("BP_V_ARTIFACT_RECONCILE", "invalid reconciliation result")
        else
            reconciliation = validation_error("BP_V_ARTIFACT_RECONCILE", tostring(result))
        end
    end

    local errors = {}
    for _, checked in ipairs({physical, reconciliation}) do
        for _, error_record in ipairs(checked.errors or {}) do errors[#errors + 1] = error_record end
    end
    return {ok = physical.ok == true and reconciliation.ok == true,
        result = physical.result, errors = #errors > 0 and errors or nil,
        physical = physical, reconciliation = reconciliation}
end

local input_path, output_path, canonical_path, validate_path
local index = 1
while index <= #arg do
    local option = arg[index]
    if option == "--input" then input_path = arg[index + 1]; index = index + 2
    elseif option == "--output" then output_path = arg[index + 1]; index = index + 2
    elseif option == "--canonical" then canonical_path = arg[index + 1]; index = index + 2
    elseif option == "--validate" then validate_path = arg[index + 1]; index = index + 2
    elseif not input_path then input_path = option; index = index + 1
    else fail("unknown argument " .. tostring(option)) end
end

if not input_path and not canonical_path and not validate_path then fail("usage: generate.lua --input prepared_input.json [--output result.json]") end

local ok, result_or_error = xpcall(function()
    local Serialize = require "logic.bp.serialize"
    if canonical_path then
        local source = JSON.decode(read_file(canonical_path))
        local canonical, version = Serialize.canonical(source)
        local encoded = JSON.encode(canonical)
        return {schema_version = 1, source = "lua-canonical", canonical = canonical, canonical_version = version,
            canonical_json = encoded, canonical_sha256 = sha256(encoded)}
    end

    local prepared = input_path and JSON.decode(read_file(input_path)) or {}
    if type(prepared) ~= "table" then error("prepared input must be an object") end
    if type(prepared.prepared_input) == "table" then prepared = prepared.prepared_input end
    if type(prepared.catalog) == "table" and prepared.catalog.material == nil then
        local MaterialCost = require("logic.bp.material_cost")
        local fixture = ROOT .. "/tests/fixtures/material_cost_2.1.txt"
        local file = io.open(fixture, "r")
        if not file then fixture = ROOT .. "/tests/fixtures/material_cost_2.0.txt"; file = assert(io.open(fixture, "r")) end
        local text = file:read("*a"); file:close()
        prepared.catalog.material = MaterialCost.parse_fixture(text)
    end

    local input_digest = input_path and sha256(read_file(input_path)) or nil
    local plan, plan_error = captured_plan(prepared, input_digest)
    if not plan then
        return {schema_version = 1, source = validate_path and "lua-validator" or "lua-generator", ok = false,
            stage = validate_path and "validate" or "plan", errors = {{code = "BP_CAP_INCOMPLETE", detail = plan_error}}}
    end
    prepared.plan_result = plan

    if validate_path then
        local Validate = require "logic.bp.validate"
        local candidate = JSON.decode(read_file(validate_path))
        if type(candidate) == "table" and type(candidate.result) == "table" then candidate = candidate.result end
        if type(candidate) == "table" and type(candidate.candidate) == "table" then candidate = candidate.candidate end
        local validation = artifact_validation(Validate, candidate, prepared)
        return {schema_version = 1, source = "lua-validator", ok = validation.ok == true,
            result = validation.result, errors = validation.errors, physical = validation.physical,
            reconciliation = validation.reconciliation, validation = validation, stage = "validate"}
    end

    local Search = require "logic.bp.search"
    local state = Search.begin(prepared)
    local limit = tonumber(prepared.max_generator_ops or prepared.generator_ops or 1000000) or 1000000
    local ticks = 0
    while not state.done do
        ticks = ticks + 1
        if ticks > limit then error("generator exceeded operation safety limit") end
        Search.step(state, {ops = tonumber(prepared.ops_per_step) or 100000})
    end
    if state.ok ~= true or type(state.result) ~= "table" then
        return {schema_version = 1, source = "lua-generator", ok = false, stage = state.phase or "search",
            errors = state.errors or {{code = "BP_FAIL_NO_LAYOUT_GRID_LIMIT"}}, progress = state.progress}
    end
    -- Search's result is the serializer's output table.  Treat the encoded/decoded export as the certified
    -- object so validation cannot accidentally certify the serializer's intermediate candidate.
    local exported_json = JSON.encode(state.result)
    local exported = JSON.decode(exported_json)
    local canonical, version = Serialize.canonical(exported)
    local encoded = JSON.encode(canonical)
    local validation
    if state.incumbent and state.incumbent.candidate then
        local Validate = require "logic.bp.validate"
        validation = artifact_validation(Validate, exported, prepared, state.incumbent.candidate)
    else
        validation = validation_error("BP_V_ARTIFACT_PHYSICAL", "generator produced no bound candidate")
    end
    return {schema_version = 1, source = "lua-generator", ok = validation.ok == true, stage = "done", ticks = ticks,
        canonical = canonical, canonical_version = version, canonical_json = encoded,
        canonical_sha256 = sha256(encoded), result = exported,
        validation = validation}
end, function(error_message) return debug.traceback(tostring(error_message), 2) end)

if not ok then fail(result_or_error) end
write_output(result_or_error, output_path)
