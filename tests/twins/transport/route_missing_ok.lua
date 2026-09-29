return {
 id = "route_missing_ok", rule = "BP_V_ROUTE_MISSING", class = "engine", from = "tests/test_physical_witness.lua WI4 candidate no transport",
 grid = {w = 20, h = 20},
 entities = {
  {id = "line", kind = "belt", name = "transport-belt", x = 0, y = 1, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 1}, item = "iron-plate"}},
 check = "flow_purity", truth = "ok", codes = {},
 audit = {},
}
