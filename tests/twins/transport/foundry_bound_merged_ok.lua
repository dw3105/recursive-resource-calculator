--Round 52 integration (2026-09-30): same layout as fluid_flipped_one_other_ok (flipped foundry, casting-iron, pipe on
--the SPARE connection, engine ok: runtime box 1 merges prototype boxes 1 and 2, conns=2) but with the Box binding
--in the catalog: molten-iron -> prototype boxes {1, 2}. The validator must pin to the whole set; a binding kept as
--the lowest box only (box 1) would reject this engine-valid layout.
--Round 51 STEP 0 (engine table tests/fixtures/flip_fluidboxes_2.0.txt / _2.1.txt, identical): foundry 5x5 at tiles
--x=3..7, y=3..7 (centre 5.5,5.5), dir north, mirror = true (Flip), recipe casting-iron (one fluid: molten-iron in
--box 1). Box 1 north unflipped: pos (-1,2) target (-1,3); a Flip mirrors x in the machine frame -> target (1,3).
--Pipe column x=4, y=8..19: the OTHER south spot (-1,3) = tile (4,8). Engine filter rows (headless 2.0.77 + 2.1.20,
--2026-09-30): a one-fluid recipe merges the spare box connection into box 1 (conns=2), so this feeds too: ok.
--Engine: molten-iron fed at (4,19); the machine must hold molten-iron after the run (fluid_system).
local entities = {{id = "machine", kind = "machine", name = "foundry", x = 3, y = 3, w = 5, h = 5, dir = "north",
    mirror = true, recipe = "casting-iron", step_id = "cast"}}
for y = 8, 19 do
    entities[#entities + 1] = {id = "pipe" .. y, kind = "pipe", name = "pipe", x = 4, y = y, flows = {"fluid/molten-iron"},
        flow_id = "fluid/molten-iron"}
end
return {
 id = "foundry_bound_merged_ok", rule = "BP_V_FLUID_DISCONNECTED", class = "engine", from = "round 52 Box binding (merged runtime box)",
 grid = {w = 20, h = 20},
 entities = entities,
 validator = {
  catalog = {entity = {foundry = {name = "foundry", etype = "assembling-machine", tile_w = 5, tile_h = 5,
      needs_power = false, module_slots = 4, can_flip = true, fluid_boxes = {
      {production_type = "input", index = 1, connections = {{connection_type = "normal", flow_direction = "input", direction = 8,
          positions = {{x = -1, y = 2}, {x = -2, y = -1}, {x = 1, y = -2}, {x = 2, y = 1}}}}},
      {production_type = "input", index = 2, connections = {{connection_type = "normal", flow_direction = "input", direction = 8,
          positions = {{x = 1, y = 2}, {x = -2, y = 1}, {x = -1, y = -2}, {x = 2, y = -1}}}}}}}},
      recipe = {["casting-iron"] = {name = "casting-iron", ingredients = {{type = "fluid", name = "molten-iron", amount = 10}},
          products = {}, fluid_boxes = {foundry = {["molten-iron"] = {box = 1, boxes = {1, 2}, role = "input"}}}}}},
  plan = {steps = {{step_id = "cast", machine = "foundry", machine_count = 1, recipe = "casting-iron",
      inputs = {{full_name = "fluid/molten-iron", rate_per_second = 10, kind = "fluid", is_fluid = true}}}}},
  flows = {{flow_id = "fluid/molten-iron", is_fluid = true}},
  ports = {{port_id = "iron-port", flow_id = "fluid/molten-iron", role = "in", x = 4, y = 19, kind = "fluid", rate_per_second = 10},
      {port_id = "cast-iron", flow_id = "fluid/molten-iron", role = "in", x = 4, y = 8, kind = "fluid", step_id = "cast", rate_per_second = 10}},
  bindings = {{source_port_id = "iron-port", sink_port_id = "cast-iron", flow_id = "fluid/molten-iron", sink = "step:cast", rate_per_second = 10}},
 },
 feeds = {{tile = {4, 19}, fluid = "molten-iron"}},
 check = "fluid_system", truth = "ok", codes = {},
 audit = {blueprint_audit = {unused_pipe_tiles = 0}},
}
