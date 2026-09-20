--Capture the first candidate that reaches the independent validator, as replayable plain data.
--A repair loop that has to rediscover a layout through a whole multi-grid search pays a minute per attempt.
--This writes the exact Validate.begin input once, so every later attempt is a replay of the same candidate.
--
--  lua5.2 tests/diag/capture_validate_input.lua item_chain tests/fixtures/validate/item_chain_first.lua
local Chains = require "tests.acceptance.lib.chains"
local H = require "tests.harness"

local which = arg and arg[1] or "item_chain"
local out_path = arg and arg[2] or ("tests/fixtures/validate/" .. which .. "_first.lua")

local function sorted_keys(value)
    local numbers, strings = {}, {}
    for key in pairs(value) do
        if type(key) == "number" then numbers[#numbers + 1] = key
        elseif type(key) == "string" then strings[#strings + 1] = key end
    end
    table.sort(numbers)
    table.sort(strings)
    return numbers, strings
end

local function quote(value)
    return string.format("%q", value)
end

local function number_text(value)
    if value ~= value then return "0/0" end
    if value == math.huge then return "math.huge" end
    if value == -math.huge then return "-math.huge" end
    if math.floor(value) == value and math.abs(value) < 1e15 then return string.format("%d", value) end
    return string.format("%.17g", value)
end

local function dump(value, indent, out)
    local kind = type(value)
    if kind == "number" then out[#out + 1] = number_text(value); return end
    if kind == "string" then out[#out + 1] = quote(value); return end
    if kind == "boolean" then out[#out + 1] = tostring(value); return end
    if kind ~= "table" then out[#out + 1] = "nil"; return end
    local numbers, strings = sorted_keys(value)
    if #numbers == 0 and #strings == 0 then out[#out + 1] = "{}"; return end
    local pad = string.rep(" ", indent + 4)
    out[#out + 1] = "{\n"
    for _, key in ipairs(numbers) do
        out[#out + 1] = pad
        dump(value[key], indent + 4, out)
        out[#out + 1] = ",\n"
    end
    for _, key in ipairs(strings) do
        out[#out + 1] = pad .. key:gsub("^([^%a_])", "[%1") .. " = "
        if not key:match("^[%a_][%w_]*$") then
            out[#out] = pad .. "[" .. quote(key) .. "] = "
        end
        dump(value[key], indent + 4, out)
        out[#out + 1] = ",\n"
    end
    out[#out + 1] = string.rep(" ", indent) .. "}"
end

local chain = Chains[which]("2.0")
local Validate = require "logic.bp.validate"
local validate_begin = Validate.begin
local captured
Validate.begin = function(input)
    if captured == nil then captured = input end
    return validate_begin(input)
end

local Generation = require "logic.bp.generation"
local settings = require("logic.bp.settings").of_sheet(1, chain.sheet_id)
local job_id = Generation.start{player_index = 1, sheet_id = chain.sheet_id, settings = settings, deliver = false}
local result = Generation.status(1, job_id)
local ticks = 0
while result.state == "pending" and captured == nil and ticks < 2000 do
    H.run_ticks(chain.world, 1)
    ticks = ticks + 1
    result = Generation.status(1, job_id)
end
Validate.begin = validate_begin

if captured == nil then
    print("CAPTURE none: state=" .. tostring(result.state) .. " stage=" .. tostring(result.stage or result.phase)
        .. " ticks=" .. ticks)
    os.exit(1)
end

local out = {}
dump(captured, 0, out)
local file = assert(io.open(out_path, "w"))
file:write("--Frozen Validate.begin input: first candidate of the " .. which .. " chain.\n")
file:write("--source_kind = \"harness\"; captured by tests/diag/capture_validate_input.lua.\n")
file:write("--Expected supported outcome: a valid layout. Preserve as a positive case; it is not a rejection.\n")
file:write("return " .. table.concat(out) .. "\n")
file:close()
print("CAPTURE wrote " .. out_path .. " after " .. ticks .. " ticks")
