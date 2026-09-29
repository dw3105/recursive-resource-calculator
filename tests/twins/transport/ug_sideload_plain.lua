--Round 48 fix loop, clean twin: the same side-load from the south onto a PLAIN belt at (3,2): the feeding belt's
--two lanes merge onto the near lane (7.5/s fits one yellow lane), nothing is blocked, all 7.5/s arrive.
local entities = {
    {id = "f0", kind = "belt", name = "transport-belt", x = 3, y = 5, dir = "north", flows = {"iron-plate"}},
    {id = "f1", kind = "belt", name = "transport-belt", x = 3, y = 4, dir = "north", flows = {"iron-plate"}},
    {id = "f2", kind = "belt", name = "transport-belt", x = 3, y = 3, dir = "north", flows = {"iron-plate"}},
}
for x = 3, 9 do entities[#entities + 1] = {id = "e" .. x, kind = "belt", name = "transport-belt", x = x, y = 2, dir = "east", flows = {"iron-plate"}} end
return {
 id = "ug_sideload_plain", rule = "BP_V_UNDERGROUND_SIDELOAD_BLOCKED", class = "engine", from = "round 48 engine trial (clean control)",
 grid = {w = 10, h = 6},
 entities = entities,
 validator = {catalog = {entity = {}, belt = {items_per_second = 15, lane_items_per_second = 7.5}}},
 feeds = {{tile = {3, 5}, item = "iron-plate"}},
 sinks = {{tile = {9, 2}, items = {"iron-plate"}, rate = 7.5}},
 check = "rate", truth = "ok", codes = {},
 audit = {blueprint_audit = {sideload_blocked = 0}},
}
