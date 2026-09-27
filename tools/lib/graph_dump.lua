-- Data graph serializer used by offline snapshots. Tables, sharing, and cycles are kept.
local M = {}
local function number(v)
    if v == math.huge then return "math.huge" end
    if v == -math.huge then return "-math.huge" end
    if v ~= v then return "(0/0)" end
    if v == math.floor(v) and math.abs(v) < 9007199254740992 then return string.format("%.0f", v) end
    return string.format("%.17g", v)
end
local function scalar(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then return number(v) end
    if t == "boolean" then return tostring(v) end
    if v == nil then return "nil" end
end
function M.dump(value, path)
    local ids, nodes, omitted = {}, {}, {}
    local function ref(v)
        if type(v) ~= "table" then return scalar(v) end
        if ids[v] then return "T[" .. ids[v] .. "]" end
        local id = #nodes + 1; ids[v] = id; nodes[id] = v
        return "T[" .. id .. "]"
    end
    ref(value)
    local entries = {}
    for i, node in ipairs(nodes) do
        entries[i] = {}
        for k, v in pairs(node) do
            if (type(k) == "string" or type(k) == "number" or type(k) == "boolean") and (type(v) == "table" or scalar(v) ~= nil) then
                entries[i][#entries[i]+1] = "[" .. ref(k) .. "]=" .. ref(v)
            else omitted[#omitted+1] = "node="..i.." key_type="..type(k).." value_type="..type(v) end
        end
    end
    local target = path:match("%.gz$") and (path .. ".plain") or path
    local out = assert(io.open(target, "w")); out:write("local T={}\n")
    for i=1,#nodes do out:write("T["..i.."]={}\n") end
    for i=1,#nodes do for _, e in ipairs(entries[i]) do out:write("T["..i.."]"..e.."\n") end end
    out:write("return " .. ref(value) .. "\n"); out:close()
    if target ~= path then
        local ok = os.execute("gzip -c " .. string.format("%q", target) .. " > " .. string.format("%q", path))
        assert(ok == true or ok == 0, "gzip failed"); os.remove(target)
    end
    for _, s in ipairs(omitted) do io.stderr:write("SNAPSHOT_SKIPPED "..s.."\n") end
    return #nodes
end
function M.load(path)
    local source
    if path:match("%.gz$") then
        local p = assert(io.popen("gzip -dc " .. string.format("%q", path), "r")); source = p:read("*a"); assert(p:close())
    else local f=assert(io.open(path,"r")); source=f:read("*a"); f:close() end
    return assert(load(source, "@"..path))()
end
return M
