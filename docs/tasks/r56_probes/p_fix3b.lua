-- ticket 19 FIX3b probe: no tidy keep change; at cleanup, after untangle_splitter_chains (route.lua:4391), remove plain
-- route belts with a flow whose output tile holds no segment and no endpoint, repeated until none (dead-end stubs).
-- Chained on p_fix2.lua (FIX1+FIX2). Uses p19_dead_end-style test inline.
local base = dofile(os.getenv("HOME") .. "/.claude/plans/wayfinder-rrc-speed/research/19-probe/p_fix2.lua")
io.write("P19-FIX3B-PATCH live\n")
_G.__p19_trim = function(work, ck, from_key, Grid)
    local ends = {}
    for _, dm in ipairs(work.demands or {}) do for _, e in ipairs({dm.sink, dm.source}) do if e and e.x then ends[ck(e.x, e.y)] = true end end end
    for _, ep in pairs(work.endpoint_by_id or {}) do if type(ep) == "table" and ep.x then ends[ck(ep.x, ep.y)] = true end end
    local removed, again = 0, true
    while again do
        again = false
        for key, seg in pairs(work.segments_by_cell or {}) do
            if seg.kind == "belt" and seg.flow_id ~= nil and not seg.underground and not seg.splitter and seg.direction ~= nil and not ends[key] then
                local x, y = from_key(key); local dx, dy = Grid.dir_vector(seg.direction)
                if dx and not work.segments_by_cell[ck(x + dx, y + dy)] then
                    local cells = 0
                    for _, s in pairs(work.segments_by_cell) do if s == seg then cells = cells + 1 end end
                    if cells == 1 then
                        local ent = work.entity_by_segment[seg.segment_id]
                        if ent then ent._route_removed = true; for i = #work.entities, 1, -1 do if work.entities[i] == ent then table.remove(work.entities, i) end end end
                        work.entity_by_segment[seg.segment_id] = nil
                        work.segments_by_cell[key] = nil
                        for i = #work.segments, 1, -1 do if work.segments[i] == seg then table.remove(work.segments, i) end end
                        removed = removed + 1; again = true
                        io.write("P19-TRIM ", key, " flow=", tostring(seg.flow_id), "\n")
                        break
                    end
                end
            end
        end
    end
    return removed
end
return function(name, src)
    src = base(name, src)
    if name ~= "logic.bp.route" then return src end
    local n
    src, n = src:gsub("prune_dead_route_segments = function%(work%)\n    untangle_splitter_chains%(work%)", function()
        return "prune_dead_route_segments = function(work)\n    untangle_splitter_chains(work); _G.__p19_trim(work, coordinate_key, coordinate_from_key, Grid)" end)
    assert(n == 1, "trim site " .. n)
    return src
end
