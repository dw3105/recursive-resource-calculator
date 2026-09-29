return {
 id = "ug_unpaired_ok", rule = "BP_V_UNDERGROUND_UNPAIRED", class = "engine", from = "tests/test_route_layout_contract.lua L2 direction control",
 grid = {w = 20, h = 20},
 entities = {
  {id = "a", kind = "belt", name = "underground-belt", x = 1, y = 2, dir = "east", type = "input", ug_role = "input", ug_pair_id = "b", flow_id = "item/cross"},
  {id = "b", kind = "belt", name = "underground-belt", x = 3, y = 2, dir = "east", type = "output", ug_role = "output", ug_pair_id = "a", flow_id = "item/cross"},
 },
 check = "underground_pair", truth = "ok", codes = {},
 audit = {blueprint_audit = {unpairable_underground_belt = 0}},
}
