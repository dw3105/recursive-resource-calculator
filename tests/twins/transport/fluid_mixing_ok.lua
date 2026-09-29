return {
 id = "fluid_mixing_ok", rule = "BP_V_FLUID_MIXING", class = "engine", from = "tests/test_route_layout_contract.lua L5 two fluids on one pipe",
 grid = {w = 20, h = 20},
 entities = {
  {id = "a", kind = "pipe", name = "pipe", x = 1, y = 1, flow_id = "fluid/water"},
  {id = "b", kind = "pipe", name = "pipe", x = 10, y = 10, flow_id = "fluid/water"},
 },
 check = "fluid_system", truth = "ok", codes = {},
 audit = {},
}
