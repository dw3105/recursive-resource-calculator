return function(src)
  local old = [[
            if port.role == "in" then occupant_at(port, x - dx, y - dy)]]
  local new = [[
            if port.role == "in" then
                --A foreign belt behind an input port matters only when it feeds INTO the port tile; a belt that runs
                --past (or an underground beside it) never delivers there (player-inserter-10s-stack1, 2026-09-28).
                local bx, by = x - dx, y - dy
                local feeds = false
                for _, info in ipairs(work.infos) do
                    if transport_kind(info) then
                        local tx, ty = tile_of(info)
                        if tx == math.floor(bx) and ty == math.floor(by) then
                            local fx, fy = Grid.dir_vector(entity_direction(info) or -1)
                            if fx ~= nil and tx + fx == math.floor(x) and ty + fy == math.floor(y) then feeds = true end
                        end
                    end
                end
                local fluid_port = port.kind == "fluid" or port.is_fluid == true or port.fluid_pinned == true
                if feeds or fluid_port then occupant_at(port, bx, by) end]]
  local s, e = src:find(old, 1, true); assert(s, "valD2")
  return src:sub(1, s - 1) .. new .. src:sub(e + 1)
end
