--This regression fails on round-39-base: fluid outputs select the first matching box instead of the last.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"

local function selected_box(role)
    local catalog = {entity = {
        foundry = {name = "foundry", tile_w = 5, tile_h = 5, etype = "assembling-machine",
            fluid_boxes = {
                {index = 3, production_type = "output", pipe_connections = {{position = {x = -1, y = -2}}}},
                {index = 4, production_type = "output", pipe_connections = {{position = {x = 1, y = -2}}}},
                {index = 1, production_type = "input", pipe_connections = {{position = {x = -2, y = 0}}}},
                {index = 2, production_type = "input", pipe_connections = {{position = {x = 2, y = 0}}}},
            }},
        inserter = {name = "inserter", tile_w = 1, tile_h = 1}},
        inserter = {name = "inserter", pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}}
    local entry = {port_id = "fluid", flow_id = "fluid/test", kind = "fluid", is_fluid = true,
        rate_per_second = 1}
    local step = {step_id = "step", machine = "foundry", machine_count = 1,
        inputs = role == "input" and {entry} or {}, outputs = role == "output" and {entry} or {}}
    local plan = {steps = {step}, flows = {{flow_id = "fluid/test", kind = "fluid", is_fluid = true}},
        ports = {{port_id = "fluid", role = role == "input" and "in" or "out", kind = "fluid",
            flow_id = "fluid/test", step_id = "step", rate_per_second = 1}}}
    local state = Groups.begin({catalog = catalog, plan = plan})
    for _ = 1, 100 do if state.done then break end; Groups.step(state, {ops = 10}) end
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do
            for _, port in ipairs(block.ports or {}) do
                if port.flow_id == "fluid/test" then return port.fluidbox_index, port.connection.position.x end
            end
        end
    end
end

H.test("fluid output selects the last catalog box", function()
    local index, x = selected_box("output")
    H.equal(index, 4, "output uses box 4")
    H.equal(x, 1, "output uses the right connection")
end)

H.test("fluid input still selects the first catalog box", function()
    local index, x = selected_box("input")
    H.equal(index, 1, "input uses box 1")
    H.equal(x, -2, "input uses the left connection")
end)

H.done("test_fluid_box")
