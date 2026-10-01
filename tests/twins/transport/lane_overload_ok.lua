--Round 54 physical twin (Factorio 2.0.77, plastic x4 Turn 8: 7.5/s of 7.992/s): two branches of 5 items/s each join an
--east trunk. One side-loads from the north, one from the south: 5/s on each lane.
--Pair: lane_overload_bad (breach) / lane_overload_ok (clean). The hands tell the validator the rates; the edge feeds
--play the machines in the engine.
local entities = {}
local function belt(id, x, y, dir) entities[#entities + 1] = {id = id, kind = "belt", name = "transport-belt", x = x, y = y, dir = dir, flows = {"iron-gear-wheel"}} end
for x = 0, 19 do belt("t" .. x, x, 10, "east") end
for y = 0, 9 do belt("b" .. y, 5, y, "south") end
for y = 11, 19 do belt("c" .. y, 9, y, "north") end
entities[#entities + 1] = {id = "machine-b", kind = "machine", name = "assembling-machine-1", x = 1, y = 3, w = 3, h = 3, recipe = "iron-gear-wheel"}
entities[#entities + 1] = {id = "hand-b", kind = "inserter", name = "inserter", x = 4, y = 4, dir = "east", role = "output", flow_ids = {"item/iron-gear-wheel"}, rate_per_second = 5, pickup_position = {x = 3.5, y = 4.5}, drop_position = {x = 5.5, y = 4.5}}
entities[#entities + 1] = {id = "machine-c", kind = "machine", name = "assembling-machine-1", x = 11, y = 14, w = 3, h = 3, recipe = "iron-gear-wheel"}
entities[#entities + 1] = {id = "hand-c", kind = "inserter", name = "inserter", x = 10, y = 15, dir = "west", role = "output", flow_ids = {"item/iron-gear-wheel"}, rate_per_second = 5, pickup_position = {x = 11.5, y = 15.5}, drop_position = {x = 9.5, y = 15.5}}
return {
 id = "lane_overload_ok", rule = "BP_V_LANE_OVERLOAD", class = "engine", from = "tests/test_validate_lane_overload.lua LO1",
 grid = {w = 20, h = 20}, entities = entities,
 feeds = {{tile = {5, 0}, item = "iron-gear-wheel", rate = 5}, {tile = {9, 19}, item = "iron-gear-wheel", rate = 5}},
 sinks = {{tile = {19, 10}, items = {"iron-gear-wheel"}, rate = 10}},
 validator = {catalog = {entity = {
  inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = false, items_per_second = 10},
  ["assembling-machine-1"] = {name = "assembling-machine-1", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = false},
}, inserter = {name = "inserter", belt_stack_size = 1, items_per_second = 10, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}, belt = {items_per_second = 15, lane_items_per_second = 7.5},
  recipe = {["iron-gear-wheel"] = {ingredients = {{name = "iron-plate"}}, products = {{name = "iron-gear-wheel"}}}}}},
 check = "rate", truth = "ok", codes = {}, audit = {},
}
