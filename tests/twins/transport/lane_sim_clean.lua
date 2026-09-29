return {
 id = "audit_lane_sim_clean", rule = "audit:lane_sim:bleed", class = "engine", from = "tests/test_validate_rows.lua VL4 single-flow input control",
 grid = {w = 20, h = 20},
 entities = {
  {id = "feed-a", kind = "belt", name = "transport-belt", x = 0, y = 10, dir = "east", flow_id = "item/iron-plate"},
  {id = "merge", kind = "belt", name = "transport-belt", x = 1, y = 10, dir = "east", flow_id = "item/iron-plate"},
  {id = "run", kind = "belt", name = "transport-belt", x = 2, y = 10, dir = "east", flow_id = "item/iron-plate"},
  {id = "row-input", kind = "inserter", name = "inserter", x = 1, y = 11, dir = "south", role = "input", pickup_position = {x = 1.5, y = 10.5}, drop_position = {x = 1.5, y = 12.5}},
  {id = "machine", kind = "machine", name = "assembling-machine-1", x = 1, y = 12, w = 3, h = 3, recipe = "iron-gear-wheel"},
  {id = "power", kind = "pole", name = "substation", x = 4, y = 11, w = 2, h = 2},
 },
 feeds = {{tile = {0, 10}, item = "iron-plate"}},
 sinks = {{tile = {2, 10}, items = {"iron-plate"}}},
 validator = {catalog = {entity = {
  inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 10},
  ["assembling-machine-1"] = {name = "assembling-machine-1", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = false},
  substation = {name = "substation", etype = "electric-pole", tile_w = 2, tile_h = 2, supply_w = 9, supply_h = 9, wire_reach = 18, needs_power = false},
 }, inserter = {items_per_second = 10, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}, belt = {items_per_second = 10}, recipe = { ["iron-gear-wheel"] = {ingredients = {{name = "iron-plate"}}, products = {{name = "iron-gear-wheel"}}}}}},
 check = "flow_purity", truth = "ok", codes = {}, audit = {lane_sim = {mixed = 0, starved = 0, bleed = 0}},
}
