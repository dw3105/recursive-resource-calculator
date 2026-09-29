--A source machine's output hand drops copper-cable onto the copper-plate belt that feeds a gear machine: lane_sim
--counts the cable as bleed at the gear hand's pickup. The validator stays silent (codes {}), and in the engine the
--source machine has no copper to make cable, so the belt carries only its feed: truth ok.
return {
 id = "lane_sim_bleed", rule = "audit:lane_sim:bleed", class = "engine", from = "tests/test_validate.lua S1 transport waste with recipe-visible bleed",
 grid = {w = 12, h = 10},
 entities = {
  {id = "source-machine", kind = "machine", name = "assembling-machine-1", x = 1, y = 1, w = 3, h = 3, recipe = "copper-cable", needs_power = false},
  {id = "source-hand", kind = "inserter", name = "inserter", x = 2, y = 4, dir = "south", role = "output", pickup_position = {x = 2.5, y = 3.5}, drop_position = {x = 2.5, y = 5.5}, needs_power = false},
  {id = "belt0", kind = "belt", name = "transport-belt", x = 0, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt1", kind = "belt", name = "transport-belt", x = 1, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt2", kind = "belt", name = "transport-belt", x = 2, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt3", kind = "belt", name = "transport-belt", x = 3, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt4", kind = "belt", name = "transport-belt", x = 4, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt5", kind = "belt", name = "transport-belt", x = 5, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt6", kind = "belt", name = "transport-belt", x = 6, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "belt7", kind = "belt", name = "transport-belt", x = 7, y = 5, dir = "east", flow_id = "item/copper-plate"},
  {id = "consumer-hand", kind = "inserter", name = "inserter", x = 8, y = 5, dir = "east", role = "input", pickup_position = {x = 7.5, y = 5.5}, drop_position = {x = 9.5, y = 5.5}, needs_power = false},
  {id = "consumer-machine", kind = "machine", name = "assembling-machine-1", x = 9, y = 4, w = 3, h = 3, recipe = "iron-gear-wheel", needs_power = false},
  {id = "power", kind = "pole", name = "substation", x = 5, y = 7, w = 2, h = 2},
 },
 feeds = {{tile = {0, 5}, item = "copper-plate"}},
 validator = {catalog = {
  inserter = {items_per_second = 10, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
  entity = {inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 10},
   ["assembling-machine-1"] = {name = "assembling-machine-1", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = false},
   substation = {name = "substation", etype = "electric-pole", tile_w = 2, tile_h = 2, supply_w = 9, supply_h = 9, wire_reach = 18, needs_power = false}},
  recipe = {["copper-cable"] = {ingredients = {{name = "copper-plate"}}, products = {{name = "copper-cable"}}}, ["iron-gear-wheel"] = {ingredients = {{name = "iron-plate"}}, products = {{name = "iron-gear-wheel"}}}},
 }},
 check = "flow_purity", truth = "ok", codes = {}, audit = {lane_sim = {mixed = 1, starved = 0, bleed = 1}},
}
