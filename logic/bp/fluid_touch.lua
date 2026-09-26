--Two fluids must never touch: a plain pipe joins every neighbouring pipe, so a pipe laid beside another fluid's
--pipe mixes both networks (BP_V_FLUID_MIX). Round 40 stub: lane 229 fills both answers.
--`cells` maps key(x, y) to a route segment; `key` is route.lua's coordinate_key.
local FluidTouch = {}

--May a pipe demand step onto tile (x, y)? true = refused, a foreign pipe sits beside it.
function FluidTouch.path_blocked(cells, key, demand, x, y)
    if not demand or demand.kind ~= "pipe" then return false end
    local flow_id = demand.flow_id
    local neighbours = {{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1}}
    for _, position in ipairs(neighbours) do
        local segment = cells[key(position[1], position[2])]
        if segment and segment.kind == "pipe" and not segment.underground
            and segment.flow_id ~= flow_id and not (segment.flow_ids and segment.flow_ids[flow_id] == true) then
            return true
        end
    end
    return false
end

--May an empty pipe-to-ground pair surface as plain pipes on `tiles` ({x=, y=} list)? true = keep it buried.
function FluidTouch.unbury_blocked(cells, key, pair, tiles)
    if not pair or pair.kind ~= "pipe" then return false end
    local flow_id = pair.flow_id
    for _, tile in ipairs(tiles or {}) do
        local neighbours = {{tile.x - 1, tile.y}, {tile.x + 1, tile.y}, {tile.x, tile.y - 1}, {tile.x, tile.y + 1}}
        for _, position in ipairs(neighbours) do
            local segment = cells[key(position[1], position[2])]
            if segment and segment ~= pair and segment.kind == "pipe"
                and segment.flow_id ~= flow_id and not (segment.flow_ids and segment.flow_ids[flow_id] == true) then
                return true
            end
        end
    end
    return false
end

return FluidTouch
