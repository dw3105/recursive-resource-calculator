return {
 id = "splitter_chain_ok", rule = "BP_V_SPLITTER_CHAIN", class = "waste", from = "tests/test_validate_splitter_chain.lua frozen consecutive splitter junk",
 grid = {w = 20, h = 20},
 entities = {
  {id = "clean", kind = "belt", name = "transport-belt", x = 0, y = 2, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 2}, item = "iron-plate"}},
 check = "flow_purity", truth = "ok", codes = {},
 audit = {},
}
