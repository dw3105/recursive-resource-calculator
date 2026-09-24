-- Heaviest game ticks (2000 ops, as in game) split by module call. Usage: lua5.2 tools/tick_parts.lua <case>
-- Lines: TICK <s> start=<phase> <Module.fn>=<s> ... (calls over 5 ms). Also MAXCALL <Module.fn> <s> per function.
package.path = "./?.lua;" .. package.path
local mods = {Pack = "logic.bp.pack", Route = "logic.bp.route", Power = "logic.bp.power", Groups = "logic.bp.groups",
  Validate = "logic.bp.validate", Hands = "logic.bp.hands", Serialize = "logic.bp.serialize", Plan = "logic.bp.plan", Preflight = "logic.bp.preflight"}
local cur = {}
for name, path in pairs(mods) do
  local M = require(path)
  for fname, f in pairs(M) do if type(f) == "function" then
    M[fname] = function(...) local t = os.clock(); local a, b, c, d = f(...); local k = name .. "." .. fname; cur[k] = (cur[k] or 0) + os.clock() - t; return a, b, c, d end
  end end
end
local Search = require "logic.bp.search"
local ss = Search.step
local ticks = {}
Search.step = function(st, b) b.ops = 2000; cur = {}; local t = os.clock(); local r = ss(st, b); local d = os.clock() - t
  ticks[#ticks + 1] = {d = d, parts = cur, phase = tostring((st.state or st).phase)}
  local s = st.state or st
  if s.done or st.done then
    local maxcall = {}
    for _, k in ipairs(ticks) do for n, v in pairs(k.parts) do if v > (maxcall[n] or 0) then maxcall[n] = v end end end
    local names = {} for n in pairs(maxcall) do names[#names + 1] = n end
    table.sort(names, function(a, b) return maxcall[a] > maxcall[b] end)
    for i = 1, math.min(10, #names) do io.stderr:write(string.format("MAXCALL %s %.3f\n", names[i], maxcall[names[i]])) end
    io.stderr:write(string.format("TICKS %d\n", #ticks))
    table.sort(ticks, function(a, b) return a.d > b.d end)
    for i = 1, 6 do local k = ticks[i]; local p = {} for n, v in pairs(k.parts) do if v > 0.005 then p[#p + 1] = string.format("%s=%.3f", n, v) end end
      table.sort(p); io.stderr:write(string.format("TICK %.3f start=%s %s\n", k.d, k.phase, table.concat(p, " "))) end
    os.exit(0) end
  return r end
arg = {[0] = "tests/golden/generate.lua", "--input", "tests/golden/cases/" .. (arg[1] or "player-green-science-1s") .. "/prepared_input.json", "--output", "/dev/null"}
dofile("tests/golden/generate.lua")
