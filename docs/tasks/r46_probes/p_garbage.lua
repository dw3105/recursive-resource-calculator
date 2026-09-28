-- Probe: KB of new Lua memory per search step (collector stopped inside the step; full collect every 20000 steps).
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local a, b = src:find("\nlocal function search_step(", 1, true)
    local e1, e2 = src:find("\nend\n", b, true)
    local inject = [[
do
    local raw, kb, n = search_step, 0, 0
    collectgarbage("stop")
    search_step = function(work, search)
        local c0 = collectgarbage("count")
        local o = raw(work, search)
        kb, n = kb + collectgarbage("count") - c0, n + 1
        if n % 20000 == 0 then collectgarbage("collect"); collectgarbage("stop") end
        _G.__garbage = {kb = kb, n = n}
        return o
    end
    local exit = os.exit
    os.exit = function(...) if _G.__garbage then io.stderr:write(string.format("GARBAGE steps=%d kb=%.0f kb_per_step=%.3f\n", _G.__garbage.n, _G.__garbage.kb, _G.__garbage.kb / _G.__garbage.n)) end; return exit(...) end
end
]]
    return src:sub(1, e2) .. inject .. src:sub(e2 + 1)
end
