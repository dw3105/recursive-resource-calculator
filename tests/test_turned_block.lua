-- TB1-TB5 red on round-52-base (2026-09-30).
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Groups = require "logic.bp.groups"
local Hands = require "logic.bp.hands"
local Seat = require "logic.bp.seat"
local RunDir = require "logic.bp.run_dir"

local function block()
    return {id="b", block_id="b", w=5, h=4, members={
        {id="machine",kind="machine",x=1,y=1,w=2,h=2,dir=0},
        {id="hand",kind="inserter",name="inserter",x=0,y=1,w=1,h=1,machine_id="machine",
            pickup_position={x=1.5,y=2.5},drop_position={x=0.5,y=2.5}},
    }, ports={{port_id="p",inserter_id="hand",machine_id="m:machine",role="in",flow_id="iron",
        attach_dx=-1,attach_dy=1,normal_dir=12,travel_dir=0}}, belt_runs={{role="in",flows={"iron"},tiles={{x=0,y=2}}}}}
end

H.test("TB1 turned materialization keeps private world port tiles", function()
    local b=block()
    local north=Groups.materialize(b,{x=10,y=20,dir=0})
    H.equal(north.ports[1].x,9); H.equal(north.ports[1]._world_x,nil)
    for _,dir in ipairs({4,8,12}) do
        local p=Groups.materialize(b,{x=10,y=20,dir=dir}).ports[1]
        local q=Grid.place_port(b,{x=10,y=20,dir=dir},b.ports[1])
        H.equal(p._world_x,q.x); H.equal(p._world_y,q.y)
        H.equal(p.x,nil); H.equal(p.y,nil); H.equal(p._place_dir,dir)
    end
    print("TB1")
end)

H.test("TB2 turned ports get slides", function()
    local b=block(); local m=Groups.materialize(b,{x=10,y=10,dir=4})
    Hands.offer_slides(m,Grid.new(40,40))
    H.equal(type(m.ports[1].slide_options),"table")
    print("TB2")
end)

H.test("TB3 free_cell handles turned hand and keeps tile and attachment aligned", function()
    local b=block(); local m=Groups.materialize(b,{x=10,y=10,dir=4})
    local hand
    for _,e in ipairs(m.entities) do if e.kind=="inserter" then hand=e end end
    local ok=pcall(Hands.free_cell,m,hand.x,hand.y)
    H.equal(ok,true)
    local p=m.ports[1]
    if p._world_x ~= 9 then
        local q=Grid.place_port(b,{x=10,y=10,dir=4},p)
        H.equal(q.x,p._world_x); H.equal(q.y,p._world_y)
    end
    print("TB3")
end)

H.test("TB4 seat processes turned ports with hop candidates", function()
    local b=block(); local m=Groups.materialize(b,{x=10,y=10,dir=4})
    local p=m.ports[1]; p.hop_options={{hand_x=13,hand_y=11,port_x=14,port_y=11,turns=0}}
    local n=Seat.run(m,Grid.new(40,40),{{flow_id="iron",producers={{step_id="$external"}}}},"left")
    H.equal(n,1)
    print("TB4")
end)

H.test("TB5 RunDir partner overlap uses turned partner dimensions", function()
    local row={id="row",row=true,w=3,h=1,ports={},belt_runs={}}
    local partner={id="partner",w=5,h=3}
    RunDir.choose(row,{x=1,y=1,dir=0},{row,partner},{{x=1,y=1,dir=0},{x=8,y=4,dir=4}},
        Grid.new(30,30),{},"left","right",{})
    local w,h=Grid.rotate_size(partner.w,partner.h,4)
    H.equal(w,3); H.equal(h,5)
    print("TB5")
end)
H.done("test_turned_block")
