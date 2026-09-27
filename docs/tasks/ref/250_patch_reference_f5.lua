return function(src)
  local n1, n2
  src, n1 = src:gsub("    if previous ~= nil and cost >= previous %- EPSILON then return false end\n", function() return [[
    if previous ~= nil and cost >= previous - EPSILON then return false end
    if search.demand.no_self_cross and parent_key ~= nil then
        local walk = parent_key
        while walk do
            local p = search.points[walk]
            if p and p.x == x and p.y == y then return false end
            if walk == search.source_key then break end
            walk = search.parent[walk]
        end
    end
]] end, 1)
  src, n2 = src:gsub([[
                    elseif not placed and reason == "route%-discontinuous" and not demand.no_chain_dive then
                        local two_crossings = false
                        for i = 2, #outcome %- 1 do
                            if is_crossing_step%(outcome%[i %- 1%], outcome%[i%]%)
                                and is_crossing_step%(outcome%[i%], outcome%[i %+ 1%]%) then
                                two_crossings = true
                                break
                            end
                        end
                        if two_crossings then]], function() return [[
                    elseif not placed and reason == "route-discontinuous" and (not demand.no_chain_dive or not demand.no_self_cross) then
                        local two_crossings, revisit = false, false
                        local visited = {}
                        for i = 1, #outcome do
                            local k = coordinate_key(outcome[i].x, outcome[i].y)
                            if visited[k] then revisit = true end
                            visited[k] = true
                            if i > 1 and i < #outcome and is_crossing_step(outcome[i - 1], outcome[i])
                                and is_crossing_step(outcome[i], outcome[i + 1]) then
                                two_crossings = true
                            end
                        end
                        two_crossings = two_crossings and not demand.no_chain_dive
                        revisit = revisit and not demand.no_self_cross
                        if two_crossings or revisit then]] end, 1)
  assert(n1 == 1 and n2 == 1, "f5 " .. n1 .. n2)
  src, n2 = src:gsub([[
                            if not restart_with_priority%(state, work, demand%) then
                                demand.no_chain_dive = true
                                work.current = begin_search%(work, demand, amount, 1%)]], function() return [[
                            if not restart_with_priority(state, work, demand) then
                                if two_crossings then demand.no_chain_dive = true end
                                if revisit then demand.no_self_cross = true end
                                work.current = begin_search(work, demand, amount, 1)]] end, 1)
  assert(n2 == 1, "f5b")
  return src
end
