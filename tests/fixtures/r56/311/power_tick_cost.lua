--PF4 probe, run in a clean lua5.2 (no tests.harness: it swaps _G.type for a Lua function the engine never has).
--Loads a mid-run Power state (graph_dump), steps it at arg[2] ops (4000) and prints
--WORST <weighted> (VM instructions, hook every 1000, + 78 x tostring calls per Power.step) and RESULT <json length>.
package.path = "./?.lua;" .. package.path
local G = require "tools.lib.graph_dump"
local Power = require "logic.bp.power"
local path, ops = arg[1] or "tests/fixtures/r56/rg_power_t312.lua.gz", tonumber(arg[2]) or 4000
local state, worst, steps = G.load(path), 0, 0
local native = tostring
while not state.done and steps < 1000000 do
    local instr, calls = 0, 0
    _G.tostring = function(v) calls = calls + 1; return native(v) end
    debug.sethook(function() instr = instr + 1000 end, "", 1000)
    Power.step(state, {ops = ops})
    debug.sethook(); _G.tostring = native
    worst = math.max(worst, instr + 78 * calls); steps = steps + 1
end
local one = G.load(path)
while not one.done do Power.step(one, {ops = 1000000000}) end
local function same(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}; if seen[a] then return true end; seen[a] = true
    for k, v in pairs(a) do if not same(v, b[k], seen) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
print("WORST " .. worst)
print("STEPS " .. steps)
print("SAME " .. tostring(state.done and same(state.result, one.result)))
