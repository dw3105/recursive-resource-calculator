return {
 id = "lane_mix_ok", rule = "BP_V_LANE_MIX", class = "engine", from = "tests/test_validate_bleed.lua lane-mix",
 grid = {w = 20, h = 20},
 entities = {
  {id = "clean-a", kind = "belt", name = "transport-belt", x = 0, y = 2, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 2}, item = "iron-plate"}},
 check = "flow_purity", truth = "ok", codes = {},
 audit = {},
}
