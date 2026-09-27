--PJ1-PJ4 characterize fluid joins and buried pipe walks; PJ4 fails on round-44-wave2.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function fluid_input()
    return {grid=Grid.new(13,7),catalog={pipe={pipe="pipe",underground="pipe-to-ground",
        throughput_per_second=100,underground_max_distance=5}},
        obstacles={{x=0,y=0,w=13,h=2,owner="wall"},{x=0,y=4,w=13,h=3,owner="wall"}},
        blocks={
            {block_id="left",machines={{step_id="left"}},x=1,y=2,w=1,h=1,ports={{port_id="left-out",role="out",kind="fluid",flow_id="fluid/a",rate_per_second=1,attach_dx=1,attach_dy=0,travel_dir=Grid.EAST}}},
            {block_id="right",machines={{step_id="right"}},x=10,y=2,w=1,h=1,ports={{port_id="right-out",role="out",kind="fluid",flow_id="fluid/a",rate_per_second=1,attach_dx=-1,attach_dy=0,travel_dir=Grid.WEST}}},
            {block_id="sink",machines={{step_id="sink"}},x=6,y=2,w=1,h=1,ports={{port_id="sink-in",role="in",kind="fluid",flow_id="fluid/a",rate_per_second=2,attach_dx=-1,attach_dy=0,travel_dir=Grid.EAST}}}},
        flows={{flow_id="fluid/a",is_fluid=true,producers={{step_id="left",share_per_second=1},{step_id="right",share_per_second=1}},consumers={{step_id="sink",share_per_second=2}}}}
    }
end

local function finish(input, ops)
    local s,n=Route.begin(input),0
    while not s.done and n<20000 do n=n+1; Route.step(s,{ops=ops or 10000}) end
    H.equal(s.done,true,"routing terminates")
    return s
end

H.test("PJ1 same-fluid producers join the sink pipe from opposite sides",function()
    local s=finish(fluid_input())
    H.equal(s.ok,true,"both source paths join one fluid network")
    H.equal(#(s.result.bindings or {}),2,"both demands bind")
end)

H.test("PJ2 buried crossing pipe remains connected to its entry and exit",function()
    local s=finish(fluid_input())
    H.equal(s.ok,true,"pipe network passes the buried crossing")
    H.equal(not (s.work.last_route_rejection and s.work.last_route_rejection.reason=="route-discontinuous"),true,
        "the route is not rejected as discontinuous")
end)

H.test("PJ3 belts still refuse a head-on join",function()
    local input=fluid_input()
    input.catalog={belt={belt="belt",underground="underground-belt",items_per_second=10}}
    for _,b in ipairs(input.blocks) do for _,p in ipairs(b.ports) do p.kind="item";p.flow_id="item/a" end end
    input.flows={{flow_id="item/a",is_fluid=false,producers={{step_id="left",share_per_second=1},{step_id="right",share_per_second=1}},consumers={{step_id="sink",share_per_second=2}}}}
    local s=finish(input)
    H.equal(s.ok,false,"belt head-on merge remains forbidden")
end)

H.test("PJ4 frozen gray and magenta route places the light-oil cracking demand",function()
    H.new_world(H.shapes()[1])
    local file=assert(io.open("tests/fixtures/route_gray_magenta_154.json","r"))
    local input=assert(helpers.json_to_table(file:read("*a"))); file:close()
    local s=Route.begin(input); local deadline=os.clock()+90; local placed=false
    local wanted_source="heavy-oil-cracking:out:fluid/light-oil:machine:heavy-oil-cracking:1"
    local wanted_sink="light-oil-cracking:in:fluid/light-oil:machine:light-oil-cracking:1"
    repeat
        for _,b in ipairs(s.work.bindings or {}) do if b.source_port_id==wanted_source and b.sink_port_id==wanted_sink then placed=true end end
        if placed or s.done or os.clock()>=deadline then break end
        Route.step(s,{ops=2000})
    until false
    H.equal(placed,true,"target fluid demand is placed before the CPU deadline")
end)

H.done("test_route_pipe_join")
