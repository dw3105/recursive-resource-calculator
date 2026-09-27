package.path = "./?.lua;./?/init.lua;" .. package.path
local src = io.open("logic/bp/route.lua"):read("*a")
local n1, n2
src, n1 = src:gsub("and not %(current.mode == 1 and search.demand.kind == \"pipe\"%)", "and not (current.mode == 1 and (search.demand.kind == \"pipe\" or search.demand.no_chain_dive))", 1)
src, n2 = src:gsub("                    elseif not placed then\n                        fail_demand%(state, work, demand, reason == \"capacity\"", function() return [[
                    elseif not placed and reason == "route-discontinuous" and not demand.no_chain_dive and (function()
                            for i = 2, #outcome - 1 do
                                if is_crossing_step(outcome[i - 1], outcome[i]) and is_crossing_step(outcome[i], outcome[i + 1]) then return true end
                            end
                            return false
                        end)() then
                        if not restart_with_priority(state, work, demand) then
                            demand.no_chain_dive = true
                            work.current = begin_search(work, demand, amount, 1)
                        end
                    elseif not placed then
                        fail_demand(state, work, demand, reason == "capacity"]] end, 1)
assert(n1 == 1 and n2 == 1, "patch " .. n1 .. n2)



do
local m1, m2, m3
src, m1 = src:gsub("local refused_body = leaving ~= nil and leaving.kind ~= \"pipe\" and splitter_can_absorb%(leaving%)", "local refused_body = leaving ~= nil and leaving.kind ~= \"pipe\" and (search.demand.strict_branch or splitter_can_absorb(leaving))", 1)
src, m2 = src:gsub("    search.source_key = state_key%(demand.source.x, demand.source.y, demand.source.travel_dir or 0, demand.kind, 0%)", function() return "    local seed_heading = demand.source.travel_dir or 0\n    do local sg = demand.strict_branch and work.segments_by_cell[coordinate_key(demand.source.x, demand.source.y)]; if sg and sg.kind == \"belt\" and not sg.underground and sg.direction ~= nil and demand.kind ~= \"pipe\" then seed_heading = sg.direction end end\n    search.source_key = state_key(demand.source.x, demand.source.y, seed_heading, demand.kind, 0)" end, 1)
src = src:gsub("        direction = demand.source.travel_dir or 0, mode = 0, cost = 0,", "        direction = seed_heading, mode = 0, cost = 0,", 1)
src, m3 = src:gsub("if work.current == nil then fail_demand%(state, work, demand, \"BP_R_NO_PATH\"%) end", function() return [[if work.current == nil then
                            if demand.strict_branch then fail_demand(state, work, demand, "BP_R_NO_PATH")
                            elseif not restart_with_priority(state, work, demand) then
                                demand.strict_branch = true
                                work.current = begin_search(work, demand, amount, 1)
                            end
                        end]] end, 1)
assert(m1 == 1 and m2 == 1 and m3 == 1, "f2c")
PATCHED_SRC = src

end
package.preload["logic.bp.route"] = assert(load(src, "@logic/bp/route.lua"))
