--Round 48 physical twin: iron plates on a belt ending at (0,1); an item inserter at (1,1) loads them into an
--assembling-machine-2 on iron-gear-wheel. The engine gives the hand both targets. Pair: 10_1 (breach) / 10_2 (clean).
local entities = {
    {id = "b", kind = "belt", name = "transport-belt", x = 0, y = 1, dir = "south", flows = {"iron-plate"}},
    {id = "m", kind = "machine", name = "assembling-machine-2", x = 2, y = 0, w = 3, h = 3, recipe = "iron-gear-wheel"},
    {id = "i", kind = "inserter", name = "inserter", x = 1, y = 1, dir = "east", full_name = "item/iron-plate", role = "input", machine_id = "m"},
    {id = "p", kind = "pole", name = "medium-electric-pole", x = 1, y = 0},
}
local validator = {catalog = {
    entity = {
        ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false},
        ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = true, crafting_speed = 0.75,
            fluid_boxes = {{production_type = "input", pipe_connections = {{position = {x = -1, y = 0}}}}}},
        inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = true, items_per_second = 0.83},
        ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
    },
    inserter = {items_per_second = 0.83, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
    belt = {items_per_second = 15, lane_items_per_second = 7.5}}}
return {id = "T-280-V102", rule = "BP_V_FLUID_INSERTER", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 5, h = 3}, entities = entities, validator = validator, stage = "validate", check = "pickup_drop", truth = "ok",
    codes = {}, audit = {}}
