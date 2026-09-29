return {
 id = "ug_b2b_bad", rule = "audit:blueprint_audit:back_to_back", class = "player", from = "tests/test_validate_transport_shapes.lua TS3 tunnels",
 grid = {w = 20, h = 20},
 entities = {
  {id = "a-in", kind = "belt", name = "underground-belt", x = 1, y = 1, dir = "east", type = "input", ug_role = "input", ug_pair_id = "a-out"},
  {id = "a-out", kind = "belt", name = "underground-belt", x = 3, y = 1, dir = "east", type = "output", ug_role = "output", ug_pair_id = "a-in"},
  {id = "b-in", kind = "belt", name = "underground-belt", x = 4, y = 1, dir = "east", type = "input", ug_role = "input", ug_pair_id = "b-out"},
  {id = "b-out", kind = "belt", name = "underground-belt", x = 5, y = 1, dir = "east", type = "output", ug_role = "output", ug_pair_id = "b-in"},
 },
 --Engine (headless 2.0.77 + 2.1.20): both pairs pair as planned; the code is the player's layout rule.
 check = "underground_pair", truth = "ok", codes = {"BP_V_UNDERGROUND_BACK_TO_BACK"},
 audit = {blueprint_audit = {back_to_back = 1}},
}
