return {
 id = "ug_range_ok", rule = "BP_V_UNDERGROUND_RANGE", class = "engine", from = "tests/test_validate.lua V11 over-range pair",
 grid = {w = 20, h = 20},
 entities = {
  {id = "a", kind = "belt", name = "underground-belt", x = 0, y = 0, dir = "east", type = "input", ug_role = "input", ug_pair_id = "b"},
  {id = "b", kind = "belt", name = "underground-belt", x = 3, y = 0, dir = "east", type = "output", ug_role = "output", ug_pair_id = "a"},
 },
 validator = {catalog = {entity = {}, belt = {underground_max_distance = 3}}},
 check = "underground_pair", truth = "ok", codes = {},
 audit = {},
}
