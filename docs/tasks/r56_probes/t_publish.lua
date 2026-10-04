-- t_publish.lua (cwd = ~/wt-rrc-speed06): lua5.2 timing of generation.lua publish-tick costs on a sized result.
-- usage: lua5.2 t_publish.lua <result.json from ckpt --output> <prepared_input.json (capture)> <scale>
-- scale = entities multiplier to reach a target size (entity list and canonical text replicated).
local function lines(path, a, b)
    local out, n = {}, 0
    for l in io.lines(path) do n = n + 1; if n >= a and n <= b then out[#out + 1] = l end end
    return table.concat(out, "\n")
end
local gen = "logic/bp/generation.lua"
local reader_src = lines("tests/golden/generate.lua", 16, 169) .. "\nreturn json_reader"
local json_reader = assert(load(reader_src, "@generate.lua"))()
local src = lines(gen, 25, 48) .. "\n" .. lines(gen, 963, 1057) .. "\nreturn copy_plain, sha256"
local copy_plain, sha256 = assert(load(src, "@generation.lua"))()
local function read(p) local f = assert(io.open(p)); local s = f:read("*a"); f:close(); return s end
local function decode(text) local r = json_reader(text); return r.value and r or r end
local res_text, cap_text, scale = read(arg[1]), read(arg[2]), tonumber(arg[3] or 1)
local function parse(t)
    local ok, v = pcall(function() local r = json_reader(t); return r end)
    assert(ok, v); return v
end
local result_doc = parse(res_text)
local capture = parse(cap_text)
if type(result_doc) == "function" then error("reader returned function") end
local blueprint = result_doc.result or result_doc
local canonical_json = result_doc.canonical_json
assert(type(canonical_json) == "string", "no canonical_json")
-- scale: replicate entity list and canonical text
if scale > 1 then
    local ents = blueprint.entities or (blueprint.blueprint and blueprint.blueprint.entities)
    if ents then local n = #ents; for i = n + 1, math.floor(n * scale) do ents[i] = ents[(i - 1) % n + 1] end end
    local parts = {}; local whole = math.floor(scale); for _ = 1, whole do parts[#parts + 1] = canonical_json end
    parts[#parts + 1] = canonical_json:sub(1, math.floor(#canonical_json * (scale - whole)))
    canonical_json = table.concat(parts)
end
local function t(label, n, fn)
    collectgarbage(); collectgarbage()
    local best = math.huge
    for _ = 1, n do local c = os.clock(); fn(); local d = os.clock() - c; if d < best then best = d end end
    io.write(string.format("%-34s %8.1f ms (min of %d)\n", label, best * 1000, n))
    return best
end
local ents = blueprint.entities or (blueprint.blueprint and blueprint.blueprint.entities) or {}
io.write(string.format("entities=%d canonical_json=%d bytes capture_json=%d bytes bit32=%s\n", #ents, #canonical_json, #cap_text, tostring(bit32 ~= nil)))
local s = t("sha256(canonical_json)", 3, function() return sha256(canonical_json) end)
local cc = t("copy_plain(capture)", 5, function() return copy_plain(capture) end)
local cr = t("copy_plain(result)", 5, function() return copy_plain(blueprint) end)
-- persist_handle today: fields copied into record (capture, result, canonical, interim.result) then the whole record again
local handle = {capture = capture, result = blueprint, canonical = blueprint, interim = {result = blueprint}}
local p2 = t("persist_handle body today (x2 copy)", 3, function()
    local record = {capture = copy_plain(handle.capture), result = copy_plain(handle.result),
        canonical = copy_plain(handle.canonical), interim = copy_plain(handle.interim)}
    return copy_plain(record)
end)
local p1 = t("persist_handle body copy once", 3, function()
    return {capture = copy_plain(handle.capture), result = copy_plain(handle.result),
        canonical = copy_plain(handle.canonical), interim = copy_plain(handle.interim)}
end)
io.write(string.format("PUBLISH-EST today sha+3 persist = %.0f ms; sha only on test + copy once = %.0f ms; saved %.0f ms\n",
    (s + 3 * p2) * 1000, 3 * p1 * 1000, (s + 3 * p2 - 3 * p1) * 1000))
