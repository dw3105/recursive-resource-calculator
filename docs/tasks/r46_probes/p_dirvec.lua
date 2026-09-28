-- In-memory trial K2: Grid.dir_vector built 5 tables on EVERY call; the constant table moves out of the function.
return function(name, src)
    if name ~= "logic.bp.grid" then return src end
    local old = "function Grid.dir_vector(dir)\n    local vectors = {\n"
    local a, b = src:find(old, 1, true)
    assert(a, "dir_vector anchor not found")
    local e1, e2 = src:find("\nend\n", b, true)
    local new = "local DIR_VECTORS\nfunction Grid.dir_vector(dir)\n" ..
        "    if DIR_VECTORS == nil then\n" ..
        "        DIR_VECTORS = {[Grid.NORTH] = {x = 0, y = -1}, [Grid.EAST] = {x = 1, y = 0},\n" ..
        "            [Grid.SOUTH] = {x = 0, y = 1}, [Grid.WEST] = {x = -1, y = 0}}\n" ..
        "    end\n" ..
        "    local vector = DIR_VECTORS[normalized_dir(dir)]\n" ..
        "    if vector then return vector.x, vector.y end\n" ..
        "    return nil\nend\n"
    io.stderr:write("PATCH dirvec live\n")
    return src:sub(1, a - 1) .. new .. src:sub(e2 + 1)
end
