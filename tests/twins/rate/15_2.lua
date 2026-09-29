--Round 48 physical twin: iron plates from the west edge -> fast inserter -> assembling-machine-2 on iron-gear-wheel ->
--fast inserter -> sink belt (east edge). The plan asks this machine for iron-gear-wheel at 0.75/s; a fast hand
--brings ~2.3 plates/s, so ~1.1 gears/s leave. Pair: 15_1 (breach, wrong recipe) / 15_2 (clean).
local entities = {
    {id = "in0", kind = "belt", name = "transport-belt", x = 0, y = 1, dir = "east", flows = {"iron-plate"}},
    {id = "in1", kind = "belt", name = "transport-belt", x = 1, y = 1, dir = "east", flows = {"iron-plate"}},
    {id = "hand-in", kind = "inserter", name = "fast-inserter", x = 2, y = 1, dir = "east", full_name = "item/iron-plate", role = "input", machine_id = "m", pickup_target = "external-in", drop_target = "m"},
    {id = "m", kind = "machine", name = "assembling-machine-2", x = 3, y = 0, w = 3, h = 3, step_id = "s", recipe = "iron-gear-wheel"},
    {id = "hand-out", kind = "inserter", name = "fast-inserter", x = 6, y = 1, dir = "east", full_name = "item/iron-gear-wheel", role = "output", machine_id = "m", pickup_target = "m", drop_target = "external-out"},
    {id = "out7", kind = "belt", name = "transport-belt", x = 7, y = 1, dir = "east", flows = {"iron-gear-wheel"}},
    {id = "pole", kind = "pole", name = "medium-electric-pole", x = 3, y = 3},
}
local validator = {
    plan = {steps = {{step_id = "s", machine = "assembling-machine-2", machine_count = 1, recipe = "iron-gear-wheel",
        inputs = {{full_name = "item/iron-plate", rate_per_second = 1.5}}, outputs = {{full_name = "item/iron-gear-wheel", rate_per_second = 0.75}}}}},
    flows = {{flow_id = "item/iron-plate"}, {flow_id = "item/iron-gear-wheel"}},
    ports = {
        {port_id = "external-in", flow_id = "item/iron-plate", role = "in", x = 0, y = 1, rate_per_second = 1.5},
        {port_id = "machine-in", flow_id = "item/iron-plate", role = "in", step_id = "s", x = 2, y = 1, rate_per_second = 1.5},
        {port_id = "machine-out", flow_id = "item/iron-gear-wheel", role = "out", step_id = "s", x = 6, y = 1, rate_per_second = 0.75},
        {port_id = "external-out", flow_id = "item/iron-gear-wheel", role = "out", x = 7, y = 1, rate_per_second = 0.75},
    },
    segments = {
        {id = "input", segment_id = "input", kind = "belt", length = 2, flow_id = "item/iron-plate", capacity_per_second = 15, allocations = {{flow_id = "item/iron-plate", sink = "step:s", rate_per_second = 1.5}}},
        {id = "output", segment_id = "output", kind = "belt", length = 1, flow_id = "item/iron-gear-wheel", capacity_per_second = 15, allocations = {{flow_id = "item/iron-gear-wheel", sink = "port:external-out", rate_per_second = 0.75}}},
    },
    bindings = {
        {source_port_id = "external-in", sink_port_id = "machine-in", flow_id = "item/iron-plate", sink = "step:s", segment_id = "input", rate_per_second = 1.5},
        {source_port_id = "machine-out", sink_port_id = "external-out", flow_id = "item/iron-gear-wheel", sink = "port:external-out", segment_id = "output", rate_per_second = 0.75},
    },
    catalog = {entity = {
        ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false},
        ["fast-inserter"] = {name = "fast-inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = true, items_per_second = 2.31},
        ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = true, crafting_speed = 0.75},
        ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
    }, inserter = {items_per_second = 2.31, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
        belt = {items_per_second = 15, lane_items_per_second = 7.5}},
}
return {id = "T-280-V152", rule = "BP_V_MACHINE_IDENTITY", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 8, h = 4}, entities = entities, validator = validator, stage = "validate", check = "rate", truth = "ok", codes = {},
    feeds = {{tile = {0, 1}, item = "iron-plate"}}, sinks = {{tile = {7, 1}, items = {"iron-gear-wheel"}, rate = 0.75}},
    audit = {}}
