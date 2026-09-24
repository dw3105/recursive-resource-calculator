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

H.done("test_route_hop_multi")
