--Round 48 fix loop: a belt side-loads from the north into an east-facing underground entrance at (3,2); the exit at
--(6,2) runs to a sink at (9,2). The engine shows whether that side's lane passes (ok) or the hood blocks it (defect).
return {
 id = "ug_sideload_north", rule = "BP_V_UNDERGROUND_SIDELOAD_BLOCKED", class = "engine", from = "round 48 engine trial (validate.lua side-load walk)",
 grid = {w = 10, h = 6},
 entities = {
    {id = "f0", kind = "belt", name = "transport-belt", x = 3, y = 0, dir = "south", flows = {"iron-plate"}},
    {id = "f1", kind = "belt", name = "transport-belt", x = 3, y = 1, dir = "south", flows = {"iron-plate"}},
    {id = "in", kind = "belt", name = "underground-belt", x = 3, y = 2, dir = "east", type = "input", ug_role = "input", ug_pair_id = "out", flows = {"iron-plate"}},
    {id = "out", kind = "belt", name = "underground-belt", x = 6, y = 2, dir = "east", type = "output", ug_role = "output", ug_pair_id = "in", flows = {"iron-plate"}},
    {id = "e7", kind = "belt", name = "transport-belt", x = 7, y = 2, dir = "east", flows = {"iron-plate"}},
    {id = "e8", kind = "belt", name = "transport-belt", x = 8, y = 2, dir = "east", flows = {"iron-plate"}},
    {id = "e9", kind = "belt", name = "transport-belt", x = 9, y = 2, dir = "east", flows = {"iron-plate"}},
 },
 validator = {catalog = {entity = {}, belt = {items_per_second = 15, lane_items_per_second = 7.5, underground_max_distance = 5}}},
 feeds = {{tile = {3, 0}, item = "iron-plate"}},
 sinks = {{tile = {9, 2}, items = {"iron-plate"}}},
 check = "flow_purity", truth = "defect", codes = {"BP_V_UNDERGROUND_SIDELOAD_BLOCKED"},  --validator claim; engine verdict pending
 audit = {blueprint_audit = {sideload_blocked = 0}},
}
