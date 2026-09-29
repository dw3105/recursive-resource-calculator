--Two splitters back to back: the second splits what the first already split. Nothing feeds the pair, so in the
--engine both carry no item (waste); the validator names the redundant second splitter.
return {
 id = "splitter_chain_bad", rule = "BP_V_SPLITTER_CHAIN", class = "waste", from = "tests/test_validate_splitter_chain.lua frozen consecutive splitter junk",
 grid = {w = 40, h = 40},
 entities = {
  {id = "sp1", kind = "splitter", flows = {"iron-plate"}, name = "splitter", x = 31, y = 16, w = 1, h = 2, dir = "east"},
  {id = "sp2", kind = "splitter", flows = {"iron-plate"}, name = "splitter", x = 32, y = 16, w = 1, h = 2, dir = "east"},
 },
 check = "flow_purity", truth = "waste", codes = {"BP_V_SPLITTER_CHAIN"},
 audit = {},
}
