--Round 48 physical twin: a working electric-furnace line whose plan configures one beacon; two are built (above and
--below). Two give 1.15 plates/s; removing either still gives the planned 1.0 (0.625 x 1.6), so each is surplus. ENGINE GAP: today's beacon_effect check runs the flow path, which sees a pure, fed line and
--says ok; it needs a per-beacon removal (or effects vs plan) check in tests/game/test_twins.lua to see the waste.
--Pair: 04_1 (breach) / 04_2 (clean).
local entities = {
    {id = "in0", kind = "belt", name = "transport-belt", x = 0, y = 8, dir = "east", flows = {"iron-ore"}},
    {id = "in1", kind = "belt", name = "transport-belt", x = 1, y = 8, dir = "east", flows = {"iron-ore"}},
    {id = "hand-in", kind = "inserter", name = "fast-inserter", x = 2, y = 8, dir = "east", full_name = "item/iron-ore", role = "input", machine_id = "m", pickup_target = "external-in", drop_target = "m"},
    {id = "m", kind = "machine", name = "electric-furnace", x = 3, y = 7, w = 3, h = 3, step_id = "s"},
    {id = "hand-out", kind = "inserter", name = "fast-inserter", x = 6, y = 8, dir = "east", full_name = "item/iron-plate", role = "output", machine_id = "m", pickup_target = "m", drop_target = "external-out"},
    {id = "out7", kind = "belt", name = "transport-belt", x = 7, y = 8, dir = "east", flows = {"iron-plate"}},
    {id = "b1", kind = "beacon", name = "beacon", x = 3, y = 4, w = 3, h = 3, modules = {{name = "speed-module", count = 2}}, required_for = {"m"}},
    {id = "b2", kind = "beacon", name = "beacon", x = 3, y = 10, w = 3, h = 3, modules = {{name = "speed-module", count = 2}}, required_for = {"m"}},
    {id = "p2", kind = "pole", name = "medium-electric-pole", x = 2, y = 6},
    {id = "p3", kind = "pole", name = "medium-electric-pole", x = 2, y = 10},
    {id = "p4", kind = "pole", name = "medium-electric-pole", x = 6, y = 6},
}
local validator = {
    plan = {steps = {{step_id = "s", machine = "electric-furnace", machine_count = 1, beacon_groups = {{name = "beacon", count_per_machine = 1}},
        inputs = {{full_name = "item/iron-ore", rate_per_second = 1.0}}, outputs = {{full_name = "item/iron-plate", rate_per_second = 1.0}}}}},
    flows = {{flow_id = "item/iron-ore"}, {flow_id = "item/iron-plate"}},
    ports = {
        {port_id = "external-in", flow_id = "item/iron-ore", role = "in", x = 0, y = 8, rate_per_second = 1.0},
        {port_id = "machine-in", flow_id = "item/iron-ore", role = "in", step_id = "s", x = 2, y = 8, rate_per_second = 1.0},
        {port_id = "machine-out", flow_id = "item/iron-plate", role = "out", step_id = "s", x = 6, y = 8, rate_per_second = 1.0},
        {port_id = "external-out", flow_id = "item/iron-plate", role = "out", x = 7, y = 8, rate_per_second = 1.0},
    },
    segments = {
        {id = "input", segment_id = "input", kind = "belt", length = 2, flow_id = "item/iron-ore", capacity_per_second = 15, allocations = {{flow_id = "item/iron-ore", sink = "step:s", rate_per_second = 1.0}}},
        {id = "output", segment_id = "output", kind = "belt", length = 1, flow_id = "item/iron-plate", capacity_per_second = 15, allocations = {{flow_id = "item/iron-plate", sink = "port:external-out", rate_per_second = 1.0}}},
    },
    bindings = {
        {source_port_id = "external-in", sink_port_id = "machine-in", flow_id = "item/iron-ore", sink = "step:s", segment_id = "input", rate_per_second = 1.0},
        {source_port_id = "machine-out", sink_port_id = "external-out", flow_id = "item/iron-plate", sink = "port:external-out", segment_id = "output", rate_per_second = 1.0},
    },
    wires = {{a_id = "p2", a_connector = 5, b_id = "p3", b_connector = 5}, {a_id = "p2", a_connector = 5, b_id = "p4", b_connector = 5}},
    catalog = {entity = {
        ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false},
        ["fast-inserter"] = {name = "fast-inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = true, items_per_second = 2.31},
        ["electric-furnace"] = {name = "electric-furnace", etype = "furnace", tile_w = 3, tile_h = 3, needs_power = true, crafting_speed = 2, module_slots = 2},
        beacon = {name = "beacon", etype = "beacon", tile_w = 3, tile_h = 3, needs_power = true, module_slots = 2,
            beacon = {supply_w = 3, supply_h = 3, distribution_effectivity = 1.5}},
        ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
    }, inserter = {items_per_second = 2.31, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
        module = {["speed-module"] = {effects = {speed = 0.2, consumption = 0.5, quality = -0.1}}},
        belt = {items_per_second = 15, lane_items_per_second = 7.5}},
}
return {id = "T-280-V41", rule = "BP_V_BEACON_REDUNDANT", class = "waste", from = "tests/test_validate.lua twin candidate",
    grid = {w = 8, h = 13}, entities = entities, validator = validator, stage = "validate", check = "beacon_effect", truth = "waste",
    codes = {"BP_V_BEACON_REDUNDANT"},
    feeds = {{tile = {0, 8}, item = "iron-ore"}}, sinks = {{tile = {7, 8}, items = {"iron-plate"}, rate = 1.0}},
    audit = {},
}
