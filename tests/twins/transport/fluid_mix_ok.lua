--Round 48 fix loop (physical rewrite): same lines with a gap at x=4: two systems.
--Engine: water fed at (0,3), steam at (19,3); a joined system holds one fluid, so a pipe declared for the other
--flow carries a foreign fluid (defect).
local entities = {}
for x = 0, 3 do entities[#entities + 1] = {id = "w" .. x, kind = "pipe", name = "pipe", x = x, y = 3, flows = {"fluid/water"}, flow_id = "fluid/water"} end
for x = 5, 19 do entities[#entities + 1] = {id = "s" .. x, kind = "pipe", name = "pipe", x = x, y = 3, flows = {"fluid/steam"}, flow_id = "fluid/steam"} end
return {
 id = "fluid_mix_ok", rule = "BP_V_FLUID_MIX", class = "engine", from = "tests/test_validate_fluid_mix.lua adjacent foreign pipes",
 grid = {w = 20, h = 20},
 entities = entities,
 feeds = {{tile = {0, 3}, fluid = "water"}, {tile = {19, 3}, fluid = "steam"}},
 check = "fluid_system", truth = "ok", codes = {},
 audit = {},
}
