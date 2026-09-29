--Round 48 physical twin: two powered roboports 20 tiles apart (centres x=2 and x=22), well inside the 50 tiles at
--which their 25-tile logistic areas meet: the engine joins them into one logistic network. Two wired substations
--power both. Pair: 02_1 (breach) / 02_2 (clean).
local entities = {
    {id = "r1", kind = "roboport", name = "roboport", x = 0, y = 0, w = 4, h = 4},
    {id = "r2", kind = "roboport", name = "roboport", x = 20, y = 0, w = 4, h = 4},
    {id = "s1", kind = "pole", name = "substation", x = 0, y = 4, w = 2, h = 2},
    {id = "s2", kind = "pole", name = "substation", x = 14, y = 4, w = 2, h = 2},
}
local validator = {
    wires = {{a_id = "s1", a_connector = 5, b_id = "s2", b_connector = 5}},
    catalog = {entity = {
        roboport = {name = "roboport", etype = "roboport", tile_w = 4, tile_h = 4, needs_power = true, logistic_radius = 25},
        substation = {name = "substation", etype = "electric-pole", tile_w = 2, tile_h = 2, supply_w = 9, supply_h = 9, wire_reach = 18},
    }},
}
return {id = "T-280-V22", rule = "BP_V_ROBO_DISCONNECTED", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 24, h = 6}, entities = entities, validator = validator, stage = "validate", check = "network", truth = "ok",
    codes = {}, audit = {}}
