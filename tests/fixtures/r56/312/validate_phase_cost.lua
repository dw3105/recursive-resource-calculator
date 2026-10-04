--Validate one-phase cost probe, clean lua5.2 (no tests.harness). Usage:
--  lua5.2 tests/fixtures/r56/312/validate_phase_cost.lua <validate state.lua.gz> <phase> [dump.lua.gz]
--Steps the Validate state (4000 ops per call) until cursor.phase == <phase>; with a dump path it saves that state and
--exits; else it runs ONE call in <phase> and prints WEIGHTED <instructions + 78 x tostring> PHASE_AFTER <p>
--ERRORS <n> SIG <digest of codes and metrics> so a change can prove the same answer.
package.path = "./?.lua;" .. package.path
local G = require "tools.lib.graph_dump"
local Validate = require "logic.bp.validate"
local state, phase, dump = G.load(arg[1]), arg[2], arg[3]
--Phases between geometry and the next yield run inside one call: near the end of geometry, step one op at a time.
while not state.done and state.cursor.phase ~= phase do
    local near_end = (state.cursor.phase ~= "geometry" and state.cursor.phase ~= "setup")
        or (state._work and (state.cursor.index or 0) >= #state._work.infos - 2)
    Validate.step(state, {ops = near_end and 1 or 4000})
end
if dump then G.dump(state, dump); print("DUMPED " .. dump); return end
local native, instr, calls = tostring, 0, 0
_G.tostring = function(v) calls = calls + 1; return native(v) end
debug.sethook(function() instr = instr + 1000 end, "", 1000)
Validate.step(state, {ops = 4000})
debug.sethook(); _G.tostring = native
local parts = {}
for _, e in ipairs(state._work.errors or {}) do parts[#parts + 1] = native(e.code) .. ":" .. table.concat(e.ids or {}, ",") end
local eff = state._work.metrics.beacon_effects_by_entity_id or {}
local ids = {}; for id in pairs(eff) do ids[#ids + 1] = native(id) end; table.sort(ids)
for _, id in ipairs(ids) do local e = eff[id]; parts[#parts + 1] = id .. "=" .. string.format("%.6f/%.6f/%.6f/%.6f", e.speed, e.consumption, e.pollution, e.quality) end
local text = table.concat(parts, ";")
local sum = 0; for i = 1, #text do sum = (sum * 31 + text:byte(i)) % 4294967296 end
print("WEIGHTED " .. (instr + 78 * calls) .. " PHASE_AFTER " .. native(state.cursor.phase) .. " ERRORS " .. #(state._work.errors or {})
    .. " SIG " .. string.format("%08x", sum) .. " len=" .. #text)
