return function(src)
  local old = [[
    place_side(inputs, "in", "top", SOUTH, SOUTH, 0)
    place_side(outputs, "out", "left", EAST, Grid.WEST, 0)
end]]
  local new = [[
    place_side(inputs, "in", "top", SOUTH, SOUTH, 0)
    place_side(outputs, "out", "left", EAST, Grid.WEST, 0)
    local by_tile = {}
    local function flow_key(p) return tostring(p.flow_id or (p.flow_ids and table.concat(p.flow_ids, "+"))) end
    for _, p in ipairs(block.ports) do
        if p.attach_dx ~= nil then
            local k = p.attach_dx .. ":" .. p.attach_dy
            by_tile[k] = by_tile[k] or {}
            by_tile[k][#by_tile[k] + 1] = p
        end
    end
    for _, p in ipairs(block.ports) do
        if p.kind ~= "fluid" and not p.fluid_pinned and p.attach_dx ~= nil and p.travel_dir ~= nil and p.inserter_id ~= nil then
            local dx, dy = Grid.dir_vector(p.travel_dir)
            if dx then
                local sign = p.role == "out" and 1 or -1
                local clash = false
                for _, q in ipairs(by_tile[(p.attach_dx + sign * dx) .. ":" .. (p.attach_dy + sign * dy)] or {}) do
                    if flow_key(q) ~= flow_key(p) then clash = true end
                end
                if clash then
                    for _, hand in ipairs(block.inserters or {}) do
                        if hand.id == p.inserter_id and hand.x ~= nil then
                            local out = Grid.dir_from_vector(p.attach_dx - math.floor(hand.x), p.attach_dy - math.floor(hand.y))
                            if out then p.travel_dir = p.role == "out" and out or Grid.dir_opposite(out) end
                            break
                        end
                    end
                end
            end
        end
    end
end]]
  local s, e = src:find(old, 1, true); assert(s, "D")
  return src:sub(1, s - 1) .. new .. src:sub(e + 1)
end
