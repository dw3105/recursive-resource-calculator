return {
 id = "route_loop_bad", rule = "BP_V_ROUTE_LOOP", class = "engine", from = "tests/test_validate_transport_shapes.lua TS4 directed ring",
 grid = {w = 20, h = 20},
 entities = {
  {id = "r0", kind = "belt", name = "transport-belt", x = 1, y = 1, dir = "east", flows = {"iron-plate"}},
  {id = "r1", kind = "belt", name = "transport-belt", x = 2, y = 1, dir = "south", flows = {"iron-plate"}},
  {id = "r2", kind = "belt", name = "transport-belt", x = 2, y = 2, dir = "west", flows = {"iron-plate"}},
  {id = "r3", kind = "belt", name = "transport-belt", x = 1, y = 2, dir = "north", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 1}, item = "iron-plate"}},
 check = "flow_purity", truth = "defect", codes = {"BP_V_ROUTE_LOOP"},
 audit = {blueprint_audit = {cycles = 1}},
}
