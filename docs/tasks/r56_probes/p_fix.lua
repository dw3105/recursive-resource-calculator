-- ticket 19 fix probe (FIX1): a splitter branch may not END on a row-port sink whose travel_dir differs from the
-- splitter (trunk) heading: the body's output faces the trunk way, the row head needs items moving travel_dir.
-- Search side only (route.lua body_jump, ~:3287). Chained on P19_CHAIN (default p_commits.lua).
local base = dofile(os.getenv("P19_CHAIN") or (os.getenv("HOME") .. "/.claude/plans/wayfinder-rrc-speed/research/19-probe/p_commits.lua"))
io.write("P19-FIX1-PATCH live\n")
return function(name, src)
    src = base(name, src)
    if name ~= "logic.bp.route" then return src end
    local old = [[
                and not (search.demand.crossing_blocked
                    and search.demand.crossing_blocked[current_tile_key])
                and segment_allows(work, leaving, search.demand, search.amount)]]
    local a, b = src:find(old, 1, true); assert(a, "body_jump site")
    return src:sub(1, a - 1) .. [[
                and not (search.demand.crossing_blocked
                    and search.demand.crossing_blocked[current_tile_key])
                and not (target and not search.merge_target and search.demand.sink.row_port and search.demand.sink.travel_dir ~= nil and leaving.direction ~= search.demand.sink.travel_dir and (function() _G.__p19_fixhits = (_G.__p19_fixhits or 0) + 1; return true end)())
                and segment_allows(work, leaving, search.demand, search.amount)]] .. src:sub(b + 1)
end
