return function(src)
  local n
  src, n = src:gsub("                if work.multi_flow_hands and not segment_has_flow%(segment, demand.flow_id%) and not search.merge_target then\n", function() return [[
                local shared_cell = is_target and work.port_cells and work.port_cells[coordinate_key(x, y)]
                local shared_hand = shared_cell and shared_cell[demand.sink and demand.sink.port_id]
                    and segment.flow_id ~= nil and shared_cell["flow:" .. tostring(segment.flow_id)]
                if work.multi_flow_hands and not segment_has_flow(segment, demand.flow_id) and not search.merge_target
                    and not shared_hand then
]] end, 1)
  assert(n == 1, "f8")
  return src
end
