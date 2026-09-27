-- Capture the whole reachable routing state at the first requested fail_demand call.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
if #arg ~= 3 then io.stderr:write("usage: lua5.2 tools/route_fail_snapshot.lua <route_input.json> <N|0=every failure> <out>\n"); os.exit(2) end
local input_path, wanted, output = arg[1], assert(tonumber(arg[2])), arg[3]
local function transformed(source)
    local patch = os.getenv("PATCH")
    if patch then local fn = assert(loadfile(patch))(); source = assert(fn(source)) end
    local needle = "local function fail_demand(state, work, demand, code, detail)"
    local replacement = needle .. "\n    if _G.__route_fail_hook then _G.__route_fail_hook(state, work, demand, code, detail) end"
    local pattern = needle:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local result, n = source:gsub(pattern, function() return replacement end, 1)
    assert(n == 1, "fail_demand hook point not found")
    return result
end
local source = assert(io.open("logic/bp/route.lua", "r")):read("*a")
local route_chunk = assert(load(transformed(source), "@logic/bp/route.lua"))
local Route = route_chunk()
H.new_world("2.0")
local f = assert(io.open(input_path, "r")); local input = assert(helpers.json_to_table(f:read("*a"))); f:close()
local function scalar(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "number" then return tostring(v) end
    if type(v) == "boolean" then return tostring(v) end
    if v == nil then return "nil" end
end
local function save_graph(state, index, code)
    local ids, nodes, omitted = {}, {}, {}
    local function ref(v)
        if type(v) ~= "table" then return scalar(v) end
        if ids[v] then return "T[" .. ids[v] .. "]" end
        local id = #nodes + 1; ids[v] = id; nodes[id] = v
        return "T[" .. id .. "]"
    end
    ref(state)
    local serialized = {}
    for id, node in ipairs(nodes) do
        local entries = {}
        for k, v in pairs(node) do
            local kt = type(k); local vt = type(v)
            if (kt == "string" or kt == "number" or kt == "boolean") and (vt == "table" or scalar(v) ~= nil) then
                entries[#entries+1] = "[" .. ref(k) .. "]=" .. ref(v)
            else omitted[#omitted+1] = "node=" .. id .. " key=" .. tostring(k) .. " key_type=" .. kt .. " value_type=" .. vt end
        end
        serialized[id] = entries
    end
    local out = assert(io.open(output, "w"))
    out:write("local T={}\n")
    for i=1,#nodes do out:write("T["..i.."]={}\n") end
    for i=1,#nodes do for _, entry in ipairs(serialized[i]) do out:write("T["..i.."]["..entry:match("^%[(.-)%]=").."]="..entry:match("=(.*)$").."\n") end end
    out:write("return {state=T[1],demand_index=" .. tostring(index) .. ",code=" .. string.format("%q", code) .. "}\n")
    out:close()
    for _, line in ipairs(omitted) do io.stderr:write("SNAPSHOT_SKIPPED " .. line .. "\n") end
    return #nodes
end
local nfail, stopped = 0, false
_G.__route_fail_hook = function(state, work, demand, code)
    nfail = nfail + 1
    if wanted == 0 then
        --N=0: save every failure to <out>.<k> and keep routing (env LIMIT caps CPU seconds), so one run collects
        --the whole tail of a sheet whose failures each restart every demand.
        local i = 0; for j, d in ipairs(work.demands) do if d == demand then i = j; break end end
        local keep = output
        output = keep .. "." .. nfail
        save_graph(state, i, code)
        io.write("SNAPSHOT "..output.." demand="..i.." flow="..tostring(demand.flow_id).." code="..code.." sink="..tostring(demand.sink and demand.sink.port_id).." t="..string.format("%.3f", os.clock()-started).."s\n")
        io.stdout:flush()
        output = keep
    elseif nfail == wanted then
        local i = 0; for j, d in ipairs(work.demands) do if d == demand then i = j; break end end
        local nodes = save_graph(state, i, code)
        io.write("SNAPSHOT "..output.." demand="..i.." flow="..tostring(demand.flow_id).." code="..code.." sink="..tostring(demand.sink and demand.sink.port_id).." t="..string.format("%.3f", os.clock()-started).."s\n")
        stopped = true
    end
end
started = os.clock()
local state = Route.begin(input)
local limit = tonumber(os.getenv("LIMIT") or "")
while not state.done and not stopped and not (limit and os.clock() - started > limit) do Route.step(state, {ops=2000}) end
if wanted == 0 then io.write("ROUTE done=" .. tostring(state.done) .. " ok=" .. tostring(state.ok) .. " failures=" .. nfail .. " t=" .. string.format("%.1f", os.clock() - started) .. "s\n"); os.exit(0) end
_G.__route_fail_hook = nil
if not stopped then io.stderr:write("route ended before failure "..wanted.."\n"); os.exit(1) end
