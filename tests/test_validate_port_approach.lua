-- PA1 and PA2 fail on base code: port approaches use the declared heading rather than the routed belt.
package.path = "./?.lua;" .. package.path
local snapshot = require "tools.lib.graph_dump".load("tests/fixtures/route_snaps/stack1_validate_candidate.lua.gz")
local Validate = require "logic.bp.validate"
local H = require "tests.harness"

local function replay()
    local st = snapshot.state
    local v = Validate.begin({candidate = st.work.validate_candidate, plan = st.work.plan_result,
        catalog = st.work.input.catalog, ring_bump = st.work.attempt or 0})
    while not v.done do Validate.step(v, {ops = 100000}) end
    return v
end

local function has_port_error(state)
    for _, err in ipairs(state.errors or {}) do
        if err.code == "BP_V_PORT_EDGE_WRONG" then return true end
    end
    return false
end

H.test("PA1 stack1 routed ports follow their belt heading", function()
    H.equal(replay().ok, true)
end)

H.test("PA2 output still rejects foreign flow ahead along the belt", function()
    local Grid = require "logic.bp.grid"
    local state = Validate.begin({grid = {w = 12, h = 12}, catalog = {entity = {}},
        ports = {{port_id = "out", flow_id = "item/copper", role = "out", x = 6, y = 6, dir = Grid.EAST}},
        entities = {
            {id = "own", kind = "belt", name = "transport-belt", flow_id = "item/copper", x = 6, y = 6, w = 1, h = 1, dir = Grid.NORTH},
            {id = "foreign", kind = "belt", name = "transport-belt", flow_id = "item/iron", x = 6, y = 5, w = 1, h = 1, dir = Grid.NORTH},
        }})
    while not state.done do Validate.step(state, {ops = 100}) end
    H.equal(has_port_error(state), true)
end)

H.done("test_validate_port_approach")
