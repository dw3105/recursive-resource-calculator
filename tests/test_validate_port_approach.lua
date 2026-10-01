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
    io.write("PA1 ")
    H.equal(replay().ok, true)
end)

H.test("PA2 output still rejects foreign flow ahead along the belt", function()
    io.write("PA2 ")
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

--PA3 red on bd494f0: gray + magenta grid 9 (legalcopilot-dev 2026-09-28) - the steel-plate row belt (29,113) runs east
--past the tile behind iron-ore input (29,112); the entity check read entity_direction(info.entity), always nil.
local function input_with_behind(behind_dir)
    local Grid = require "logic.bp.grid"
    local state = Validate.begin({grid = {w = 12, h = 12}, catalog = {entity = {}},
        ports = {{port_id = "in", flow_id = "item/copper", role = "in", x = 6, y = 6, dir = Grid.NORTH, travel_dir = Grid.NORTH}},
        entities = {
            {id = "own", kind = "belt", name = "transport-belt", flow_id = "item/copper", x = 6, y = 6, w = 1, h = 1, dir = Grid.NORTH},
            {id = "foreign", kind = "belt", name = "transport-belt", flow_id = "item/iron", x = 6, y = 7, w = 1, h = 1, dir = behind_dir},
        }})
    while not state.done do Validate.step(state, {ops = 100}) end
    return state
end

H.test("PA3 foreign belt passing sideways behind an input port is not a port error", function()
    io.write("PA3 ")
    H.equal(has_port_error(input_with_behind(require("logic.bp.grid").EAST)), false)
end)

H.test("PA4 foreign belt pointing into an input port is still a port error", function()
    io.write("PA4 ")
    H.equal(has_port_error(input_with_behind(require("logic.bp.grid").NORTH)), true)
end)

--PA5 red on ad09f6b: asm-1 electronic circuit x4 Turn 4 (round 54) - the circuit belt dives north at output port
--(16,19) under the copper-cable belt at (16,18); the ahead check read the entry's heading and refused it.
H.test("PA5 an underground entry on an output port tile dives under the foreign belt ahead", function()
    io.write("PA5 ")
    local Grid = require "logic.bp.grid"
    local function run(ug_role)
        local state = Validate.begin({grid = {w = 12, h = 12}, catalog = {entity = {}},
            ports = {{port_id = "out", flow_id = "item/copper", role = "out", x = 6, y = 6, dir = Grid.EAST}},
            entities = {
                {id = "own", kind = "belt", name = "underground-belt", flow_id = "item/copper", x = 6, y = 6, w = 1, h = 1,
                    dir = Grid.NORTH, ug_role = ug_role, ug_pair_id = "exit"},
                {id = "exit", kind = "belt", name = "underground-belt", flow_id = "item/copper", x = 6, y = 4, w = 1, h = 1,
                    dir = Grid.NORTH, ug_role = "output", ug_pair_id = "own"},
                {id = "foreign", kind = "belt", name = "transport-belt", flow_id = "item/iron", x = 6, y = 5, w = 1, h = 1, dir = Grid.WEST},
            }})
        while not state.done do Validate.step(state, {ops = 100}) end
        return state
    end
    H.equal(has_port_error(run("input")), false)
    H.equal(has_port_error(run(nil)), true)
end)

H.done("test_validate_port_approach")
