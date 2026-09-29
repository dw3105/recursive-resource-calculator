return {
 id = "belt_no_source_bad", rule = "BP_V_BELT_NO_SOURCE", class = "engine", from = "tests/test_validate_belt_no_source.lua frozen source-less stub",
 grid = {w = 20, h = 20},
 entities = {
  {id = "orphan", kind = "belt", name = "transport-belt", x = 4, y = 4, dir = "east", flows = {"iron-plate"}},
 },
 --nothing feeds the stub: the engine reads it as a sink that never receives iron (no feed, no belt on the edge).
 sinks = {{tile = {4, 4}, items = {"iron-plate"}}},
 check = "flow_purity", truth = "defect", codes = {"BP_V_BELT_NO_SOURCE"},
 audit = {blueprint_audit = {unused_belt_tiles = 1}},
}
