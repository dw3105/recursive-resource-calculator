-- Replay only the failed demand stored by route_fail_snapshot.lua.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
if #arg ~= 1 then io.stderr:write("usage: lua5.2 tools/route_replay_one.lua <snapshot>\n"); os.exit(2) end
local function load_snapshot(path)
    if path:match("%.gz$") then
        local p = assert(io.popen("gzip -dc " .. string.format("%q", path), "r"))
        local text = p:read("*a"); p:close()
        return assert(load(text, "@" .. path))()
    end
    return assert(loadfile(path))()
end
local record = load_snapshot(arg[1])
local state, index = record.state, record.demand_index
local work, demand = state.work, assert(state.work.demands[index], "snapshot demand missing")
local function transform(source)
    local patch = os.getenv("PATCH")
    if patch then source = assert(assert(loadfile(patch))()(source)) end
    local fail = "local function fail_demand(state, work, demand, code, detail)"
    local failrep = fail .. "\n    if _G.__route_fail_hook then _G.__route_fail_hook(state, work, demand, code, detail) end"
    local append = "local function append_normal_path(work, demand, path, amount)"
    local apprep = append .. "\n    if _G.__route_path_hook then _G.__route_path_hook(work, demand, path, amount) end"
    local function replace(src, literal, rep)
        local pat = literal:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        return src:gsub(pat, function() return rep end, 1)
    end
    local a, na = replace(source, fail, failrep)
    local b, nb = replace(a, append, apprep)
    assert(na == 1 and nb == 1, "route hook point not found")
    return b
end
local src = assert(io.open("logic/bp/route.lua", "r")):read("*a")
local Route = assert(load(transform(src), "@logic/bp/route.lua"))()
local flags = {"curve_allowed", "free_heading", "allow_ride", "no_chain_dive", "strict_branch"}
if os.getenv("RESET_FLAGS") == "1" then for _, k in ipairs(flags) do demand[k] = nil end end
demand.remaining = demand.amount; demand.source_index, demand.sink_index = 1, 1
demand.source, demand.sink = demand.source_candidates and demand.source_candidates[1] or demand.source,
    demand.sink_candidates and demand.sink_candidates[1] or demand.sink
demand.crossing_blocked, demand.crossing_retries, demand.bury_blocked = nil, nil, nil
work.current = nil; state.cursor.demand_index = index; state.done = false; state.ok = nil; state.errors = nil
local path, outcome, failed_code
_G.__route_path_hook = function(w, d, p) if d == demand then path = p end end
_G.__route_fail_hook = function(s, w, d, code)
    if d == demand then failed_code = code; s.done = true end
end
local start = os.clock()
while not state.done and demand.remaining > 1e-9 do Route.step(state, {ops=2000}) end
_G.__route_path_hook, _G.__route_fail_hook = nil, nil
local placed = demand.remaining <= 1e-9 and demand.unroutable == nil
local rejection = work.last_route_rejection or {}
local cells = {}
for i, c in ipairs(path or {}) do
    local x, y = c.x or c[1], c.y or c[2]
    local n = path[i + 1]
    local jump = n and (math.abs(n.x - x) + math.abs(n.y - y)) or 0
    if x ~= nil and y ~= nil then cells[#cells+1] = tostring(x)..","..tostring(y)..(jump > 1 and ("J"..tostring(jump)) or "") end
end
io.write("REPLAY "..(placed and "placed" or "failed").." code="..tostring(failed_code or record.code).." reason="..tostring(rejection.reason).." path="..#cells.." cells t="..string.format("%.3f", os.clock()-start).."s\n")
io.write(table.concat(cells, " ").."\n")
if os.getenv("MAP") == "1" then
    local sx, sy = demand.source and demand.source.x, demand.source and demand.source.y
    local tx, ty = demand.sink and demand.sink.x, demand.sink and demand.sink.y
    local minx, maxx, miny, maxy = math.huge,-math.huge,math.huge,-math.huge
    for _, p in ipairs({{sx,sy},{tx,ty}}) do if p[1] then minx=math.min(minx,p[1]-8);maxx=math.max(maxx,p[1]+8);miny=math.min(miny,p[2]-5);maxy=math.max(maxy,p[2]+5) end end
    for y=miny,maxy do local row={}; for x=minx,maxx do
        local key=tostring(x)..":"..tostring(y); local ch = "."
        if work.obstacles and work.obstacles[key] then ch="#"
        elseif work.port_cells and work.port_cells[key] then ch="p"
        else
            local seg = work.segments_by_cell and work.segments_by_cell[key]
            if seg then ch = (seg.flow_id == demand.flow_id) and "+" or (seg.kind == "pipe" and "=" or "-") end
        end
        if x==sx and y==sy then ch="S" elseif x==tx and y==ty then ch="T" end
        for _, c in ipairs(path or {}) do if (c.x or c[1])==x and (c.y or c[2])==y and ch ~= "S" and ch ~= "T" then ch="*" end end
        row[#row+1]=ch
    end; io.write(table.concat(row).."\n") end
end
