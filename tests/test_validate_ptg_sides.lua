-- Regression tests for pipe-to-ground side handling; each case fails against the round-41-base validator.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local Grid = require "logic.bp.grid"

local function validate(input)
    local state = Validate.begin(input)
    while not state.done do Validate.step(state, {ops = 100}) end
    return state
end

local function has_code(state, wanted)
    for _, err in ipairs(state.errors or {}) do
        if err.code == wanted then return true end
    end
    return false
end

local function fluid_machine(ptg_direction, on_port)
    local flow = "fluid/a"
    return validate({candidate = {grid_w = 16, grid_h = 12, entities = {
        {id = "machine", name = "machine", kind = "machine", type = "machine", x = 5, y = 5, w = 2, h = 2, step_id = "maker"},
        {id = "ptg-machine", name = "pipe-to-ground", kind = "pipe", type = "pipe-to-ground", flow_id = flow,
            x = on_port and 8 or 7, y = 6, w = 1, h = 1, dir = ptg_direction},
        {id = "plain", name = "pipe", kind = "pipe", flow_id = flow, x = on_port and 9 or 8, y = 6, w = 1, h = 1},
    }, flows = {{flow_id = flow}}, ports = {{port_id = "source", flow_id = flow, role = "in", x = on_port and 8 or 7, y = 6}}},
        plan = {steps = {{step_id = "maker", machine = "machine", machine_count = 1,
            inputs = {{flow_id = flow, kind = "fluid", is_fluid = true, rate_per_second = 1}}}}},
        catalog = {entity = {
        machine = {name = "machine", etype = "assembling-machine", tile_w = 2, tile_h = 2,
            needs_power = false, fluid_boxes = {{production_type = "input", pipe_connections = {
                {position = {x = 2, y = 0}, direction = Grid.EAST},
            }}}},
    }}})
end

H.test("VS1 a plain pipe beside the closed side of a pipe-to-ground is not joined", function()
    H.equal(has_code(fluid_machine(Grid.WEST), "BP_V_FLUID_DISCONNECTED"), true)
end)
H.test("VS2 a plain pipe beside the open side of a pipe-to-ground is joined", function()
    H.equal(has_code(fluid_machine(Grid.EAST), "BP_V_FLUID_DISCONNECTED"), false)
end)
H.test("VS3 a machine port pipe-to-ground opening away is disconnected", function()
    H.equal(has_code(fluid_machine(Grid.EAST, true), "BP_V_FLUID_DISCONNECTED"), true)
end)
H.test("VS4 a machine port pipe-to-ground opening into the machine connects", function()
    H.equal(has_code(fluid_machine(Grid.WEST, true), "BP_V_FLUID_DISCONNECTED"), false)
end)
H.done("test_validate_ptg_sides")
