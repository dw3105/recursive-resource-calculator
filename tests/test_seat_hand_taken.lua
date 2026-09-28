-- SH1 fails on round-47-base: Seat can hop onto an unseated hand tile; SH2 locks conflict-free choice.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Seat = require "logic.bp.seat"

local function fixture(conflict)
    local active = {id="m:active",kind="inserter",name="inserter",x=5,y=5,w=1,h=1,machine_id="m1",dir=Grid.WEST}
    local guard = {id="m:guard",kind="inserter",name="inserter",x=3,y=3,w=1,h=1,machine_id="m1",dir=Grid.WEST}
    local pa = {port_id="active",inserter_id="active",role="in",kind="item",flow_id="ore",x=6,y=5,
        attach_dx=5,attach_dy=0,normal_dir=Grid.EAST,travel_dir=Grid.EAST,
        hop_options={{hand_x=3,hand_y=3,port_x=2,port_y=3,turns=1},{hand_x=1,hand_y=4,port_x=0,port_y=4,turns=1}}}
    local pg = {port_id="guard",inserter_id="guard",role="in",kind="item",flow_id="local",x=4,y=3,
        attach_dx=2,attach_dy=0,normal_dir=Grid.EAST,travel_dir=Grid.EAST}
    if not conflict then
        pa.hop_options={{hand_x=1,hand_y=4,port_x=0,port_y=4,turns=1}}
    end
    return {entities={{id="m1",kind="machine",x=1,y=3,w=2,h=4},active,guard},ports={pa,pg}}, {w=12,h=12},
        {{flow_id="ore",producers={{step_id="$external"}}}}
end

H.test("SH1 unseated hand tiles and ports block a hop",function()
    local m,g,f=fixture(true)
    Seat.run(m,g,f,"left")
    local hands,ports={},{}
    for _,e in ipairs(m.entities) do if e.kind=="inserter" then local k=e.x..":"..e.y; H.equal(hands[k],nil,"unique hand tile"); hands[k]=true end end
    for _,p in ipairs(m.ports) do local k=p.x..":"..p.y; H.equal(ports[k],nil,"unique port tile"); ports[k]=true end
    H.equal(m.entities[3].x==3 and m.entities[3].y==3,true,"guard hand stays on its tile")
    H.equal(m.ports[1].x==0 and m.ports[1].y==4,true,"active hand uses the alternate hop")
end)
H.test("SH2 conflict-free hop choice stays unchanged",function()
    local m,g,f=fixture(false)
    Seat.run(m,g,f,"left")
    H.equal(m.entities[2].x,1,"chosen hop hand x")
    H.equal(m.entities[2].y,4,"chosen hop hand y")
    H.equal(m.ports[1].x,0,"chosen hop port x")
    H.equal(m.ports[1].y,4,"chosen hop port y")
end)
H.done("test_seat_hand_taken")
