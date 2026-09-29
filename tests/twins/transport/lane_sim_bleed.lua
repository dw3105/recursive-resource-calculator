return {
 id = "lane_sim_bleed", rule = "audit:lane_sim:bleed", class = "engine", from = "tests/test_validate.lua S1 transport waste with recipe-visible bleed",
 grid = {w = 12, h = 10},
 entities = {
  {id = "source-machine", kind = "machine", name = "assembling-machine-1", x = 2, y = 3, recipe = "source-copper", needs_power = false},
  {id = "source-hand", kind = "inserter", name = "inserter", x = 2, y = 4, dir = "south", role = "output", flow_id = "item/copper-plate", pickup_position = {x = 2.5, y = 3.5}, drop_position = {x = 2.5, y = 5.5}, needs_power = false},
  {id = "belt0", kind = "belt", name = "transport-belt", x = 0, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt1", kind = "belt", name = "transport-belt", x = 1, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt2", kind = "belt", name = "transport-belt", x = 2, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt3", kind = "belt", name = "transport-belt", x = 3, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt4", kind = "belt", name = "transport-belt", x = 4, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt5", kind = "belt", name = "transport-belt", x = 5, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "consumer-hand", kind = "inserter", name = "inserter", x = 6, y = 5, dir = "east", role = "input", flow_id = "item/copper-plate", pickup_position = {x = 5.5, y = 5.5}, drop_position = {x = 7.5, y = 5.5}, needs_power = false},
  {id = "consumer-machine", kind = "machine", name = "assembling-machine-1", x = 7, y = 5, recipe = "iron-gear-wheel", needs_power = false},
 },
 feeds = {{tile = {0, 5}, item = "copper-plate"}},
 validator = {catalog = {
  inserter = {items_per_second = 10, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
  entity = {inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 10}, ["assembling-machine-1"] = {name = "assembling-machine-1", etype = "assembling-machine", tile_w = 1, tile_h = 1, needs_power = false}},
  recipe = { ["source-copper"] = {ingredients = {}, products = {{name = "copper-plate"}}}, ["iron-gear-wheel"] = {ingredients = {{name = "iron-plate"}}, products = {{name = "iron-gear-wheel"}}} },
 }},
 check = "flow_purity", truth = "ok", codes = {}, audit = {lane_sim = {mixed = 1, starved = 0, bleed = 1}},
}
