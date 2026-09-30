--Round 52 integration (engine filter rows tests/fixtures/flip_filters_{2.0,2.1}.txt, headless 2.0.77 + 2.1.20, 2026-09-30):
--oil-refinery 5x5 at tiles x=3..7, y=3..7 (centre 5.5,5.5), dir north, no Flip, recipe basic-oil-processing (ONE input
--fluid, two input boxes). Engine binds crude-oil to prototype box 2, connection (1,2) -> pipe tile (6,8); prototype
--box 1 (-1,2) -> tile (4,8) stays empty (filter none). Today's validator pins a box only when the recipe fills every
--box of the role, so it accepted either. Box binding (CONTEXT.md) pins crude to box 2. Crude pipe column x=4: box 1's tile, engine gives box 1 no filter, refinery starves, defect.
local CRUDE_X = 4
local entities = {{id = "machine", kind = "machine", name = "oil-refinery", x = 3, y = 3, w = 5, h = 5, dir = "north",
    recipe = "basic-oil-processing", step_id = "oil"}}
for y = 8, 19 do
    entities[#entities + 1] = {id = "crude" .. y, kind = "pipe", name = "pipe", x = CRUDE_X, y = y, flows = {"fluid/crude-oil"},
        flow_id = "fluid/crude-oil"}
end
local function box(index, kind, x, y, direction)
    return {production_type = kind, index = index, connections = {{connection_type = "normal", flow_direction = kind,
        direction = direction, positions = {{x = x, y = y}, {x = -y, y = x}, {x = -x, y = -y}, {x = y, y = -x}}}}}
end
return {
 id = "refinery_basic_oil_bad", rule = "BP_V_FLUID_DISCONNECTED", class = "engine", from = "round 52 Box binding (engine filter rows)",
 grid = {w = 20, h = 20},
 entities = entities,
 validator = {
  catalog = {entity = {["oil-refinery"] = {name = "oil-refinery", etype = "assembling-machine", tile_w = 5, tile_h = 5,
      needs_power = false, module_slots = 3, fluid_boxes = {box(1, "input", -1, 2, 8), box(2, "input", 1, 2, 8),
          box(3, "output", -2, -2, 0), box(4, "output", 0, -2, 0), box(5, "output", 2, -2, 0)}}},
      recipe = {["basic-oil-processing"] = {name = "basic-oil-processing",
          ingredients = {{type = "fluid", name = "crude-oil", amount = 100}},
          products = {{type = "fluid", name = "petroleum-gas", amount = 45}},
          fluid_boxes = {["oil-refinery"] = {["crude-oil"] = {box = 2, role = "input"},
              ["petroleum-gas"] = {box = 5, role = "output"}}}}}},
  plan = {steps = {{step_id = "oil", machine = "oil-refinery", machine_count = 1, recipe = "basic-oil-processing",
      inputs = {{full_name = "fluid/crude-oil", rate_per_second = 10, kind = "fluid", is_fluid = true}}}}},
  flows = {{flow_id = "fluid/crude-oil", is_fluid = true}},
  ports = {{port_id = "crude-port", flow_id = "fluid/crude-oil", role = "in", x = CRUDE_X, y = 19, kind = "fluid", rate_per_second = 10},
      {port_id = "oil-crude", flow_id = "fluid/crude-oil", role = "in", x = CRUDE_X, y = 8, kind = "fluid", step_id = "oil", rate_per_second = 10}},
  bindings = {{source_port_id = "crude-port", sink_port_id = "oil-crude", flow_id = "fluid/crude-oil", sink = "step:oil", rate_per_second = 10}},
 },
 feeds = {{tile = {CRUDE_X, 19}, fluid = "crude-oil"}},
 check = "fluid_system", truth = "defect", codes = {"BP_V_FLUID_DISCONNECTED"},
 audit = {blueprint_audit = {unused_pipe_tiles = 0}},
}
