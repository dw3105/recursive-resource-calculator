--Round 48 physical twin: two medium-electric-poles 12 tiles apart with no wire between them (out of the 9-tile reach
--anyway): the engine keeps them on two electric networks. Pair: 08_1 (breach) / 08_2 (clean).
local entities = {
    {id = "p1", kind = "pole", name = "medium-electric-pole", x = 1, y = 1},
    {id = "p2", kind = "pole", name = "medium-electric-pole", x = 13, y = 1},
}
local validator = {catalog = {entity = {["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9}}}}
return {id = "T-280-V81", rule = "BP_V_WIRE_DISCONNECTED", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 16, h = 3}, entities = entities, validator = validator, stage = "validate", check = "network", truth = "defect",
    codes = {"BP_V_WIRE_DISCONNECTED"}, audit = {}}
