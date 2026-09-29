return {
 id = "ug_sideload_ok", rule = "BP_V_UNDERGROUND_SIDELOAD_BLOCKED", class = "engine", from = "tests/test_validate_transport_shapes.lua TS2b blocked lane",
 grid = {w = 20, h = 20},
 entities = {
  {id = "straight", kind = "belt", name = "transport-belt", x = 0, y = 4, dir = "east", flows = {"iron-plate"}},
  {id = "in", kind = "belt", name = "underground-belt", x = 1, y = 4, dir = "east", type = "input", ug_role = "input", ug_pair_id = "out"},
  {id = "out", kind = "belt", name = "underground-belt", x = 7, y = 4, dir = "east", type = "output", ug_role = "output", ug_pair_id = "in"},
 },
 feeds = {{tile = {0, 4}, item = "iron-plate"}},
 check = "underground_pair", truth = "ok", codes = {},
 audit = {blueprint_audit = {sideload_blocked = 0}},
}
