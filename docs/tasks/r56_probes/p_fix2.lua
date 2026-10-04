-- ticket 19 FIX2 probe: route.lua:3392 port-tile pipe dive guard on every search phase (not only strict_ptg).
-- P19_FIX2_SINK=1 also applies the :3403 sink-heading surfacing rule always. Chained on p_fix.lua (FIX1) unless P19_NOFIX1=1.
local base = dofile(os.getenv("HOME") .. "/.claude/plans/wayfinder-rrc-speed/research/19-probe/" .. (os.getenv("P19_NOFIX1") and "p_commits.lua" or "p_fix.lua"))
io.write("P19-FIX2-PATCH live sink=" .. tostring(os.getenv("P19_FIX2_SINK")) .. " nofix1=" .. tostring(os.getenv("P19_NOFIX1")) .. "\n")
return function(name, src)
    src = base(name, src)
    if name ~= "logic.bp.route" then return src end
    local n
    src, n = src:gsub("local port_here = work%.strict_ptg and search%.demand%.kind == \"pipe\"", function()
        return "local port_here = search.demand.kind == \"pipe\"" end)
    assert(n == 1, "3392 " .. n)
    if os.getenv("P19_FIX2_SINK") then
        src, n = src:gsub("search%.demand%.kind == \"pipe\" and work%.strict_ptg then sink_heading", function()
            return "search.demand.kind == \"pipe\" then sink_heading" end)
        assert(n == 1, "3403 " .. n)
    end
    return src
end
