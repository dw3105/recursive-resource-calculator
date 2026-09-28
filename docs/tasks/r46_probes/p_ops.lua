-- In-memory trial W1: one search step is charged OPS_STEP ops (env, default 4) instead of 10. Slicing only.
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local old = "local EXPANSION_OPS = 10"
    local a, b = src:find(old, 1, true)
    assert(a, "ops anchor")
    io.stderr:write("PATCH ops live\n")
    return src:sub(1, a - 1) .. "local EXPANSION_OPS = " .. (os.getenv("OPS_STEP") or "4") .. src:sub(b + 1)
end
