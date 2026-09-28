-- Probe: at the first re-route trial that floods (>= 2000 steps) and finds no path, print the sink's neighbourhood and stop.
_G.__probe = function(work, st, static_owner, key)
    local d, t = st.demand, st.trial
    local o = t.option
    io.write(string.format("FLOOD steps=%d flow=%s kind=%s src=%d,%d dir=%s sink=%d,%d travel_dir=%s perimeter=%s row_port=%s feed_curve=%s rear_curve=%s hop=%s\n",
        t.steps, tostring(d.flow_id), tostring(d.kind), d.source.x, d.source.y, tostring(d.source.travel_dir), d.sink.x, d.sink.y,
        tostring(d.sink.travel_dir), tostring(d.sink.perimeter), tostring(d.sink.row_port), tostring(d.sink.feed_curve), tostring(d.sink.rear_curve),
        o and o.hop and (o.hop.port_x .. "," .. o.hop.port_y .. " hand " .. o.hop.hand_x .. "," .. o.hop.hand_y .. " turns " .. tostring(o.hop.turns)) or "-"))
    io.write(string.format("saw_blocked=%s saw_capacity=%s saw_fluid_mix=%s closed=%d\n", tostring(t.search.saw_blocked), tostring(t.search.saw_capacity),
        tostring(t.search.saw_fluid_mix), (function() local n = 0; for _ in pairs(t.search.closed) do n = n + 1 end; return n end)()))
    for y = d.sink.y - 4, d.sink.y + 4 do
        local row = {}
        for x = d.sink.x - 4, d.sink.x + 6 do
            local k = key(x, y)
            local seg, own, res = work.segments_by_cell[k], static_owner(work, x, y), work.port_cells[k]
            local c = "."
            if x == d.sink.x and y == d.sink.y then c = "T" elseif x == d.source.x and y == d.source.y then c = "S" end
            if seg then c = c .. (seg.kind == "pipe" and "p" or "b") .. tostring(seg.direction or "?") .. (seg.underground and "u" or "") .. (seg.splitter and "s" or "")
            elseif own ~= nil then c = c .. "#" end
            if res then c = c .. "r" end
            if x < 0 or y < 0 then c = "x" end
            row[#row + 1] = string.format("%-7s", c)
        end
        io.write(string.format("y=%3d ", y) .. table.concat(row) .. "\n")
    end
    for _, dd in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
        local x, y = d.sink.x + dd[1], d.sink.y + dd[2]
        local res = work.port_cells[key(x, y)]
        local names = {}
        for k2, v2 in pairs(res or {}) do names[#names + 1] = tostring(k2) .. "=" .. tostring(v2) end
        table.sort(names)
        io.write(string.format("cell %d,%d owner=%s reserved={%s}\n", x, y, tostring(static_owner(work, x, y)), table.concat(names, "; ")))
    end
    closed_cells = {}
    local n = 0
    for k2 in pairs(t.search.closed) do local xy = k2:match("^([^:]+:[^:]+):"); if not closed_cells[xy] then closed_cells[xy] = true; n = n + 1 end end
    io.write("distinct cells closed=" .. n .. " grid=" .. tostring(work.grid and work.grid.w) .. "x" .. tostring(work.grid and work.grid.h) .. "\n")
    io.flush()
    os.exit(0)
end
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local n = 0
    src = src:gsub("local weight = trial_finish%(work, st%.trial, st%.demand%)\n", function(h)
        n = n + 1
        if n > 1 then return h end
        return h .. "            if st.trial.steps >= 2000 and not st.trial.path then _G.__probe(work, st, static_owner, coordinate_key) end\n"
    end)
    return src
end
