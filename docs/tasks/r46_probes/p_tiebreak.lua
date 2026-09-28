-- In-memory trial R2 (result may change): equal priority -> deeper node first (larger cost so far).
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local old = "    if left.cost ~= right.cost then return left.cost < right.cost end"
    local a, b = src:find(old, 1, true)
    assert(a, "tiebreak anchor")
    io.stderr:write("PATCH tiebreak live\n")
    return src:sub(1, a - 1) .. "    if left.cost ~= right.cost then return left.cost > right.cost end" .. src:sub(b + 1)
end
