--Round 48 physical twin: two medium-electric-poles 8 tiles apart (inside reach) joined only by a RED circuit wire
--(connector 1 = defines.wire_connector_id.circuit_red in 2.0) where a copper wire (connector 5) was needed. A circuit
--wire carries signals, not power: the engine keeps the poles on two electric networks. The red wire is the only link,
--so the validator also reports the split (BP_V_WIRE_DISCONNECTED). Pair: 07_1 (breach) / 07_2 (clean).
local entities = {
    {id = "p1", kind = "pole", name = "medium-electric-pole", x = 1, y = 1},
    {id = "p2", kind = "pole", name = "medium-electric-pole", x = 9, y = 1},
}
local validator = {
    --2.0 connector ids (defines.wire_connector_id): circuit_red 1, circuit_green 2, pole_copper 5.
    wire_connector_ids = {circuit_red = 1, circuit_green = 2},
    wires = {{a_id = "p1", a_connector = 1, b_id = "p2", b_connector = 1}},
    catalog = {entity = {["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9}}},
}
return {id = "T-280-V71", rule = "BP_V_WIRE_ILLEGAL", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 16, h = 3}, entities = entities, validator = validator, stage = "validate", check = "network", truth = "defect",
    codes = {"BP_V_WIRE_DISCONNECTED", "BP_V_WIRE_ILLEGAL"}, audit = {}}
