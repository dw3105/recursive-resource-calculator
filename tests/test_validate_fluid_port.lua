local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local Grid = require "logic.bp.grid"
local function run(occupant)
    local state = Validate.begin({grid={w=12,h=12}, catalog={entity={}},
        ports={{port_id="fluid-in", flow_id="fluid/copper", kind="fluid", role="in", x=6, y=6, dir=Grid.EAST}},
        entities={occupant}})
    while not state.done do Validate.step(state, {ops=100}) end
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_PORT_EDGE_WRONG" then return true end end
    return false
end
H.test("a belt behind a fluid port is not a port conflict", function()
    H.equal(run({id="belt", kind="belt", name="transport-belt", flow_id="item/gear", x=5, y=6, w=1, h=1}), false)
end)
H.test("a foreign pipe behind a fluid port is refused", function()
    H.equal(run({id="pipe", kind="pipe", name="pipe", flow_id="fluid/iron", x=5, y=6, w=1, h=1}), true)
end)
H.done("test_validate_fluid_port")
