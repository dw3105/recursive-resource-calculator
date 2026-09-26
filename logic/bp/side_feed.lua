--A belt that feeds a laid run from the side must keep a belt to feed: burying that run under a crossing flow puts
--the side feed onto an underground entrance, where one lane is blocked (BP_V_UNDERGROUND_SIDELOAD_BLOCKED).
--Round 40 stub: lane 230 fills the answer. `cells` maps key(x, y) to a route segment; `key` is route.lua's
--coordinate_key; `tiles` is the run's tiles as {{x, y}, ...}; `direction` is the run's heading.
local SideFeed = {}
local Grid = require "logic.bp.grid"

local DIRECTIONS = {Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}

--true = some belt feeds one of `tiles` from a side, so the run may not be buried.
function SideFeed.into(cells, key, tiles, direction)
    for _, tile in ipairs(tiles or {}) do
        local px, py = tile[1], tile[2]
        for _, d in ipairs(DIRECTIONS) do
            if d ~= direction and d ~= Grid.dir_opposite(direction) then
                local dx, dy = Grid.dir_vector(d)
                local side_key = key(px - dx, py - dy)
                local side = cells[side_key]
                if side and side.kind == "belt" and not side.splitter and side.direction == d
                    and not (side.underground and side.underground_entry_key == side_key) then
                    return true
                end
            end
        end
    end
    return false
end

return SideFeed
