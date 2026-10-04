--GS8 probe, run in a clean lua5.2 (no tests.harness: it swaps _G.type for a Lua function the engine never has).
--Prints WORST <weighted> where weighted = VM instructions (hook every 1000) + 78 x tostring calls per Groups.step.
package.path = "./?.lua;" .. package.path
local f = assert(io.open("tests/golden/generate.lua")); local gen = f:read("*a"):gsub("^#![^\n]*\n", ""); f:close()
local a = gen:find("local JSON = {}", 1, true); local b = gen:find("local input_path,", a, true)
local JSON = assert(load(gen:sub(a, b - 1) .. "\nreturn JSON"))()
local input = JSON.decode(assert(io.open(arg[1] or "tests/fixtures/r56/310/blue_bound_groups.json")):read("*a"))
local Groups = require "logic.bp.groups"
local ops = tonumber(arg[2]) or 4000
local state, worst = Groups.begin(input), 0
local native = tostring
while not state.done do
    local instr, calls = 0, 0
    _G.tostring = function(v) calls = calls + 1; return native(v) end
    debug.sethook(function() instr = instr + 1000 end, "", 1000)
    Groups.step(state, {ops = ops})
    debug.sethook(); _G.tostring = native
    worst = math.max(worst, instr + 78 * calls)
end
print("WORST " .. worst)
