return {
 id = "belt_no_source_ok", rule = "BP_V_BELT_NO_SOURCE", class = "engine", from = "tests/test_validate_belt_no_source.lua frozen source-less stub",
 grid = {w = 20, h = 20},
 entities = {
  {id = "source", kind = "belt", name = "transport-belt", x = 0, y = 4, dir = "east", flows = {"iron-plate"}},
  {id = "fed", kind = "belt", name = "transport-belt", x = 1, y = 4, dir = "east", flows = {"iron-plate"}},
 },
 feeds = {{tile = {0, 4}, item = "iron-plate"}},
 check = "flow_purity", truth = "ok", codes = {},
 audit = {blueprint_audit = {unused_belt_tiles = 0}},
}
