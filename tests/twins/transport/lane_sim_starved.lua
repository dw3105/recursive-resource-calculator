return {
 id = "lane_sim_starved", rule = "BP_V_ROUTE_LOOP", class = "engine", from = "tests/test_validate_transport_shapes.lua TS4 ring pickup is starved",
 grid = {w = 20, h = 20},
 entities = {
  {id = "r1", kind = "belt", name = "transport-belt", x = 4, y = 5, dir = "east"},
  {id = "r2", kind = "belt", name = "transport-belt", x = 5, y = 5, dir = "south"},
  {id = "r3", kind = "belt", name = "transport-belt", x = 5, y = 6, dir = "west"},
  {id = "r4", kind = "belt", name = "transport-belt", x = 4, y = 6, dir = "north"},
  {id = "hand", kind = "inserter", name = "inserter", x = 6, y = 6, dir = "east", role = "input", flow_id = "item/iron-plate", pickup_position = {x = 5.5, y = 6.5}, drop_position = {x = 7.5, y = 6.5}, needs_power = false},
  {id = "machine", kind = "machine", name = "assembling-machine-1", x = 7, y = 6, recipe = "iron-gear-wheel", needs_power = false},
 },
 validator = {catalog = {entity = {inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 10}, ["assembling-machine-1"] = {name = "assembling-machine-1", etype = "assembling-machine", tile_w = 1, tile_h = 1, needs_power = false}}, inserter = {items_per_second = 10, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}, belt = {items_per_second = 10}, recipe = {["iron-gear-wheel"] = {ingredients = {{name = "iron-plate"}}, products = {{name = "iron-gear-wheel"}}}}}},
 check = "flow_purity", truth = "defect", codes = {"BP_V_ROUTE_LOOP"}, audit = {lane_sim = {mixed = 0, starved = 1, bleed = 0}, blueprint_audit = {cycles = 1, unused_belt_tiles = 4}},
}
