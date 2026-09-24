-- Multi-binding endpoint moves are one route transaction: every consumer must remain connected.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function input()
    local catalog = {belt = {belt = "basic-belt", underground = "basic-underground", splitter = "basic-splitter",
        items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 5}}
    return {
        grid = Grid.new(10, 8), catalog = catalog,
        blocks = {
            {block_id="src", machines={{step_id="src"}}, x=7,y=1,w=1,h=1,ports={{port_id="src-out",role="out",
                kind="item",flow_id="item/iron",rate_per_second=2,attach_dx=0,attach_dy=1,
                normal_dir=Grid.NORTH,travel_dir=Grid.SOUTH}}},
            {block_id="a", machines={{step_id="a"}}, x=1,y=2,w=1,h=1,ports={{port_id="a-in",role="in",
                kind="item",flow_id="item/iron",rate_per_second=1,attach_dx=1,attach_dy=0,
                normal_dir=Grid.EAST,travel_dir=Grid.WEST}}},
            {block_id="b", machines={{step_id="b"}}, x=1,y=5,w=1,h=1,ports={{port_id="b-in",role="in",
                kind="item",flow_id="item/iron",rate_per_second=1,attach_dx=1,attach_dy=0,
                normal_dir=Grid.EAST,travel_dir=Grid.WEST}}},
        },
        flows={{flow_id="item/iron",is_fluid=false,producers={{step_id="src",share_per_second=2}},
            consumers={{step_id="a",share_per_second=1},{step_id="b",share_per_second=1}}}},
    }
end

H.test("two bindings from one source both reach their sinks", function()
    local state=Route.begin(input())
    local ticks=0
    while not state.done and ticks<600 do ticks=ticks+1; Route.step(state,{ops=100000}) end
    H.equal(state.done,true,"route completes")
    H.equal(state.ok,true,"both bindings route")
    local sinks={}
    for _,binding in ipairs(state.work.bindings or {}) do sinks[binding.sink_port_id]=true end
    H.equal(sinks["a-in"],true,"first sink binding exists")
    H.equal(sinks["b-in"],true,"second sink binding exists")
end)

--Route demands carry `amount`; a trial that moves a port with two belts read `rate_per_second` from them, so the
--belt it laid stored a nil allocation and the next capacity check died ("attempt to perform arithmetic on field
--'rate_per_second'"). Found 2026-09-24 on legalcopilot-dev: a layered pack trial put green science's shared iron
--port where such a hop was worth trying. Sink b faces north below the trunk so both belts own a turn and lift.
local function shared_port_input(hops)
    local value = input()
    value.grid = Grid.new(12, 10)
    local src_port = value.blocks[1].ports[1]
    src_port.hand_x, src_port.hand_y, src_port.hop_options = 7, 2, hops
    local b = value.blocks[3]
    b.x, b.y = 3, 4
    local port = b.ports[1]
    port.attach_dx, port.attach_dy, port.normal_dir, port.travel_dir = 0, -1, Grid.NORTH, Grid.SOUTH
    return value
end

H.test("RHM2 a hop trial on a port with two belts lays them with the demand amount", function()
    local hops = {{hand_x = 6, hand_y = 1, port_x = 5, port_y = 1, turns = 1},
        {hand_x = 8, hand_y = 1, port_x = 9, port_y = 1, turns = 3}}
    local ok, result = pcall(function()
        local state = Route.begin(shared_port_input(hops))
        local ticks = 0
        while not state.done and ticks < 600 do ticks = ticks + 1; Route.step(state, {ops = 100000}) end
        return state
    end)
    H.equal(ok, true, "route raises no error: " .. tostring(not ok and result or ""))
    if ok then
        H.equal(result.done, true, "route completes")
        H.equal(result.ok, true, "both belts route")
        for _, segment in pairs(result.work.segments_by_cell or {}) do
            for _, allocation in ipairs(segment.allocations or {}) do
                H.equal(type(allocation.rate_per_second), "number", "every belt allocation carries a rate")
            end
        end
    end
end)

H.done("test_route_hop_multi")
