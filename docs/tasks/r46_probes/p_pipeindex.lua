-- In-memory trial P1: PipeRuns.prune_redundant opens_to() scanned EVERY entity per neighbour test; an index by
-- segment id + tile is built once (first live candidate in entity order wins, as before).
return function(name, src)
    if name ~= "logic.bp.pipe_runs" then return src end
    local old = [[
        local entity = nil
        for _, candidate in ipairs(work.entities or {}) do
            if candidate.segment_id == segment.segment_id and not candidate._route_removed
                and math.floor(candidate.position.x) == x and math.floor(candidate.position.y) == y then
                entity = candidate
                break
            end
        end
]]
    local a, b = src:find(old, 1, true)
    assert(a, "pipeindex anchor")
    local new = [[
        local entity = nil
        if not work._pipe_entity_index or work._pipe_entity_index_n ~= #(work.entities or {}) then
            local index = {}
            for _, candidate in ipairs(work.entities or {}) do
                if candidate.segment_id ~= nil and candidate.position then
                    local k = tostring(candidate.segment_id) .. "@" .. math.floor(candidate.position.x) .. ":" .. math.floor(candidate.position.y)
                    index[k] = index[k] or {}
                    index[k][#index[k] + 1] = candidate
                end
            end
            work._pipe_entity_index, work._pipe_entity_index_n = index, #(work.entities or {})
        end
        for _, candidate in ipairs(work._pipe_entity_index[tostring(segment.segment_id) .. "@" .. x .. ":" .. y] or {}) do
            if not candidate._route_removed then entity = candidate; break end
        end
]]
    io.stderr:write("PATCH pipeindex live\n")
    return src:sub(1, a - 1) .. new .. src:sub(b + 1)
end
