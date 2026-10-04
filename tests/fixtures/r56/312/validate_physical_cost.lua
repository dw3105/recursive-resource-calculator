--Worst single Validate.step weighted cost while in one phase (default physical), clean lua5.2 (no tests.harness).
--Usage: lua5.2 tests/fixtures/r56/312/validate_physical_cost.lua <state at that phase.lua.gz> [phase]
package.path = "./?.lua;" .. package.path
local G = require "tools.lib.graph_dump"
local Validate = require "logic.bp.validate"
local state, phase = G.load(arg[1]), arg[2] or "physical"
local native, worst, steps = tostring, 0, 0
while not state.done and state.cursor.phase == phase do
    local instr, calls = 0, 0
    _G.tostring = function(v) calls = calls + 1; return native(v) end
    debug.sethook(function() instr = instr + 1000 end, "", 1000)
    Validate.step(state, {ops = 4000}); state.yield_tick = nil
    debug.sethook(); _G.tostring = native
    worst = math.max(worst, instr + 78 * calls); steps = steps + 1
end
local parts = {}
for _, e in ipairs(state._work.errors or {}) do parts[#parts + 1] = native(e.code) .. ":" .. table.concat(e.ids or {}, ",") end
local w = state._work.metrics.transfer_witnesses or {}
print("WORST " .. worst .. " STEPS " .. steps .. " ERRORS " .. #(state._work.errors or {}) .. " WITNESSES " .. #w .. " " .. table.concat(parts, ";"))
