return {
 id = "fluid_disconnected_ok", rule = "BP_V_FLUID_DISCONNECTED", class = "engine", from = "tests/test_blueprint_physical_contract.lua FL3 removing pipe from middle breaks fluid network", grid = {w = 12, h = 12},
 entities = {
  {id = "machine", kind = "machine", type = "machine", name = "assembling-machine-3", x = 3, y = 3, w = 3, h = 3, step_id = "mix", recipe = "concrete", recipe_quality = "normal", quality = "normal", modules = {}},
  {id = "pipe0", kind = "pipe", name = "pipe", x = 0, y = 4, flow_id = "fluid/water"},
  {id = "pipe1", kind = "pipe", name = "pipe", x = 1, y = 4, flow_id = "fluid/water"},
  {id = "pipe2", kind = "pipe", name = "pipe", x = 2, y = 4, flow_id = "fluid/water"}
 },
 validator = {
  catalog = {entity = { ["assembling-machine-3"] = {name = "assembling-machine-3", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = false, module_slots = 4, fluid_boxes = {{production_type = "input", index = 1, pipe_connections = {{position = {x = -2, y = 0}, direction = 12}}}} }}, pipe = {throughput_per_second = 1200}},
  plan = {steps = {{step_id = "mix", machine = "assembling-machine-3", machine_count = 1, recipe = "concrete", recipe_quality = "normal", modules = {}, inputs = {{full_name = "fluid/water", rate_per_second = 10, kind = "fluid", is_fluid = true}}, outputs = {}}}},
  flows = {{flow_id = "fluid/water", is_fluid = true}},
  ports = {{port_id = "water-port", flow_id = "fluid/water", role = "in", x = 0, y = 4, kind = "fluid", rate_per_second = 10}, {port_id = "mix-water", flow_id = "fluid/water", role = "in", x = 2, y = 4, kind = "fluid", step_id = "mix", rate_per_second = 10}},
  segments = {{id = "water-segment", segment_id = "water-segment", kind = "pipe", flow_id = "fluid/water", capacity_per_second = 1200, length = 3, allocations = {{flow_id = "fluid/water", sink = "step:mix", rate_per_second = 10}}}},
  bindings = {{source_port_id = "water-port", sink_port_id = "mix-water", flow_id = "fluid/water", sink = "step:mix", segment_id = "water-segment", rate_per_second = 10}},
 },
 check = "fluid_system", truth = "ok", codes = {}, audit = {blueprint_audit = {unused_pipe_tiles = 0}},
}
