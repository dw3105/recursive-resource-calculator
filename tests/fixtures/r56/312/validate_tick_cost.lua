--Validate Tick cost probe, clean lua5.2 (no tests.harness: it swaps _G.type for a Lua function the engine lacks).
--Usage: lua5.2 tests/fixtures/r56/312/validate_tick_cost.lua <validate input.json> [ops]. Prints WORST <weighted> <phase>.
package.path = "./?.lua;" .. package.path
local f = assert(io.open("tests/golden/generate.lua")); local gen = f:read("*a"):gsub("^#![^\n]*\n", ""); f:close()
local a = gen:find("local JSON = {}", 1, true); local b = gen:find("local input_path,", a, true)
local JSON = assert(load(gen:sub(a, b - 1) .. "\nreturn JSON"))()
local input = JSON.decode(assert(io.open(arg[1])):read("*a"))
local Validate = require "logic.bp.validate"
local ops = tonumber(arg[2]) or 4000
local state, worst, phase = Validate.begin(input), 0, ""
local native = tostring
while not state.done do
    local ph, instr, calls = state.cursor.phase, 0, 0
    _G.tostring = function(v) calls = calls + 1; return native(v) end
    debug.sethook(function() instr = instr + 1000 end, "", 1000)
    Validate.step(state, {ops = ops})
    debug.sethook(); _G.tostring = native
    if instr + 78 * calls > worst then worst, phase = instr + 78 * calls, ph end
end
print("WORST " .. worst .. " " .. phase .. " codes=" .. #(state.errors or {}))
