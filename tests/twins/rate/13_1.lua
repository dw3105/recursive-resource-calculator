--Round 48 physical twin: feed belt (west edge) -> inserter -> sink belt (east edge). Step s needs 2 items/s; its only route is one inserter (~0.83 items/s), so the planned allocation reaching s is 0.83 and the sink sees < 0.95 x 2.
--Pair: 13_1 (breach) / 13_2 (clean).
local entities = {
    {id = "in0", kind = "belt", name = "transport-belt", x = 0, y = 0, dir = "east", flows = {"iron-plate"}},
    {id = "in1", kind = "belt", name = "transport-belt", x = 1, y = 0, dir = "east", flows = {"iron-plate"}},
    {id = "in2", kind = "belt", name = "transport-belt", x = 2, y = 0, dir = "east", flows = {"iron-plate"}},
    {id = "in3", kind = "belt", name = "transport-belt", x = 3, y = 0, dir = "east", flows = {"iron-plate"}},
    {id = "hand", kind = "inserter", name = "inserter", x = 3, y = 1, dir = "south"},
    {id = "out3", kind = "belt", name = "transport-belt", x = 3, y = 2, dir = "east", flows = {"iron-plate"}},
    {id = "pole", kind = "pole", name = "medium-electric-pole", x = 1, y = 1},
}
local validator = {
    flows = {{flow_id = "item/iron-plate", producers = {{step_id = "src", share_per_second = 2}}, consumers = {{step_id = "s", share_per_second = 2}}}},
    segments = {{segment_id = "hand", kind = "inserter", flow_id = "item/iron-plate", capacity_per_second = 0.83,
        allocations = {{flow_id = "item/iron-plate", sink = "step:s", rate_per_second = 0.83}}}},
    catalog = {entity = {
        ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false},
        inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = true, items_per_second = 0.83},
        ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
    }, inserter = {items_per_second = 0.83, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
        belt = {items_per_second = 15, lane_items_per_second = 7.5}},
}
return {id = "T-280-V131", rule = "BP_V_TARGET_SHORTFALL", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 4, h = 3}, entities = entities, validator = validator, stage = "validate", check = "rate", truth = "defect",
    codes = {"BP_V_TARGET_SHORTFALL"},
    feeds = {{tile = {0, 0}, item = "iron-plate"}}, sinks = {{tile = {3, 2}, items = {"iron-plate"}, rate = 2}},
    audit = {}}
