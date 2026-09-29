return {
 id = "route_loop_ok", rule = "BP_V_ROUTE_LOOP", class = "engine", from = "tests/test_validate_transport_shapes.lua TS4 directed ring",
 grid = {w = 20, h = 20},
 entities = {
  {id = "s1", kind = "belt", name = "transport-belt", x = 0, y = 1, dir = "east", flows = {"iron-plate"}},
  {id = "s2", kind = "belt", name = "transport-belt", x = 1, y = 1, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 1}, item = "iron-plate"}},
 check = "flow_purity", truth = "ok", codes = {},
 audit = {blueprint_audit = {cycles = 0}},
}
