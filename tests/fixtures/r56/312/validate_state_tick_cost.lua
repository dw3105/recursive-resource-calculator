--Validate Tick cost probe on a mid-run Validate state (graph_dump .lua.gz), clean lua5.2 (no tests.harness: it swaps
--_G.type for a Lua function the engine lacks). Usage: lua5.2 tests/fixtures/r56/312/validate_state_tick_cost.lua
--<state.lua.gz> [ops]. Prints WORST <weighted> <phase> codes=<n> (weighted = instructions + 78 x tostring calls).
package.path = "./?.lua;" .. package.path
local G = require "tools.lib.graph_dump"
local Validate = require "logic.bp.validate"
local ops = tonumber(arg[2]) or 4000
local state, worst, phase = G.load(arg[1] or "tests/fixtures/r56/rg_validate_t812.lua.gz"), 0, ""
local native = tostring
while not state.done do
    local ph, instr, calls = state.cursor and state.cursor.phase or state.phase, 0, 0
    _G.tostring = function(v) calls = calls + 1; return native(v) end
    debug.sethook(function() instr = instr + 1000 end, "", 1000)
    Validate.step(state, {ops = ops})
    debug.sethook(); _G.tostring = native
    if instr + 78 * calls > worst then worst, phase = instr + 78 * calls, tostring(ph) end
end
local codes = {}
for _, e in ipairs(state.errors or (state.result and state.result.errors) or {}) do codes[#codes + 1] = tostring(e.code) end
print("WORST " .. worst .. " " .. phase .. " codes=" .. #codes .. " " .. table.concat(codes, ","))
