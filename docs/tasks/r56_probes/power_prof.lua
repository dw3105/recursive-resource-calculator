-- power_prof.lua (cwd = ~/wt-rrc-speed06): where does the power span spend VM instructions?
-- usage: lua5.2 power_prof.lua <checkpoint at phase=power> <stop-phase> [levers]
-- Count hook every 100 instructions; charge sample to the innermost power.lua frame: function linedefined, and
-- for Power.step itself the cursor phase being run (read from the step's state local).
package.path = "./?.lua;" .. package.path
local P = os.getenv("HOME") .. "/.claude/plans/wayfinder-rrc-speed/research/06-probe"
local Graph = require "tools.lib.graph_dump"
_G.P06_LEVERS = arg[3] or ""
local patch = dofile(P .. "/p06.lua")
local native_require = require
_G.require = function(name)
    if type(name) == "string" and name:match("^logic%.bp%.") then
        if package.loaded[name] ~= nil then return package.loaded[name] end
        local path = name:gsub("%.", "/") .. ".lua"
        local f = assert(io.open(path, "r")); local src = f:read("*a"); f:close()
        src = patch(name, src)
        local v = assert(load(src, "@" .. path))(); package.loaded[name] = v; return v
    end
    return native_require(name)
end
local Search = require "logic.bp.search"
local d = Graph.load(arg[1]); local st = d.state or d
local stop = arg[2]
local by, total, outside = {}, 0, 0
local function hook()
    total = total + 1
    for level = 2, 30 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        if info.short_src:find("power.lua", 1, true) then
            local key = "fn@" .. info.linedefined
            if info.linedefined == 976 then
                local ph
                for i = 1, 30 do local n, v = debug.getlocal(level, i); if not n then break end; if n == "phase" then ph = v end end
                key = "Power.step phase=" .. tostring(ph)
            end
            by[key] = (by[key] or 0) + 1
            return
        end
    end
    outside = outside + 1
end
debug.sethook(hook, "", 100)
while not st.done and st.phase ~= stop do
    local b = {ops = 2000}
    repeat local before = b.ops; Search.step(st, b); if b.ops >= before then b.ops = before - 1 end until b.ops <= 0 or st.done or st.phase == stop
end
debug.sethook()
local list = {}; for k, v in pairs(by) do list[#list + 1] = {k, v} end
table.sort(list, function(a, b) return a[2] > b[2] end)
io.write(string.format("total samples=%d (x100 instr) outside power=%d\n", total, outside))
for i = 1, math.min(15, #list) do io.write(string.format("%6.1f%% %s\n", list[i][2] / total * 100, list[i][1])) end
