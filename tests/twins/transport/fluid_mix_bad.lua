--Round 48 fix loop (physical rewrite): water pipes 0..3 touch steam pipes 4..19 on y=3: the engine joins them into one fluid system.
--Engine: water fed at (0,3), steam at (19,3); a joined system holds one fluid, so a pipe declared for the other
--flow carries a foreign fluid (defect).
local entities = {}
for x = 0, 3 do entities[#entities + 1] = {id = "w" .. x, kind = "pipe", name = "pipe", x = x, y = 3, flows = {"fluid/water"}, flow_id = "fluid/water"} end
for x = 4, 19 do entities[#entities + 1] = {id = "s" .. x, kind = "pipe", name = "pipe", x = x, y = 3, flows = {"fluid/steam"}, flow_id = "fluid/steam"} end
return {
 id = "fluid_mix_bad", rule = "BP_V_FLUID_MIX", class = "engine", from = "tests/test_validate_fluid_mix.lua adjacent foreign pipes",
 grid = {w = 20, h = 20},
 entities = entities,
 feeds = {{tile = {0, 3}, fluid = "water"}, {tile = {19, 3}, fluid = "steam"}},
 check = "fluid_system", truth = "defect", codes = {"BP_V_FLUID_MIX"},
 audit = {},
}
