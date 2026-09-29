-- F2 fix: a row-port (belt run head) or perimeter sink is fed only by a belt FACING the port's travel_dir.
-- A laid same-flow run that crosses the sink tile in another heading and carries on (underground, splitter,
-- or a same-flow belt ahead) can never feed the run head: refuse that seed instead of pricing it.
return function(name, src)
  if name ~= "logic.bp.route" then return src end
  local old = [[                if x == demand.sink.x and y == demand.sink.y
                    and demand.sink.travel_dir ~= nil and heading ~= demand.sink.travel_dir then]]
  local new = [[                local passes_through = false
                if x == demand.sink.x and y == demand.sink.y and demand.sink.travel_dir ~= nil
                    and heading ~= demand.sink.travel_dir and (demand.sink.row_port or demand.sink.perimeter) then
                    if segment.underground or segment.splitter then passes_through = true
                    else
                        local hx, hy = Grid.dir_vector(heading)
                        local ahead = hx and work.segments_by_cell[coordinate_key(x + hx, y + hy)]
                        passes_through = ahead ~= nil and segment_has_flow(ahead, demand.flow_id)
                    end
                    if passes_through and os.getenv("F2LOG") then io.write("F2 refuse seed ", key, " ", tostring(demand.flow_id), " -> ", tostring(demand.sink.block_id), "\n"); io.flush() end
                end
                if passes_through then seed_cost = nil
                elseif x == demand.sink.x and y == demand.sink.y
                    and demand.sink.travel_dir ~= nil and heading ~= demand.sink.travel_dir then]]
  local a, b = src:find(old, 1, true); assert(a, "F2 needle 1")
  src = src:sub(1, a - 1) .. new .. src:sub(b + 1)
  local old2 = "                enqueue_state(search, x, y, heading, 0, nil, seed_cost)\n"
  local a2, b2 = src:find(old2, 1, true); assert(a2, "F2 needle 2")
  src = src:sub(1, a2 - 1) .. "                if seed_cost ~= nil then enqueue_state(search, x, y, heading, 0, nil, seed_cost) end\n" .. src:sub(b2 + 1)
  return src
end
