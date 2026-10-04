-- ticket 13 lever probe: strict_ends from first routing (no strict redo), chained on restart log patch.
local base = dofile(os.getenv("HOME") .. "/.claude/plans/wayfinder-rrc-speed/research/13-probe/p_restart.lua")
io.write("P13-STRICT-PATCH live\n")
return function(name, src)
    src = base(name, src)
    if name ~= "logic.bp.search" then return src end
    local n
    src, n = src:gsub("if route_input and state%.work%.strict_ends then route_input%.strict_ends = true end", function()
        return "if route_input then route_input.strict_ends = true; state.work.strict_ends = true end"
    end)
    assert(n == 1, "strict site " .. n)
    return src
end
