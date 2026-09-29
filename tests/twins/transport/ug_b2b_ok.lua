return {
 id = "ug_b2b_ok", rule = "BP_V_UNDERGROUND_BACK_TO_BACK", class = "engine", from = "tests/test_validate_transport_shapes.lua TS3 tunnels",
 grid = {w = 20, h = 20},
 entities = {
  {id = "a-in", kind = "belt", name = "underground-belt", x = 1, y = 1, dir = "east", type = "input", ug_role = "input", ug_pair_id = "a-out"},
  {id = "a-out", kind = "belt", name = "underground-belt", x = 5, y = 1, dir = "east", type = "output", ug_role = "output", ug_pair_id = "a-in"},
 },
 check = "underground_pair", truth = "ok", codes = {},
 audit = {blueprint_audit = {back_to_back = 0}},
}
