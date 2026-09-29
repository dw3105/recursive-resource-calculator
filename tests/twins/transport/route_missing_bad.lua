return {
 id = "route_missing_bad", rule = "BP_V_ROUTE_MISSING", class = "engine", from = "tests/test_physical_witness.lua WI4 candidate no transport",
 grid = {w = 20, h = 20},
 entities = {
  {id = "line", kind = "belt", name = "transport-belt", x = 0, y = 1, dir = "east", flow_id = "item/plate"},
 },
 feeds = {{tile = {0, 1}, item = "iron-plate"}},
 validator = {catalog = {entity = {}, belt = {items_per_second = 15}}, flows = {{flow_id = "item/plate", supplied = 1, removed = 1}}},
 check = "flow_purity", truth = "defect", codes = {"BP_V_ROUTE_MISSING"},
 audit = {},
}
