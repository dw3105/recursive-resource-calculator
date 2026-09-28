-- In-memory trial R1 (exact by argument): a failed flood is replayed in another direction order ONLY when a
-- path-dependent refusal fired in it (own-path revisit, ring check). Without one, the reachable state set does not
-- depend on expansion order, so the replay must fail the same way.
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local n
    src, n = src:gsub("            if point and point%.x == x and point%.y == y then return false end\n",
        "            if point and point.x == x and point.y == y then search.path_dep = true; return false end\n", 1)
    assert(n == 1, "noreplay2 anchor 1")
    local a, b = src:find("\nlocal function downstream_reaches_root(work, search, from_key, x, y)\n", 1, true)
    assert(a, "noreplay2 anchor 2")
    local e1, e2 = src:find("\nend\n", b, true)
    src = src:sub(1, e2) .. "do local raw = downstream_reaches_root; downstream_reaches_root = function(work, search, ...) " ..
        "local r = raw(work, search, ...); if r then search.path_dep = true end; return r end end\n" .. src:sub(e2 + 1)
    local old = "and search.order_index < #DIRECTION_ORDERS then"
    a, b = src:find(old, 1, true)
    assert(a, "noreplay2 anchor 3")
    src = src:sub(1, a - 1) .. "and search.order_index < #DIRECTION_ORDERS and (function() " ..
        "if _G.__P then _G.__P.count(search.path_dep and 'replay_kept_path_dependent' or 'replay_skipped_order_free') end; " ..
        "return search.path_dep == true end)() then" .. src:sub(b + 1)
    io.stderr:write("PATCH noreplay2 live\n")
    return src
end
