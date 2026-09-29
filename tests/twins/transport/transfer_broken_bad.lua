return {
 id = "transfer_broken_bad", rule = "BP_V_TRANSFER_BROKEN", class = "engine", from = "tests/test_physical_witness.lua WI3 missing output transfer belt",
 grid = {w = 12, h = 10},
 entities = {
  {id = "machine", kind = "machine", type = "machine", name = "machine", x = 3, y = 3, w = 3, h = 3, step_id = "step", quality = "normal", recipe = "recipe", recipe_quality = "normal", modules = {}},
  {id = "in-belt", kind = "belt", type = "belt", name = "transport-belt", x = 0, y = 4, dir = "east", flow_id = "item/in"},
  {id = "in-belt2", kind = "belt", type = "belt", name = "transport-belt", x = 1, y = 4, dir = "east", flow_id = "item/in"},
  {id = "in-hand", kind = "inserter", type = "inserter", name = "inserter", x = 2, y = 4, dir = "east", flow_id = "item/in", role = "input", machine_id = "machine", pickup_target = "external-in", drop_target = "machine", rate_per_second = 1, pickup_position = {x = 0.5, y = 4.5}, drop_position = {x = 3.5, y = 4.5}},
  {id = "pole", kind = "pole", name = "pole", x = 4, y = 7}
 },
 validator = {
  catalog = {
   inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
   entity = {
    machine = {name = "machine", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = false, module_slots = 0},
    inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 5},
    belt = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false},
    pole = {name = "pole", etype = "electric-pole", tile_w = 1, tile_h = 1, needs_power = false},
   },
  },
  plan = {steps = {{step_id = "step", machine = "machine", machine_count = 1, recipe = "recipe", recipe_quality = "normal", modules = {}, inputs = {{full_name = "item/in", rate_per_second = 1}}, outputs = {{full_name = "item/out", rate_per_second = 1}}}}},
  flows = {{flow_id = "item/in"}, {flow_id = "item/out"}},
  ports = {
   {port_id = "external-in", flow_id = "item/in", role = "in", x = 0, y = 4, rate_per_second = 1},
   {port_id = "machine-in", flow_id = "item/in", role = "in", step_id = "step", x = 2, y = 4, rate_per_second = 1},
   {port_id = "machine-out", flow_id = "item/out", role = "out", step_id = "step", x = 6, y = 4, rate_per_second = 1},
   {port_id = "external-out", flow_id = "item/out", role = "out", x = 11, y = 4, rate_per_second = 1},
  },
  segments = {
   {id = "input", segment_id = "input", kind = "belt", flow_id = "item/in", capacity_per_second = 5, length = 2, allocations = {{flow_id = "item/in", sink = "step:step", rate_per_second = 1}}},
   {id = "output", segment_id = "output", kind = "belt", flow_id = "item/out", capacity_per_second = 5, length = 5, allocations = {{flow_id = "item/out", sink = "port:external-out", rate_per_second = 1}}},
  },
  bindings = {
   {source_port_id = "external-in", sink_port_id = "machine-in", flow_id = "item/in", sink = "step:step", segment_id = "input", rate_per_second = 1},
   {source_port_id = "machine-out", sink_port_id = "external-out", flow_id = "item/out", sink = "port:external-out", segment_id = "output", rate_per_second = 1},
  },
 },
 check = "pickup_drop", truth = "defect", codes = {"BP_V_TRANSFER_BROKEN"}, audit = {},
}
