--These fixtures fail on round-41-base: fluid underground pairs can face away from a port, and fluid sources cannot dive on their first step.
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"

local function fixture(role, kind, obstacle)
    local dir = Grid.EAST
    local port = {port_id="port",role=role,kind=kind,flow_id=(kind == "fluid" and "fluid/a" or "item/a"),
        rate_per_second=1,attach_dx=(role=="in" and -1 or 1),attach_dy=0,normal_dir=dir,travel_dir=dir}
    local source, sink
    if role == "in" then
        source = {block_id="source",machines={{step_id="source"}},x=1,y=3,w=1,h=1,
            ports={{port_id="source-out",role="out",kind=kind,flow_id=port.flow_id,rate_per_second=1,attach_dx=1,attach_dy=0,travel_dir=Grid.EAST}}}
        sink = {block_id="sink",machines={{step_id="sink"}},x=6,y=3,w=1,h=1,ports={port}}
    else
        source = {block_id="source",machines={{step_id="source"}},x=1,y=3,w=1,h=1,ports={port}}
        sink = {block_id="sink",machines={{step_id="sink"}},x=6,y=3,w=1,h=1,
            ports={{port_id="sink-in",role="in",kind=kind,flow_id=port.flow_id,rate_per_second=1,attach_dx=-1,attach_dy=0,travel_dir=Grid.EAST}}}
    end
    local blocks={source,sink}
    return {grid=Grid.new(10,8),catalog={pipe={pipe="pipe",underground="underground-pipe",throughput_per_second=100,underground_max_distance=5},
        belt={belt="belt",underground="underground-belt",items_per_second=100,underground_max_distance=5}},blocks=blocks,
        obstacles=obstacle and {{x=4,y=2,w=1,h=3,owner="wall"}} or nil,
        flows={{flow_id=port.flow_id,is_fluid=kind=="fluid",producers={{step_id="source",share_per_second=1}},consumers={{step_id="sink",share_per_second=1}}}}}
end

local function route(input)
    local state=Route.begin(input); local ticks=0
    while not state.done and ticks<20000 do ticks=ticks+1; Route.step(state,{ops=10000}) end
    H.equal(state.done,true,"route finishes"); H.equal(state.ok,true,"route succeeds "..tostring(state.errors and state.errors[1] and state.errors[1].code))
    return state
end
local function underground(state)
    for _,e in ipairs(state.result.entities or {}) do if e.ug_role then return e end end
end

H.test("FP1 fluid sink obstacle dives into port heading",function()
    local state=route(fixture("in","fluid",true)); local e=underground(state)
    H.equal(e~=nil,true,"uses underground pair"); local at_port=false
    for _,entity in ipairs(state.result.entities or {}) do if entity.ug_role and math.floor(entity.position.x)==5 and math.floor(entity.position.y)==3 then at_port=true; H.equal(entity.dir,Grid.EAST,"port tile opens east") end end
    H.equal(at_port,true,"underground endpoint is on fluid port tile")
end)
H.test("FP2 sideways approach cannot open away on fluid port",function()
    local input=fixture("in","fluid",false)
    input.obstacles={{x=4,y=2,w=1,h=1,owner="wall"}}
    local state=route(input)
    local at_port=false
    for _,e in ipairs(state.result.entities or {}) do
        if e.ug_role and math.floor(e.position.x)==5 and math.floor(e.position.y)==3 then at_port=true; H.equal(e.dir,Grid.EAST,"port tile opens east") end
    end
    H.equal(at_port, false, "a side-fed candidate is not needed on the port tile")
end)
H.test("FP3 fluid source can dive from its port tile",function()
    local state=route(fixture("out","fluid",true)); H.equal(underground(state)~=nil,true,"source uses underground pair")
end)
H.test("FP4 item source still cannot dive on first step",function()
    local state=route(fixture("out","item",true));
    for _,e in ipairs(state.result.entities or {}) do
        if e.ug_role then H.equal(math.floor(e.position.x)==2 and math.floor(e.position.y)==3,false,"item source port tile is not underground") end
    end
end)
H.done("test_route_fluid_port_ptg")
