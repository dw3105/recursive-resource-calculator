-- F3 fix: end_feed_bleeds (logic/bp/route.lua) second loop.
-- (a) a placed row run's segment carries flow_ids only (flow_id nil), so `other.flow_id ~= nil` skipped it and a
--     foreign underground entrance was laid in front of the plastic-bar row end (72,58)->(72,57).
-- (b) a same-flow older end pointing into a new path cell closes a ring when that end is downstream of the path
--     (tidy trial put the adv-circuit exit at (93,96) in front of its own row end (93,95)).
local OLD = [[
                if other and other ~= mine and other.kind == "belt" and other.direction == d and not other.splitter
                    and other.flow_id ~= nil and not segment_has_flow(mine, other.flow_id)
                    and (not other.underground or ok_key == other.underground_exit_key)
                    and mine.direction ~= Grid.dir_opposite(d)
                    and end_cannot_turn(work, ox, oy, d, other.flow_id, other) then
                    return true
                end]]
local NEW = [[
                local other_flow = other and other.flow_id
                if other and other_flow == nil and other.flow_ids then
                    local ids = {}
                    for id, on in pairs(other.flow_ids) do if on and not segment_has_flow(mine, id) then ids[#ids + 1] = id end end
                    table.sort(ids); other_flow = ids[1]
                    if other_flow == nil then for id, on in pairs(other.flow_ids) do if on then other_flow = id; break end end end
                end
                if other and other ~= mine and other.kind == "belt" and other.direction == d and not other.splitter
                    and other_flow ~= nil
                    and (not other.underground or ok_key == other.underground_exit_key)
                    and mine.direction ~= Grid.dir_opposite(d) then
                    if not segment_has_flow(mine, other_flow) then
                        if end_cannot_turn(work, ox, oy, d, other_flow, other) then return true end
                    elseif segment_has_flow(other, demand.flow_id) then
                        if ring_tiles == nil then
                            local last = path[#path]
                            local _, tiles = route_chain_walk(work, {x = last.x, y = last.y}, nil, demand.flow_id)
                            ring_tiles = {}
                            for _, t in ipairs(tiles) do ring_tiles[t] = true end
                        end
                        if ring_tiles[ok_key] then io.write("F3 RING refused ", tostring(demand.flow_id), " at ", ok_key, "\n"); return true end
                    end
                end]]
return function(name, src)
  if name ~= "logic.bp.route" then return src end
  local a, b = src:find(OLD, 1, true); assert(a, "F3 old block missing")
  src = src:sub(1, a - 1) .. NEW .. src:sub(b + 1)
  local h = "    for _, cell in ipairs(path) do\n        local k = coordinate_key(cell.x, cell.y)\n        local mine = work.segments_by_cell[k]"
  local c, e = src:find(h, 1, true); assert(c, "F3 loop head missing")
  src = src:sub(1, c - 1) .. "    local ring_tiles\n" .. src:sub(c)
  io.write("F3 PATCH live\n")
  return src
end
