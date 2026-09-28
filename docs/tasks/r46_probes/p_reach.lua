-- In-memory trial T3: all_bindings_reach_sinks walks each (source, flow) chain ONCE and tests every sink of that
-- source against the reached tiles, instead of one walk per binding.
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local a = src:find("\nlocal function all_bindings_reach_sinks(work)\n", 1, true)
    assert(a, "reach anchor not found")
    local e1, e2 = src:find("\nend\n", a + 1, true)
    local new = [[

local function all_bindings_reach_sinks(work)
    local reached_by = {}
    for _, binding in ipairs(work.bindings or {}) do
        local source = work.endpoint_by_id and work.endpoint_by_id[binding.source_port_id]
        local sink = work.endpoint_by_id and work.endpoint_by_id[binding.sink_port_id]
        if not source or not sink then return false end
        local memo_key = coordinate_key(source.x, source.y) .. "|" .. tostring(binding.flow_id)
        local reached = reached_by[memo_key]
        if reached == nil then
            reached = {}
            local _, tiles = route_chain_walk(work, source, nil, binding.flow_id)
            for _, key in ipairs(tiles) do reached[key] = true end
            reached_by[memo_key] = reached
        end
        if not reached[coordinate_key(sink.x, sink.y)] then return false end
    end
    return true
end
]]
    io.stderr:write("PATCH reach live\n")
    return src:sub(1, a - 1) .. new .. src:sub(e2 + 1)
end
