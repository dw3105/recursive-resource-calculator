--PipeRuns.prune_redundant replay on a dumped route work table (graph_dump), clean lua5.2 (no tests.harness).
--Usage: lua5.2 tests/fixtures/r56/309/prune_tick_cost.lua <work.lua.gz>. Prints WEIGHTED <instructions + 78 x tostring>
--REMOVED <n> and SHA <digest of kept segment ids and bindings> so a change can prove the same answer.
package.path = "./?.lua;" .. package.path
local G = require "tools.lib.graph_dump"
local PipeRuns = require "logic.bp.pipe_runs"
local work = G.load(arg[1])
local KEY = {}
local h = {
    key = function(x, y)
        local row = KEY[x]; if row == nil then row = {}; KEY[x] = row end
        local k = row[y]; if k == nil then k = tostring(x) .. ":" .. tostring(y); row[y] = k end
        return k
    end,
    coordinate_from_key = function(key)
        local x, y = string.match(key, "^([^:]+):([^:]+)$")
        if x == nil then return nil end
        return tonumber(x), tonumber(y)
    end,
}
local native, instr, calls = tostring, 0, 0
_G.tostring = function(v) calls = calls + 1; return native(v) end
debug.sethook(function() instr = instr + 1000 end, "", 1000)
local removed = PipeRuns.prune_redundant(work, h)
debug.sethook(); _G.tostring = native
local ids = {}
for _, segment in ipairs(work.segments or {}) do ids[#ids + 1] = native(segment.segment_id) end
for _, binding in ipairs(work.bindings or {}) do ids[#ids + 1] = "b" .. native(binding.segment_id) end
local text = table.concat(ids, ",")
local sum = 0
for i = 1, #text do sum = (sum * 31 + text:byte(i)) % 4294967296 end
print("WEIGHTED " .. (instr + 78 * calls))
print("REMOVED " .. removed)
print("SHA " .. string.format("%08x", sum) .. " len=" .. #text)
