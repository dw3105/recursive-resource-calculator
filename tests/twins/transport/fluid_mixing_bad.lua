return {
 id = "fluid_mixing_bad", rule = "BP_V_FLUID_MIXING", class = "engine", from = "tests/test_route_layout_contract.lua L5 two fluids on one pipe",
 grid = {w = 20, h = 20},
 entities = {
  {id = "a", kind = "pipe", name = "pipe", x = 1, y = 1, flow_id = "fluid/water"},
  {id = "b", kind = "pipe", name = "pipe", x = 10, y = 10, flow_id = "fluid/steam"},
 },
 validator = {catalog = {entity = {}, pipe = {throughput_per_second = 100}}, segments = {{segment_id = "one-network", kind = "pipe", capacity_per_second = 100, allocations = {{flow_id = "fluid/water", sink = "water", rate_per_second = 1}, {flow_id = "fluid/steam", sink = "steam", rate_per_second = 1}}}}},
 check = "fluid_system", truth = "defect", codes = {"BP_V_FLUID_MIXING"},
 audit = {},
}
