--Round 51 integration (engine filter rows, tests/game/test_flip_fluidboxes.lua, headless 2.0.77 + 2.1.20, 2026-09-30):
--foundry 5x5 at tiles x=3..7, y=3..7 (centre 5.5,5.5), dir north, mirror = true, recipe casting-low-density-structure
--(two fluids fill both input boxes: box 1 molten-iron, box 2 molten-copper, one connection each). Unflipped: box 1
--pos (-1,2), box 2 pos (1,2); a Flip mirrors x -> box 1 (1,2), box 2 (-1,2). Pipe columns x=6 (iron) and x=4
--(copper), y=8..19: iron on the FLIPPED box 1 spot (1,3) = tile (6,8), copper on flipped box 2 (-1,3) = tile (4,8): ok.
local IRON_X, COPPER_X = 6, 4
local entities = {{id = "machine", kind = "machine", name = "foundry", x = 3, y = 3, w = 5, h = 5, dir = "north",
    mirror = true, recipe = "casting-low-density-structure", step_id = "cast"}}
for y = 8, 19 do
    entities[#entities + 1] = {id = "iron" .. y, kind = "pipe", name = "pipe", x = IRON_X, y = y, flows = {"fluid/molten-iron"},
        flow_id = "fluid/molten-iron"}
    entities[#entities + 1] = {id = "copper" .. y, kind = "pipe", name = "pipe", x = COPPER_X, y = y,
        flows = {"fluid/molten-copper"}, flow_id = "fluid/molten-copper"}
end
return {
 id = "fluid_flipped_two_ok", rule = "BP_V_FLUID_DISCONNECTED", class = "engine", from = "round 51 Flip (engine filter rows)",
 grid = {w = 20, h = 20},
 entities = entities,
 validator = {
  catalog = {entity = {foundry = {name = "foundry", etype = "assembling-machine", tile_w = 5, tile_h = 5,
      needs_power = false, module_slots = 4, can_flip = true, fluid_boxes = {
      {production_type = "input", index = 1, connections = {{connection_type = "normal", flow_direction = "input", direction = 8,
          positions = {{x = -1, y = 2}, {x = -2, y = -1}, {x = 1, y = -2}, {x = 2, y = 1}}}}},
      {production_type = "input", index = 2, connections = {{connection_type = "normal", flow_direction = "input", direction = 8,
          positions = {{x = 1, y = 2}, {x = -2, y = 1}, {x = -1, y = -2}, {x = 2, y = -1}}}}}}}}},
  plan = {steps = {{step_id = "cast", machine = "foundry", machine_count = 1, recipe = "casting-low-density-structure",
      inputs = {{full_name = "fluid/molten-iron", rate_per_second = 10, kind = "fluid", is_fluid = true},
          {full_name = "fluid/molten-copper", rate_per_second = 10, kind = "fluid", is_fluid = true}}}}},
  flows = {{flow_id = "fluid/molten-iron", is_fluid = true}, {flow_id = "fluid/molten-copper", is_fluid = true}},
  ports = {{port_id = "iron-port", flow_id = "fluid/molten-iron", role = "in", x = IRON_X, y = 19, kind = "fluid", rate_per_second = 10},
      {port_id = "copper-port", flow_id = "fluid/molten-copper", role = "in", x = COPPER_X, y = 19, kind = "fluid", rate_per_second = 10},
      {port_id = "cast-iron", flow_id = "fluid/molten-iron", role = "in", x = IRON_X, y = 8, kind = "fluid", step_id = "cast", rate_per_second = 10},
      {port_id = "cast-copper", flow_id = "fluid/molten-copper", role = "in", x = COPPER_X, y = 8, kind = "fluid", step_id = "cast", rate_per_second = 10}},
  bindings = {{source_port_id = "iron-port", sink_port_id = "cast-iron", flow_id = "fluid/molten-iron", sink = "step:cast", rate_per_second = 10},
      {source_port_id = "copper-port", sink_port_id = "cast-copper", flow_id = "fluid/molten-copper", sink = "step:cast", rate_per_second = 10}},
 },
 feeds = {{tile = {IRON_X, 19}, fluid = "molten-iron"}, {tile = {COPPER_X, 19}, fluid = "molten-copper"}},
 check = "fluid_system", truth = "ok", codes = {},
 audit = {blueprint_audit = {unused_pipe_tiles = 0}},
}
