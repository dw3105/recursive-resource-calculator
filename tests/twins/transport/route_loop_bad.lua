--Flow iron-plate enters at the left edge and should leave at the right edge (4,1), but the route turns into a
--directed ring (1,1) -> (2,1) -> (2,2) -> (1,2) -> (1,1): items circle forever and the exit belt starves.
return {
 id = "route_loop_bad", rule = "BP_V_ROUTE_LOOP", class = "engine", from = "tests/test_validate_transport_shapes.lua TS4 directed ring",
 grid = {w = 5, h = 5},
 entities = {
  {id = "s0", kind = "belt", name = "transport-belt", x = 0, y = 1, dir = "east", flows = {"iron-plate"}},
  {id = "r0", kind = "belt", name = "transport-belt", x = 1, y = 1, dir = "east", flows = {"iron-plate"}},
  {id = "r1", kind = "belt", name = "transport-belt", x = 2, y = 1, dir = "south", flows = {"iron-plate"}},
  {id = "r2", kind = "belt", name = "transport-belt", x = 2, y = 2, dir = "west", flows = {"iron-plate"}},
  {id = "r3", kind = "belt", name = "transport-belt", x = 1, y = 2, dir = "north", flows = {"iron-plate"}},
  {id = "exit", kind = "belt", name = "transport-belt", x = 4, y = 1, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 1}, item = "iron-plate"}},
 sinks = {{tile = {4, 1}, items = {"iron-plate"}}},
 check = "flow_purity", truth = "defect", codes = {"BP_V_ROUTE_LOOP"},
 audit = {blueprint_audit = {cycles = 1}},
}
