--PJ1-PJ4 characterize fluid joins and buried pipe walks; PJ4 fails on round-44-wave2.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

--A one-row corridor (y = 2) with the sink block ABOVE it: the sink's port tile (5,2) is open from the west and
--from the east. The left producer arrives heading east; the right producer can only arrive heading west, head-on
--into the left pipe. The PJ2 variant adds a one-tile wall in the corridor that only a pipe-to-ground crosses.
local function fluid_input()
    return {grid=Grid.new(13,5),catalog={pipe={pipe="pipe",underground="pipe-to-ground",
        throughput_per_second=100,underground_max_distance=5}},
        obstacles={{x=0,y=0,w=13,h=1,owner="wall"},{x=0,y=1,w=5,h=1,owner="wall"},{x=6,y=1,w=7,h=1,owner="wall"},
            {x=0,y=3,w=13,h=2,owner="wall"}},
        blocks={
            {block_id="left",machines={{step_id="left"}},x=1,y=2,w=1,h=1,ports={{port_id="left-out",role="out",kind="fluid",flow_id="fluid/a",rate_per_second=1,attach_dx=1,attach_dy=0,travel_dir=Grid.EAST}}},
            {block_id="right",machines={{step_id="right"}},x=11,y=2,w=1,h=1,ports={{port_id="right-out",role="out",kind="fluid",flow_id="fluid/a",rate_per_second=1,attach_dx=-1,attach_dy=0,travel_dir=Grid.WEST}}},
            {block_id="sink",machines={{step_id="sink"}},x=5,y=1,w=1,h=1,ports={{port_id="sink-in",role="in",kind="fluid",flow_id="fluid/a",rate_per_second=2,attach_dx=0,attach_dy=1,travel_dir=Grid.NORTH}}}},
        flows={{flow_id="fluid/a",is_fluid=true,producers={{step_id="left",share_per_second=1},{step_id="right",share_per_second=1}},consumers={{step_id="sink",share_per_second=2}}}}
    }
end

local function shortfalls(s)
    local n = 0
    for _ in ipairs(s.work and s.work.shortfalls or {}) do n = n + 1 end
    for _ in ipairs(s.errors or {}) do n = n + 1 end
    return n
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
    H.equal(shortfalls(s),0,"neither producer is left unrouted")
end)

H.test("PJ2 buried crossing pipe remains connected to its entry and exit",function()
    local input=fluid_input()
    input.obstacles[#input.obstacles+1]={x=8,y=2,w=1,h=1,owner="fluid-wall"}
    local s=finish(input)
    H.equal(s.ok,true,"pipe network passes the buried crossing")
    H.equal(shortfalls(s),0,"the right producer crosses the wall and joins")
    local buried=false
    for _,e in ipairs(s.result.entities or {}) do if e.ug_role then buried=true end end
    H.equal(buried,true,"the route crosses the wall with a pipe-to-ground pair")
    H.equal(not (s.work.last_route_rejection and s.work.last_route_rejection.reason=="route-discontinuous"),true,
        "the route is not rejected as discontinuous")
end)

H.test("PJ3 belts still refuse a head-on join",function()
    local input=fluid_input()
    input.catalog={belt={belt="belt",underground="underground-belt",items_per_second=10}}
    for _,b in ipairs(input.blocks) do for _,p in ipairs(b.ports) do p.kind="item";p.flow_id="item/a" end end
    input.flows={{flow_id="item/a",is_fluid=false,producers={{step_id="left",share_per_second=1},{step_id="right",share_per_second=1}},consumers={{step_id="sink",share_per_second=2}}}}
    local s=finish(input)
    H.equal(shortfalls(s) > 0,true,"belt head-on merge remains forbidden (the right belt is left unrouted)")
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
    if not placed then io.stderr:write("PJ4 state done="..tostring(s.done).." ok="..tostring(s.ok).." error="..tostring(s.errors and s.errors[1] and s.errors[1].code).." reject="..tostring(s.work.last_route_rejection and s.work.last_route_rejection.reason).."\n") end
    H.equal(placed,true,"target fluid demand is placed before the CPU deadline")
end)

--PJ5 (round 44): a pipe path may end on its own fluid network, not only on the sink tile. Lane 245's rewrite of the
--pipe witness demanded the sink tile and sent molten iron (4 producers, 13 consumers) into 21 restarts before
--demand 13 of 92 on the frozen 154x154 input; the network walk reaches demand 13 with 0 restarts (~24 s).
H.test("PJ5 frozen gray and magenta route reaches demand 13 without a restart",function()
    local f=assert(io.open("tests/fixtures/route_gray_magenta_154.json","r"))
    local input=assert(helpers.json_to_table(f:read("*a")))
    f:close()
    local s=Route.begin(input)
    local t0=os.clock()
    while not s.done and os.clock()-t0<90 do
        Route.step(s,{ops=2000})
        if s.cursor and s.cursor.demand_index and s.cursor.demand_index>12 and s.progress.phase=="routing" then break end
    end
    H.equal(s.cursor.demand_index>12,true,"route passes demand 12 within 90 s CPU")
    H.equal(s.work.counters.restarts,0,"no restart on the way")
end)

H.done("test_route_pipe_join")
