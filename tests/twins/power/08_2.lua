--Round 48 physical twin: three medium-electric-poles 6 tiles apart, wired in a chain inside the 9-tile reach: the
--engine puts all three on one electric network. Pair: 08_1 (breach) / 08_2 (clean).
local entities = {
    {id = "p1", kind = "pole", name = "medium-electric-pole", x = 1, y = 1},
    {id = "p2", kind = "pole", name = "medium-electric-pole", x = 7, y = 1},
    {id = "p3", kind = "pole", name = "medium-electric-pole", x = 13, y = 1},
}
local validator = {
    wires = {{a_id = "p1", a_connector = 5, b_id = "p2", b_connector = 5}, {a_id = "p2", a_connector = 5, b_id = "p3", b_connector = 5}},
    catalog = {entity = {["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9}}},
}
return {id = "T-280-V82", rule = "BP_V_WIRE_DISCONNECTED", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 16, h = 3}, entities = entities, validator = validator, stage = "validate", check = "network", truth = "ok",
    codes = {}, audit = {}}
