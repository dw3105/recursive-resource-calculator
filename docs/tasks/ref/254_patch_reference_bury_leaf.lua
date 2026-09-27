return function(src)
  local n
  src, n = src:gsub([[
    work.segments = kept
    return pairs_laid
end]], function() return [[
    work.segments = kept
    if work.demands then
        local ends = {}
        local function mark(e) if e and e.x and e.y then ends[key(e.x, e.y)] = true end end
        for _, e in pairs(work.endpoint_by_id or {}) do mark(e) end
        for _, d in ipairs(work.demands) do mark(d.source); mark(d.sink) end
        local function opens(seg, sk, x, y)
            if not seg.underground then return true end
            local dx, dy = Grid.dir_vector(seg.direction)
            if not dx then return false end
            if sk == seg.underground_entry_key then
                local ex, ey = h.coordinate_from_key(sk); return ex - dx == x and ey - dy == y
            end
            local ex, ey = h.coordinate_from_key(sk); return ex + dx == x and ey + dy == y
        end
        local dropped = true
        while dropped do
            dropped = false
            for cell_key, seg in pairs(by_cell) do
                if seg.kind == "pipe" and not seg.underground and not seg._route_removed and not ends[cell_key]
                    and not (work.port_cells and work.port_cells[cell_key]) then
                    local x, y = h.coordinate_from_key(cell_key)
                    local links = 0
                    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                        local nk = key(x + d[1], y + d[2])
                        local o = by_cell[nk]
                        if o and o.kind == "pipe" and not o._route_removed and flow_of(o) == flow_of(seg) and opens(o, nk, x, y) then links = links + 1 end
                    end
                    if links <= 1 then
                        seg._route_removed = true
                        local ent = entity_by_segment[seg.segment_id]
                        if ent then ent._route_removed = true end
                        by_cell[cell_key] = nil
                        dropped = true
                    end
                end
            end
        end
        local k2 = {}
        for _, s in ipairs(work.segments) do if not s._route_removed then k2[#k2 + 1] = s end end
        work.segments = k2
        local e2 = {}
        for _, e in ipairs(work.entities or {}) do if not e._route_removed then e2[#e2 + 1] = e end end
        work.entities = e2
    end
    return pairs_laid
end]] end, 1)
  assert(n == 1, "bury_leaf")
  return src
end
