--Round 48 fix loop (physical rewrite): assembling-machine-3 on concrete (needs water) at x=3..5, y=3..5; its
--north-facing fluid input sits at the top edge centre, so the connecting pipe tile is (4,2). pipe missing at (2,2): the machine never gets water.
--Engine: water fed at (0,2); the machine must hold water after the run (fluid_system).
local entities = {{id = "machine", kind = "machine", name = "assembling-machine-3", x = 3, y = 3, w = 3, h = 3, dir = "north",
    recipe = "concrete", step_id = "mix"}}
for _, x in ipairs({0, 1, 3, 4}) do
    entities[#entities + 1] = {id = "pipe" .. x, kind = "pipe", name = "pipe", x = x, y = 2, flows = {"fluid/water"}, flow_id = "fluid/water"}
end
return {
 id = "fluid_disconnected_bad", rule = "BP_V_FLUID_DISCONNECTED", class = "engine", from = "tests/test_red_green_fluid_ports.lua water port",
 grid = {w = 20, h = 20},
 entities = entities,
 validator = {
  catalog = {entity = {["assembling-machine-3"] = {name = "assembling-machine-3", etype = "assembling-machine", tile_w = 3, tile_h = 3,
      needs_power = false, module_slots = 4, fluid_boxes = {{production_type = "input", index = 1,
      connections = {{connection_type = "normal", flow_direction = "input", direction = 0, positions = {{x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0}}}}}}}}},
  plan = {steps = {{step_id = "mix", machine = "assembling-machine-3", machine_count = 1, recipe = "concrete",
      inputs = {{full_name = "fluid/water", rate_per_second = 10, kind = "fluid", is_fluid = true}}}}},
  flows = {{flow_id = "fluid/water", is_fluid = true}},
  ports = {{port_id = "water-port", flow_id = "fluid/water", role = "in", x = 0, y = 2, kind = "fluid", rate_per_second = 10},
      {port_id = "mix-water", flow_id = "fluid/water", role = "in", x = 4, y = 2, kind = "fluid", step_id = "mix", rate_per_second = 10}},
  bindings = {{source_port_id = "water-port", sink_port_id = "mix-water", flow_id = "fluid/water", sink = "step:mix", rate_per_second = 10}},
 },
 feeds = {{tile = {0, 2}, fluid = "water"}},
 check = "fluid_system", truth = "defect", codes = {"BP_V_FLUID_DISCONNECTED", "BP_V_TRANSPORT_UNUSED"},
 audit = {blueprint_audit = {unused_pipe_tiles = 2}},
}
