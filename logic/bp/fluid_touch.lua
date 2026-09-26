--Two fluids must never touch: a plain pipe joins every neighbouring pipe, so a pipe laid beside another fluid's
--pipe mixes both networks (BP_V_FLUID_MIX). Round 40 stub: lane 229 fills both answers.
--`cells` maps key(x, y) to a route segment; `key` is route.lua's coordinate_key.
local FluidTouch = {}

--May a pipe demand step onto tile (x, y)? true = refused, a foreign pipe sits beside it.
function FluidTouch.path_blocked(cells, key, demand, x, y)
    return false
end

--May an empty pipe-to-ground pair surface as plain pipes on `tiles` ({x=, y=} list)? true = keep it buried.
function FluidTouch.unbury_blocked(cells, key, pair, tiles)
    return false
end

return FluidTouch
