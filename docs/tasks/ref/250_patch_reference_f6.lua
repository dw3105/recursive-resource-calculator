return function(src)
  local n1, n2
  src, n1 = src:gsub("and not %(current.mode == 1 and %(search.demand.kind == \"pipe\" or search.demand.no_chain_dive%)%)", function() return [[and not (current.mode == 1 and (search.demand.kind == "pipe" or search.demand.no_chain_dive or search.demand.strict_dive))
                and not (search.demand.strict_dive and work.segments_by_cell[coordinate_key(current.x, current.y)] ~= nil)]] end, 1)
  src, n2 = src:gsub([[
                        if demand.crossing_retries <= 4 then
                            work.current = begin_search%(work, demand, amount, 1%)
                        else
                            fail_demand%(state, work, demand, "BP_R_NO_PATH"%)
                        end]], function() return [[
                        if demand.crossing_retries <= 4 then
                            work.current = begin_search(work, demand, amount, 1)
                        elseif not demand.strict_dive then
                            demand.strict_dive, demand.no_self_cross = true, true
                            demand.crossing_retries = 0
                            work.current = begin_search(work, demand, amount, 1)
                        else
                            fail_demand(state, work, demand, "BP_R_NO_PATH")
                        end]] end, 1)
  assert(n1 == 1 and n2 == 1, "f6 " .. n1 .. n2)
  return src
end
