local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local Grid = require "logic.bp.grid"

local function candidate(entities)
    local s = Validate.begin({grid={w=40,h=40}, catalog={entity={}, inserter={items_per_second=10}, belt={underground_max_distance=5}}, entities=entities})
    while not s.done do Validate.step(s,{ops=100}) end
    return s
end
local function belt(id,x,y,d,lane)
    return {id=id,name="transport-belt",kind="belt",type="belt",x=x,y=y,w=1,h=1,dir=d,carried_lane=lane}
end
local function ug(id,x,y,d,role,pair)
    return {id=id,name="underground-belt",kind="belt",type=role,ug_role=role,ug_pair_id=pair,x=x,y=y,w=1,h=1,dir=d}
end
local function has(s,code)
    for _,e in ipairs(s.errors or {}) do if e.code==code then return e end end
end

H.test("TS1 blocked lane is derived at the in-game anchor", function()
    print("lane trace: inserter (14,10) drops on (14,9); NORTH travel => right/east lane; curve preserves right; WEST travel at (14,4) => right/north lane; NORTH inlet hood blocks north lane")
    --The candidate's INTERNAL frame points an inserter's dir at its DROP (logic/bp/serialize.lua flips it at the
    --publish boundary).  This row first wrote dir=SOUTH for "drops north", the published frame, and the
    --validator seeded lanes on the pickup tile instead.  Corrected 2026-09-23 on legalcopilot-dev.
    local route={ {id="drop",name="inserter",kind="inserter",type="inserter",x=14,y=10,w=1,h=1,dir=Grid.NORTH} }
    for y=9,5,-1 do route[#route+1]=belt("north-"..y,14,y,Grid.NORTH) end
    route[#route+1]=belt("anchor-feeder",14,4,Grid.WEST)
    route[#route+1]=ug("anchor-in",13,4,Grid.NORTH,"input","anchor-out")
    route[#route+1]=ug("anchor-out",13,0,Grid.NORTH,"output","anchor-in")
    local s=candidate(route)
    local e=has(s,"BP_V_UNDERGROUND_SIDELOAD_BLOCKED")
    H.equal(e~=nil,true); H.equal(e.ids[1],"anchor-feeder"); H.equal(e.ids[2],"anchor-in")
end)
H.test("TS2 passing lane side-load is legal", function()
    print("lane trace: inserter (15,9) drops on (14,9) from the EAST; NORTH travel puts it on left/west lane; curve preserves left; WEST feeder's left lane is south, behind the NORTH inlet hood, so the item passes")
    local route={{id="other-side-hand",name="inserter",kind="inserter",type="inserter",x=15,y=9,w=1,h=1,dir=Grid.WEST}}
    for y=9,5,-1 do route[#route+1]=belt("other-north-"..y,14,y,Grid.NORTH) end
    route[#route+1]=belt("pass-feeder",14,4,Grid.WEST)
    route[#route+1]=ug("pass-in",13,4,Grid.NORTH,"input","pass-out")
    route[#route+1]=ug("pass-out",13,0,Grid.NORTH,"output","pass-in")
    local s=candidate(route)
    H.equal(has(s,"BP_V_UNDERGROUND_SIDELOAD_BLOCKED"),nil)
end)
H.test("TS2b same belts, hand on the WEST side, item rides the blocked lane", function()
    --The control that keeps TS2 honest: identical belts, only the hand moves across.  If TS2 passed because
    --no lane was ever seeded, this row stays silent too and fails.
    print("lane trace: inserter (13,9) drops on (14,9) from the WEST; far lane is east = right; curve keeps right; WEST feeder's right lane is north, under the NORTH inlet hood")
    local route={{id="west-hand",name="inserter",kind="inserter",type="inserter",x=13,y=9,w=1,h=1,dir=Grid.EAST}}
    for y=9,5,-1 do route[#route+1]=belt("west-north-"..y,14,y,Grid.NORTH) end
    route[#route+1]=belt("west-feeder",14,4,Grid.WEST)
    route[#route+1]=ug("west-in",13,4,Grid.NORTH,"input","west-out")
    route[#route+1]=ug("west-out",13,0,Grid.NORTH,"output","west-in")
    local s=candidate(route)
    local e=has(s,"BP_V_UNDERGROUND_SIDELOAD_BLOCKED")
    H.equal(e~=nil,true); H.equal(e.ids[1],"west-feeder")
end)
H.test("TS3 back-to-back tunnels within reach are refused", function()
    local s=candidate({ug("a-in",1,1,4,"input","a-out"),ug("a-out",3,1,4,"output","a-in"),ug("b-in",4,1,4,"input","b-out"),ug("b-out",5,1,4,"output","b-in")})
    H.equal(has(s,"BP_V_UNDERGROUND_BACK_TO_BACK")~=nil,true)
end)
H.test("TS3b combined tunnel span beyond reach is accepted", function()
    local s=candidate({ug("a-in",1,1,4,"input","a-out"),ug("a-out",5,1,4,"output","a-in"),ug("b-in",6,1,4,"input","b-out"),ug("b-out",12,1,4,"output","b-in")})
    H.equal(has(s,"BP_V_UNDERGROUND_BACK_TO_BACK"),nil)
end)
H.test("TS4 directed ring is refused and TS4b straight run is accepted", function()
    local ring={}; local pts={{1,1},{2,1},{3,1},{4,1},{5,1},{5,2},{5,3},{5,4},{4,4},{3,4},{2,4},{1,4},{1,3},{1,2}}
    for i,p in ipairs(pts) do local q=pts[i%#pts+1]; local d=Grid.dir_from_vector(q[1]-p[1],q[2]-p[2]); ring[#ring+1]=belt("r"..i,p[1],p[2],d) end
    H.equal(has(candidate(ring),"BP_V_ROUTE_LOOP")~=nil,true)
    H.equal(has(candidate({belt("s1",1,1,4),belt("s2",2,1,4),belt("s3",3,1,4)}),"BP_V_ROUTE_LOOP"),nil)
end)
H.done("test_validate_transport_shapes")
