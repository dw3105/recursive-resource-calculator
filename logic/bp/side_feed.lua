--A belt that feeds a laid run from the side must keep a belt to feed: burying that run under a crossing flow puts
--the side feed onto an underground entrance, where one lane is blocked (BP_V_UNDERGROUND_SIDELOAD_BLOCKED).
--Round 40 stub: lane 230 fills the answer. `cells` maps key(x, y) to a route segment; `key` is route.lua's
--coordinate_key; `tiles` is the run's tiles as {{x, y}, ...}; `direction` is the run's heading.
local SideFeed = {}

--true = some belt feeds one of `tiles` from a side, so the run may not be buried.
function SideFeed.into(cells, key, tiles, direction)
    return false
end

return SideFeed
