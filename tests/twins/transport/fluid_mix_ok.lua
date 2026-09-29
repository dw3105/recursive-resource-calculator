return {
 id = "fluid_mix_ok", rule = "BP_V_FLUID_MIX", class = "engine", from = "tests/test_validate_fluid_mix.lua adjacent foreign pipes",
 grid = {w = 20, h = 20},
 entities = {
  {id = "a", kind = "pipe", name = "pipe", x = 3, y = 3, flow_id = "fluid/water"},
  {id = "b", kind = "pipe", name = "pipe", x = 4, y = 3, flow_id = "fluid/water"},
 },
 check = "fluid_system", truth = "ok", codes = {},
 audit = {},
}
