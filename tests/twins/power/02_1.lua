--Round 48 physical twin: two powered roboports 56 tiles apart (centres x=2 and x=58). A roboport's logistic area
--reaches 25 tiles, so two join one logistic network only within 50 tiles: the engine keeps two networks. One chain of
--substations (17 apart, wire reach 18) powers both. Pair: 02_1 (breach) / 02_2 (clean).
local entities = {
    {id = "r1", kind = "roboport", name = "roboport", x = 0, y = 0, w = 4, h = 4},
    {id = "r2", kind = "roboport", name = "roboport", x = 56, y = 0, w = 4, h = 4},
    {id = "s1", kind = "pole", name = "substation", x = 0, y = 4, w = 2, h = 2},
    {id = "s2", kind = "pole", name = "substation", x = 17, y = 4, w = 2, h = 2},
    {id = "s3", kind = "pole", name = "substation", x = 34, y = 4, w = 2, h = 2},
    {id = "s4", kind = "pole", name = "substation", x = 51, y = 4, w = 2, h = 2},
}
local validator = {
    wires = {{a_id = "s1", a_connector = 5, b_id = "s2", b_connector = 5}, {a_id = "s2", a_connector = 5, b_id = "s3", b_connector = 5}, {a_id = "s3", a_connector = 5, b_id = "s4", b_connector = 5}},
    catalog = {entity = {
        roboport = {name = "roboport", etype = "roboport", tile_w = 4, tile_h = 4, needs_power = true, logistic_radius = 25},
        substation = {name = "substation", etype = "electric-pole", tile_w = 2, tile_h = 2, supply_w = 9, supply_h = 9, wire_reach = 18},
    }},
}
return {id = "T-280-V21", rule = "BP_V_ROBO_DISCONNECTED", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 60, h = 6}, entities = entities, validator = validator, stage = "validate", check = "network", truth = "defect",
    codes = {"BP_V_ROBO_DISCONNECTED"}, audit = {}}
