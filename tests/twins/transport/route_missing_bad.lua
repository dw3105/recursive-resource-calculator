return {
 id = "route_missing_bad", rule = "BP_V_ROUTE_MISSING", class = "engine", from = "tests/test_physical_witness.lua WI4 candidate no transport",
 grid = {w = 20, h = 20},
 entities = {
  {id = "line", kind = "belt", name = "transport-belt", x = 0, y = 1, dir = "east", flow_id = "item/iron-plate"},
  {id = "demand", kind = "belt", name = "transport-belt", x = 19, y = 1, dir = "east", flow_id = "item/iron-plate"},
 },
 feeds = {{tile = {0, 1}, item = "iron-plate"}},
 --iron is supplied at (0,1) and wanted at (19,1), but no route joins them: the demand belt never receives iron.
 sinks = {{tile = {19, 1}, items = {"iron-plate"}}},
 validator = {catalog = {entity = {}, belt = {items_per_second = 15}}, flows = {{flow_id = "item/iron-plate", supplied = 1, removed = 1}}},
 check = "flow_purity", truth = "defect", codes = {"BP_V_ROUTE_MISSING"},
 audit = {},
}
