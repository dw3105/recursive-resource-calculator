return {
 id = "route_discontinuous_ok", rule = "BP_V_ROUTE_DISCONTINUOUS", class = "engine", from = "tests/test_physical_witness.lua WI1 valid transfer control",
 grid = {w = 12, h = 10},
 entities = {
  {id = "machine", kind = "machine", name = "assembling-machine-1", x = 3, y = 3, w = 3, h = 3, step_id = "step", quality = "normal", recipe = "iron-gear-wheel", recipe_quality = "normal", modules = {}},
  {id = "in-belt", kind = "belt", name = "transport-belt", x = 0, y = 4, dir = "east", flow_id = "item/iron-plate"},
  {id = "in-belt2", kind = "belt", name = "transport-belt", x = 1, y = 4, dir = "east", flow_id = "item/iron-plate"},
  {id = "in-hand", kind = "inserter", name = "inserter", x = 2, y = 4, dir = "east", flow_id = "item/iron-plate", role = "input", machine_id = "machine", pickup_target = "external-in", drop_target = "machine", rate_per_second = 1, pickup_position = {x = 0.5, y = 4.5}, drop_position = {x = 3.5, y = 4.5}},
  {id = "out-hand", kind = "inserter", name = "inserter", x = 6, y = 4, dir = "east", flow_id = "item/iron-gear-wheel", role = "output", machine_id = "machine", pickup_target = "machine", drop_target = "external-out", rate_per_second = 1, pickup_position = {x = 5.5, y = 4.5}, drop_position = {x = 7.5, y = 4.5}},
  {id = "out-belt1", kind = "belt", name = "transport-belt", x = 7, y = 4, dir = "east", flow_id = "item/iron-gear-wheel"},
  {id = "out-belt2", kind = "belt", name = "transport-belt", x = 8, y = 4, dir = "east", flow_id = "item/iron-gear-wheel"},
  {id = "out-belt3", kind = "belt", name = "transport-belt", x = 9, y = 4, dir = "east", flow_id = "item/iron-gear-wheel"},
  {id = "out-belt4", kind = "belt", name = "transport-belt", x = 10, y = 4, dir = "east", flow_id = "item/iron-gear-wheel"},
  {id = "out-belt5", kind = "belt", name = "transport-belt", x = 11, y = 4, dir = "east", flow_id = "item/iron-gear-wheel"},
  {id = "pole", kind = "pole", name = "substation", x = 4, y = 7, w = 2, h = 2}
 },
 validator = {
  catalog = {
   inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
   entity = {
    ["assembling-machine-1"] = {name = "assembling-machine-1", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = false, module_slots = 0},
    inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 5},
    ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false},
    substation = {name = "substation", etype = "electric-pole", tile_w = 2, tile_h = 2, supply_w = 9, supply_h = 9, wire_reach = 18, needs_power = false},
   },
  },
  plan = {steps = {{step_id = "step", machine = "assembling-machine-1", machine_count = 1, recipe = "iron-gear-wheel", recipe_quality = "normal", modules = {}, inputs = {{full_name = "item/iron-plate", rate_per_second = 1}}, outputs = {{full_name = "item/iron-gear-wheel", rate_per_second = 1}}}}},
  flows = {{flow_id = "item/iron-plate"}, {flow_id = "item/iron-gear-wheel"}},
  ports = {
   {port_id = "external-in", flow_id = "item/iron-plate", role = "in", x = 0, y = 4, rate_per_second = 1},
   {port_id = "machine-in", flow_id = "item/iron-plate", role = "in", step_id = "step", x = 2, y = 4, rate_per_second = 1},
   {port_id = "machine-out", flow_id = "item/iron-gear-wheel", role = "out", step_id = "step", x = 6, y = 4, rate_per_second = 1},
   {port_id = "external-out", flow_id = "item/iron-gear-wheel", role = "out", x = 11, y = 4, rate_per_second = 1},
  },
  segments = {
   {id = "input", segment_id = "input", kind = "belt", flow_id = "item/iron-plate", capacity_per_second = 5, length = 2, allocations = {{flow_id = "item/iron-plate", sink = "step:step", rate_per_second = 1}}},
   {id = "output", segment_id = "output", kind = "belt", flow_id = "item/iron-gear-wheel", capacity_per_second = 5, length = 5, allocations = {{flow_id = "item/iron-gear-wheel", sink = "port:external-out", rate_per_second = 1}}},
  },
  bindings = {
   {source_port_id = "external-in", sink_port_id = "machine-in", flow_id = "item/iron-plate", sink = "step:step", segment_id = "input", rate_per_second = 1},
   {source_port_id = "machine-out", sink_port_id = "external-out", flow_id = "item/iron-gear-wheel", sink = "port:external-out", segment_id = "output", rate_per_second = 1},
  },
 },
 check = "pickup_drop", truth = "ok", codes = {}, audit = {},
}
