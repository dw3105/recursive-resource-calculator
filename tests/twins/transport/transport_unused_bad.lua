return {
 id = "transport_unused_bad", rule = "BP_V_TRANSPORT_UNUSED", class = "waste", from = "tests/test_validate.lua S1 transport waste",
 grid = {w = 20, h = 20},
 entities = {
  {id = "machine", kind = "machine", name = "assembler", x = 2, y = 2, step_id = "step"},
  {id = "support", kind = "belt", name = "ug", x = 0, y = 2, dir = "east", flow_id = "item/in"},
  {id = "hand", kind = "inserter", name = "inserter", x = 1, y = 2, dir = "east", flow_id = "item/in", role = "input", machine_id = "machine", pickup_target = "support", drop_target = "machine", pickup_position = {x = 0.5, y = 2.5}, drop_position = {x = 2.5, y = 2.5}},
  {id = "line", kind = "belt", name = "transport-belt", x = 0, y = 4, dir = "east", flows = {"iron-plate"}},
  {id = "orphan", kind = "belt", name = "transport-belt", x = 19, y = 6, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 4}, item = "iron-plate"}},
 validator = {catalog = {inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}, entity = {assembler = {name = "assembler", etype = "assembling-machine", tile_w = 1, tile_h = 1, needs_power = false}, inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 5}, belt = {name = "ug", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false}}}, plan = {steps = {{step_id = "step", machine = "assembler", machine_count = 1}}}},
 check = "flow_purity", truth = "waste", codes = {"BP_V_TRANSPORT_UNUSED"},
 audit = {},
}
