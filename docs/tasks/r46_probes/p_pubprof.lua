-- Probe: line-level time inside result_for(work, true) (publish), one call per tidy.
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local a, b = src:find("\nlocal function result_for(work, publish)\n", 1, true)
    assert(a, "pubprof anchor")
    local e1, e2 = src:find("\nend\n", b, true)
    local inject = [[
do
    local raw = result_for
    result_for = function(work, publish)
        if not publish then return raw(work, publish) end
        local clock, per, last_line, last_t = os.clock, {}, nil, os.clock()
        debug.sethook(function(_, line)
            local info = debug.getinfo(2, "S")
            local now = clock()
            if last_line then per[last_line] = (per[last_line] or 0) + now - last_t end
            last_line, last_t = (info.short_src or "?") .. ":" .. line, now
        end, "l")
        local t0 = clock()
        local r = raw(work, publish)
        debug.sethook()
        local rows = {}
        for k, v in pairs(per) do rows[#rows + 1] = {k, v} end
        table.sort(rows, function(x, y) return x[2] > y[2] end)
        local out = assert(io.open(os.getenv("PUBPROF_OUT"), "w"))
        out:write(string.format("result_for publish total %.3f s (hooked)\n", clock() - t0))
        for i = 1, math.min(25, #rows) do out:write(string.format("%8.3f %s\n", rows[i][2], rows[i][1])) end
        out:close()
        return r
    end
end
]]
    return src:sub(1, e2) .. inject .. src:sub(e2 + 1)
end
