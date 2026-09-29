return {
 id = "transport_unused_ok", rule = "BP_V_TRANSPORT_UNUSED", class = "waste", from = "tests/test_validate.lua orphan-belt",
 grid = {w = 20, h = 20},
 entities = {
  {id = "line", kind = "belt", name = "transport-belt", x = 0, y = 4, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 4}, item = "iron-plate"}},
 check = "flow_purity", truth = "ok", codes = {},
 audit = {},
}
