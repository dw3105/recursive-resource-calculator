--Round 51 STEP 0 (engine table tests/fixtures/flip_fluidboxes_2.0.txt / _2.1.txt, identical): foundry 5x5 at tiles
--x=3..7, y=3..7 (centre 5.5,5.5), dir north, mirror = true (Flip), recipe casting-iron (one fluid: molten-iron in
--box 1). Box 1 north unflipped: pos (-1,2) target (-1,3); a Flip mirrors x in the machine frame -> target (1,3).
--Pipe column x=6, y=8..19: MIRRORED target (1,3) from centre = tile (6,8).
--Engine: molten-iron fed at (6,19); the machine must hold molten-iron after the run (fluid_system).
local entities = {{id = "machine", kind = "machine", name = "foundry", x = 3, y = 3, w = 5, h = 5, dir = "north",
    mirror = true, recipe = "casting-iron", step_id = "cast"}}
for y = 8, 19 do
    entities[#entities + 1] = {id = "pipe" .. y, kind = "pipe", name = "pipe", x = 6, y = y, flows = {"fluid/molten-iron"},
        flow_id = "fluid/molten-iron"}
end
return {
 id = "fluid_flipped_ok", rule = "BP_V_FLUID_DISCONNECTED", class = "engine", from = "round 51 Flip (docs/tasks/287_machine_turn_flip.md)",
 grid = {w = 20, h = 20},
 entities = entities,
 validator = {
  catalog = {entity = {foundry = {name = "foundry", etype = "assembling-machine", tile_w = 5, tile_h = 5,
      needs_power = false, module_slots = 4, can_flip = true, fluid_boxes = {
      {production_type = "input", index = 1, connections = {{connection_type = "normal", flow_direction = "input", direction = 8,
          positions = {{x = -1, y = 2}, {x = -2, y = -1}, {x = 1, y = -2}, {x = 2, y = 1}}}}},
      {production_type = "input", index = 2, connections = {{connection_type = "normal", flow_direction = "input", direction = 8,
          positions = {{x = 1, y = 2}, {x = -2, y = 1}, {x = -1, y = -2}, {x = 2, y = -1}}}}}}}}},
  plan = {steps = {{step_id = "cast", machine = "foundry", machine_count = 1, recipe = "casting-iron",
      inputs = {{full_name = "fluid/molten-iron", rate_per_second = 10, kind = "fluid", is_fluid = true}}}}},
  flows = {{flow_id = "fluid/molten-iron", is_fluid = true}},
  ports = {{port_id = "iron-port", flow_id = "fluid/molten-iron", role = "in", x = 6, y = 19, kind = "fluid", rate_per_second = 10},
      {port_id = "cast-iron", flow_id = "fluid/molten-iron", role = "in", x = 6, y = 8, kind = "fluid", step_id = "cast", rate_per_second = 10}},
  bindings = {{source_port_id = "iron-port", sink_port_id = "cast-iron", flow_id = "fluid/molten-iron", sink = "step:cast", rate_per_second = 10}},
 },
 feeds = {{tile = {6, 19}, fluid = "molten-iron"}},
 check = "fluid_system", truth = "ok", codes = {},
 audit = {blueprint_audit = {unused_pipe_tiles = 0}},
}
