--Round 48 physical twin: a belt ends at (1,0); the inserter under it picks from that belt and drops onto (1,2), which
--is empty ground. The engine gives the hand a pickup target and no drop target. Pair: 09_1 (breach) / 09_2 (clean).
local entities = {
    {id = "b0", kind = "belt", name = "transport-belt", x = 0, y = 0, dir = "east", flows = {"iron-plate"}},
    {id = "b1", kind = "belt", name = "transport-belt", x = 1, y = 0, dir = "east", flows = {"iron-plate"}},
    {id = "i", kind = "inserter", name = "inserter", x = 1, y = 1, dir = "south"},
    {id = "p", kind = "pole", name = "medium-electric-pole", x = 0, y = 1},
}
local validator = {catalog = {
    inserter = {items_per_second = 0.83, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
    entity = {
        ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false},
        inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = true, items_per_second = 0.83},
        ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
    },
    belt = {items_per_second = 15, lane_items_per_second = 7.5}}}
return {id = "T-280-V91", rule = "BP_V_INSERTER_GEOMETRY", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 4, h = 3}, entities = entities, validator = validator, stage = "validate", check = "pickup_drop", truth = "defect",
    codes = {"BP_V_INSERTER_GEOMETRY"}, audit = {blueprint_audit = {invalid_inserters = 1}}}
