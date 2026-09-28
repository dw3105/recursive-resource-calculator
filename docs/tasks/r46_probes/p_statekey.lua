-- In-memory trial K3: a search state key is a number, never a built string (kind is constant inside one search).
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local a = src:find("\nlocal function state_key(x, y, arrival_direction, kind, underground_mode)\n", 1, true)
    assert(a, "state_key anchor not found")
    local e1, e2 = src:find("\nend\n", a + 1, true)
    local new = "\nlocal function state_key(x, y, arrival_direction, kind, underground_mode)\n" ..
        "    return (((y + 8) * 4096 + (x + 8)) * 32 + (arrival_direction or 0)) * 8 + (underground_mode or 0)\nend\n"
    io.stderr:write("PATCH statekey live\n")
    return src:sub(1, a - 1) .. new .. src:sub(e2 + 1)
end
