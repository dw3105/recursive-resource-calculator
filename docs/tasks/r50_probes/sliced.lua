local format, concat, sort = string.format, table.concat, table.sort
local function prefixed(v) return #v .. ":" .. v end
local encode_value
local function assemble(key_codes, by_code)
    sort(key_codes)
    local out, n = {"t", prefixed(tostring(#key_codes))}, 2
    for i = 1, #key_codes do
        local k = key_codes[i]; local v = by_code[k]
        out[n + 1] = #k .. ":" .. k; out[n + 2] = #v .. ":" .. v; n = n + 2
    end
    return concat(out)
end
encode_value = function(value, active)
    local t = type(value)
    if t == "string" then return "s" .. prefixed(value)
    elseif t == "table" then
        active[value] = true
        local codes, by = {}, {}
        for k, c in pairs(value) do local kc = encode_value(k, active); codes[#codes + 1] = kc; by[kc] = encode_value(c, active) end
        active[value] = nil
        return assemble(codes, by)
    elseif value == nil then return "n"
    elseif t == "boolean" then return value and "b1:1" or "b1:0"
    elseif t == "number" then return "d" .. prefixed(format("%.17g", value)) end
end
-- sliced: entries encoded one per op, then assembled
local snap = dofile(arg[1])
local sel = snap.selection
local t0 = os.clock()
local codes, by = {}, {}
for i, entry in ipairs(sel) do
    local kc = encode_value(i, {}); codes[#codes + 1] = kc; by[kc] = encode_value(entry, {})
end
for _, key in ipairs({"burners", "quality_loops"}) do
    local kc = encode_value(key, {}); codes[#codes + 1] = kc; by[kc] = encode_value(sel[key], {})
end
local sel_code = assemble(codes, by)
local top_codes, top_by = {}, {}
for key, value in pairs({targets = snap.targets or {}, options = snap.options or {}}) do
    local kc = encode_value(key, {}); top_codes[#top_codes + 1] = kc; top_by[kc] = encode_value(value, {})
end
local kc = encode_value("selection", {}); top_codes[#top_codes + 1] = kc; top_by[kc] = sel_code
local fp = "rrc-snapshot-1:" .. assemble(top_codes, top_by)
print(string.format("sliced total %.1f ms, per entry %.3f ms", (os.clock() - t0) * 1000, (os.clock() - t0) * 1000 / #sel))
local f = io.open(arg[2], "w") f:write(fp) f:close()
