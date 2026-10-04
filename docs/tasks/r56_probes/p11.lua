--LOCAL PROBE (wayfinder speed ticket 11, 2026-10-03), never committed: event digests that run the same in lua5.2
--and in the Factorio engine, to find the first point where blue-science-10s game and offline runs part.
local P = {n = 0, tick = 0, trace = true}
local out = rawget(_G, "log") or print
local function num(v) if v == math.floor(v) then return string.format("%d", v) end return string.format("%.10g", v) end
local function ser(v, depth)
    local t = type(v)
    if t == "number" then return num(v) elseif t == "string" then return v elseif t ~= "table" then return tostring(v) end
    if depth > 4 then return "{.}" end
    local keys = {}
    for k in pairs(v) do if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) if type(a) ~= type(b) then return type(a) < type(b) end return a < b end)
    local parts = {}
    for _, k in ipairs(keys) do local x = v[k]; if type(x) ~= "function" then parts[#parts + 1] = tostring(k) .. "=" .. ser(x, depth + 1) end end
    return "{" .. table.concat(parts, ",") .. "}"
end
P.ser = ser
local function hash(s)
    local h = 0
    for i = 1, #s, 4 do local a, b, c, d = s:byte(i, i + 3); h = (h * 1031 + a + (b or 0) * 7 + (c or 0) * 61 + (d or 0) * 251) % 2147483647 end
    return string.format("%08x", h)
end
P.hash = hash
function P.list(tag, list, dump)
    local lines = {}
    for i, e in ipairs(list or {}) do lines[i] = ser(e, 1) end
    local s = table.concat(lines, "\n")
    P.emit(tag .. " n=" .. #lines .. " h=" .. hash(s))
    if dump then for i, l in ipairs(lines) do P.emit(tag .. "#" .. i .. " " .. l) end end
end
function P.emit(msg)
    P.n = P.n + 1
    out("P11 " .. P.n .. " t=" .. P.tick .. " " .. msg)
end
_G.__p11 = P
return P
