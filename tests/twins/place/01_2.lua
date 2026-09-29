--Round 48 physical twin: two assembling-machine-2 (3x3) edge to edge (columns 5..7 and 8..10): touching boxes do
--not collide, the engine places both. Pair: 01_1 (breach) / 01_2 (clean).
local entities = {
    {id = "m1", kind = "machine", name = "assembling-machine-2", x = 5, y = 5, w = 3, h = 3},
    {id = "m2", kind = "machine", name = "assembling-machine-2", x = 8, y = 5, w = 3, h = 3},
    {id = "p", kind = "pole", name = "medium-electric-pole", x = 5, y = 8},
}
local validator = {catalog = {entity = {
    ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", tile_w = 3, tile_h = 3, crafting_speed = 0.75, needs_power = true},
    ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
}}}
return {id = "T-280-V12", rule = "BP_V_COLLISION", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w = 20, h = 20},
    entities = entities, validator = validator, stage = "validate", check = "placeable", truth = "ok", codes = {},
    --AUDITOR-DOUBT: redundant beacon count stays zero because the audit runner provides no beacon config.
    audit = {blueprint_audit = {invalid_inserters = 0, backward_hands = 0, redundant_beacons = 0}}}
