--An orphan belt at the far edge carries nothing: the engine sees an entity with a declared flow that never moves
--an item (waste). The machine row beside it is unpowered on purpose: it need not run for the waste to show.
return {
 id = "transport_unused_bad", rule = "BP_V_TRANSPORT_UNUSED", class = "waste", from = "tests/test_validate.lua S1 transport waste",
 grid = {w = 20, h = 20},
 entities = {
  {id = "machine", kind = "machine", name = "assembling-machine-1", x = 2, y = 1, w = 3, h = 3, recipe = "iron-gear-wheel", step_id = "step"},
  {id = "support", kind = "belt", name = "transport-belt", x = 0, y = 2, dir = "east", flow_id = "item/iron-plate"},
  {id = "hand", kind = "inserter", name = "inserter", x = 1, y = 2, dir = "east", flow_id = "item/iron-plate", role = "input", machine_id = "machine", pickup_target = "support", drop_target = "machine", pickup_position = {x = 0.5, y = 2.5}, drop_position = {x = 2.5, y = 2.5}},
  {id = "line", kind = "belt", name = "transport-belt", x = 0, y = 5, dir = "east", flows = {"iron-plate"}},
  {id = "orphan", kind = "belt", name = "transport-belt", x = 19, y = 6, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 5}, item = "iron-plate"}},
 validator = {catalog = {inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}, entity = {["assembling-machine-1"] = {name = "assembling-machine-1", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = false}, inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 5}, ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false}}}, plan = {steps = {{step_id = "step", machine = "assembling-machine-1", recipe = "iron-gear-wheel", machine_count = 1}}}},
 check = "flow_purity", truth = "waste", codes = {"BP_V_TRANSPORT_UNUSED"},
 audit = {},
}
