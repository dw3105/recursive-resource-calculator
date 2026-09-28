-- In-memory trial K1: coordinate_key returns an interned string from a 2-level cache instead of building it.
-- Same strings, so every map and every output byte stays as is.
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local old = 'local function coordinate_key(x, y)\n    return tostring(x) .. ":" .. tostring(y)\nend\n'
    local a, b = src:find(old, 1, true)
    assert(a, "coordinate_key not found")
    local new = 'local KEY_CACHE = {}\n' ..
        'local function coordinate_key(x, y)\n' ..
        '    local row = KEY_CACHE[x]\n' ..
        '    if row == nil then row = {}; KEY_CACHE[x] = row end\n' ..
        '    local key = row[y]\n' ..
        '    if key == nil then key = tostring(x) .. ":" .. tostring(y); row[y] = key end\n' ..
        '    return key\n' ..
        'end\n'
    io.stderr:write("PATCH keycache live\n")
    return src:sub(1, a - 1) .. new .. src:sub(b + 1)
end
