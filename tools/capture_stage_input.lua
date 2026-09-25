-- Save the input of the FIRST call of one stage for one prepared input as JSON (round 36), so a test can replay
-- one real candidate through that stage in seconds instead of generating the whole sheet.
-- Usage (repository root): lua5.2 tools/capture_stage_input.lua <prepared_input.json> <out.json> [stage] [call]
-- stage: validate (default), route, groups, pack, power -- any logic/bp/<stage>.lua with begin().
package.path = "./?.lua;./?/init.lua;" .. package.path
local input, out, stage = assert(arg[1], "prepared input"), assert(arg[2], "output path"), arg[3] or "validate"
local wanted_call, calls = tonumber(arg[4] or "1"), 0

local function escape(s)
    return (s:gsub('[%c"\\]', function(c)
        local map = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
        return map[c] or string.format("\\u%04x", c:byte())
    end))
end
local function number_text(n)
    if n ~= n or n == math.huge or n == -math.huge then return "null" end
    if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
    return string.format("%.17g", n)
end
local function encode(value, stack)
    local t = type(value)
    if value == nil then return "null" end
    if t == "boolean" then return value and "true" or "false" end
    if t == "number" then return number_text(value) end
    if t == "string" then return '"' .. escape(value) .. '"' end
    if t ~= "table" then return "null" end
    if stack[value] then return "null" end -- a cycle is cut; shared tables are written twice
    stack[value] = true
    local count, keys = 0, {}
    for k in pairs(value) do keys[#keys + 1] = k; if type(k) == "number" then count = math.max(count, k) end end
    local array = #keys > 0 and count == #keys
    for i = 1, count do if value[i] == nil then array = false end end
    local parts = {}
    if array then
        for i = 1, count do parts[#parts + 1] = encode(value[i], stack) end
        stack[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        if type(value[k]) ~= "function" then parts[#parts + 1] = encode(tostring(k), stack) .. ":" .. encode(value[k], stack) end
    end
    stack[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local V = require("logic.bp." .. stage)
local original_begin = V.begin
V.begin = function(root)
    calls = calls + 1
    if calls < wanted_call then return original_begin(root) end
    local f = assert(io.open(out, "w"))
    f:write(encode(root, {}))
    f:close()
    io.stderr:write("CAPTURED " .. out .. "\n")
    os.exit(0)
end
arg = {[0] = "tests/golden/generate.lua", "--input", input, "--output", "/dev/null"}
dofile("tests/golden/generate.lua")
