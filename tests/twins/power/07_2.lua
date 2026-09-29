--Round 48 physical twin: two medium-electric-poles 8 tiles apart joined by a COPPER wire (connector 5) inside the
--9-tile reach: the engine makes the wire and both poles share one electric network. Pair: 07_1 (breach) / 07_2 (clean).
local entities = {
    {id = "p1", kind = "pole", name = "medium-electric-pole", x = 1, y = 1},
    {id = "p2", kind = "pole", name = "medium-electric-pole", x = 9, y = 1},
}
local validator = {
    wire_connector_ids = {circuit_red = 1, circuit_green = 2},
    wires = {{a_id = "p1", a_connector = 5, b_id = "p2", b_connector = 5}},
    catalog = {entity = {["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9}}},
}
return {id = "T-280-V72", rule = "BP_V_WIRE_ILLEGAL", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 16, h = 3}, entities = entities, validator = validator, stage = "validate", check = "network", truth = "ok",
    codes = {}, audit = {}}
