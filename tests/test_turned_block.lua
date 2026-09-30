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
    kind="item",attach_dx=-1,attach_dy=1,normal_dir=12,travel_dir=0}}, belt_runs={{role="in",flows={"iron"},tiles={{x=0,y=2}}}}}
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
    local m={entities={{id="m:machine",kind="machine",x=10,y=10,w=2,h=2},
        {id="m:hand",kind="inserter",machine_id="m:machine",x=12,y=10,w=1,h=1}},
        ports={{port_id="p",inserter_id="hand",role="in",kind="item",flow_id="iron",
            attach_dx=2,attach_dy=0,travel_dir=0,normal_dir=0,_world_x=13,_world_y=10,_place_dir=4,
            hop_options={{hand_x=13,hand_y=11,port_x=14,port_y=11,turns=0}}}}}
    local n=Seat.run(m,Grid.new(40,40),{{flow_id="iron",producers={{step_id="$external"}}}},"right")
    H.equal(n,1)
    print("TB4")
end)

--TB5 rewritten by integrator (round 52 merge, 2026-09-30): the lane's TB5 asserted only Grid.rotate_size and passed
--on base. Fixture = tests/test_run_dir.lua SD1 (west consumer reverses the output run: reversed port (9,11), approach
--(8,11)) plus a 3x1 blocker placed turned at (8,9) dir 4: rotated 1x3 footprint x=8, y=9..11 covers the approach, so
--the reversal must be refused. Base read the unrotated 3x1 (x=8..10, y=9) and reversed onto the blocker.
H.test("TB5 RunDir overlap uses a turned partner's rotated footprint", function()
    local row = {id = "row", w = 5, h = 3, row = {first_x = 0, last_x = 4},
        ports = {{port_id = "row:out:science", row_port = true, role = "out", flow_id = "science",
            attach_dx = 5, attach_dy = 1, normal_dir = Grid.WEST, travel_dir = Grid.EAST}},
        belt_runs = {{role = "out", flows = {"science"}, tiles = {{x=0,y=2},{x=1,y=2},{x=2,y=2},{x=3,y=2},{x=4,y=2}},
            dir = Grid.EAST, port = {x=5,y=2,travel_dir=Grid.EAST}}}}
    local consumer, blocker = {id = "consumer", w = 1, h = 1}, {id = "blocker", w = 3, h = 1}
    local rowp = {x = 10, y = 10, dir = Grid.NORTH}
    local function choose(blocks, placements)
        return RunDir.choose(row, rowp, blocks, placements, {w = 32, h = 24},
            {{flow_id = "science", consumers = {{step_id = "consumer"}}}}, "left", "top")
    end
    H.equal(choose({row, consumer}, {rowp, {x = 2, y = 11, dir = 0}}).ports[1].attach_dx, -1, "free: reversed")
    local got = choose({row, consumer, blocker}, {rowp, {x = 2, y = 11, dir = 0}, {x = 8, y = 9, dir = 4}})
    H.equal(got.ports[1].attach_dx, 5, "turned blocker covers the reversed approach")
    print("TB5")
end)
H.done("test_turned_block")
