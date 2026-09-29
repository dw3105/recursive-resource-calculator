--Round 48 physical twin: a medium-electric-pole at (0,5) supplies x -3..4 (3.5 each side of its centre); the
--assembling-machine-2 at columns 5..7 lies outside it and stays off the network. Pair: 06_1 (breach) / 06_2 (clean).
local entities = {
    {id = "p", kind = "pole", name = "medium-electric-pole", x = 0, y = 5},
    {id = "m", kind = "machine", name = "assembling-machine-2", x = 5, y = 5, w = 3, h = 3, recipe = "iron-gear-wheel"},
}
local validator = {catalog = {entity = {
    ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = true, crafting_speed = 0.75},
    ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
}}}
return {id = "T-280-V61", rule = "BP_V_POWER_UNCOVERED", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 10, h = 10}, entities = entities, validator = validator, stage = "validate", check = "powered", truth = "defect",
    codes = {"BP_V_POWER_UNCOVERED"}, audit = {}}
