return {
 id = "splitter_chain_bad", rule = "BP_V_SPLITTER_CHAIN", class = "waste", from = "tests/test_validate_splitter_chain.lua frozen consecutive splitter junk",
 grid = {w = 40, h = 40},
 entities = {
  {id = "sp1", kind = "splitter", flows = {"iron-plate"}, name = "fast-splitter", x = 31, y = 16, dir = "east"},
  {id = "sp2", kind = "splitter", flows = {"iron-plate"}, name = "fast-splitter", x = 32, y = 16, dir = "east"},
 },
 feeds = {{tile = {0, 2}, item = "iron-plate"}},
 check = "flow_purity", truth = "waste", codes = {"BP_V_SPLITTER_CHAIN"},
 audit = {},
}
