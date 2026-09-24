local H = require "tests.harness"
local Ends = require "logic.bp.ends"
local Validate = require "logic.bp.validate"
local Grid = require "logic.bp.grid"

local function belt(id,x,y,dir,flow, extra)
    local e={id=id,kind="belt",name="transport-belt",x=x,y=y,dir=dir,flow_ids=flow}
    for k,v in pairs(extra or {}) do e[k]=v end
    return e
end
local function bleed_count(entities)
    local state=Validate.begin({grid={w=20,h=20},catalog={entity={},belt={items_per_second=10,lane_items_per_second=5}},entities=entities})
    while not state.done do Validate.step(state,{ops=100}) end
    local count=0
    for _,err in ipairs(state.errors or {}) do if err.code=="BP_V_BELT_BLEED" then count=count+1 end end
    return count
end

H.test("ET1 box-1 end turns and removes foreign belt bleed",function()
    local es={belt("a0",5,0,Grid.SOUTH,{"A"}),belt("a1",5,1,Grid.SOUTH,{"A"}),belt("a2",5,2,Grid.SOUTH,{"A"})}
    for x=3,8 do es[#es+1]=belt("b"..x,x,3,Grid.EAST,{"B"}) end
    H.equal(Ends.turn_heads({entities=es}),1,"one terminal belt turns")
    H.equal(es[3].dir,Grid.EAST,"left quarter turn")
    H.equal(bleed_count(es),0,"no bleed remains")
end)
H.test("ET2 foreign belt in first quarter-turn tile selects the other quarter",function()
    local es={belt("end",5,2,Grid.SOUTH,{"A"}),belt("east",6,2,Grid.EAST,{"B"}),belt("south",5,3,Grid.SOUTH,{"B"})}
    H.equal(Ends.turn_heads({entities=es}),1)
    H.equal(es[1].dir,Grid.WEST)
end)
H.test("ET3 a receiving join that declares both flows is left alone",function()
    local es={belt("end",5,2,Grid.SOUTH,{"A"}),belt("join",5,3,Grid.EAST,{"A","B"})}
    H.equal(Ends.turn_heads({entities=es}),0)
    H.equal(es[1].dir,Grid.SOUTH)
end)
H.test("ET4 no fitting heading leaves the belt unchanged",function()
    local es={belt("end",5,2,Grid.SOUTH,{"A"}),belt("block-e",6,2,Grid.EAST,{"B"}),belt("block-w",4,2,Grid.WEST,{"B"}),belt("bad",5,3,Grid.SOUTH,{"B"})}
    H.equal(Ends.turn_heads({entities=es}),0)
    H.equal(es[1].dir,Grid.SOUTH)
end)
H.test("ET5 splitters and undergrounds are never turned",function()
    local es={
      {id="s",kind="splitter",name="splitter",x=1,y=1,dir=Grid.SOUTH,flow_id="A"},
      {id="u",kind="underground",name="underground-belt",x=4,y=1,dir=Grid.SOUTH,ug_role="input",type="input",flow_id="A"},
      belt("foreign-s",1,2,Grid.EAST,{"B"}),belt("foreign-u",4,2,Grid.EAST,{"B"})}
    H.equal(Ends.turn_heads({entities=es}),0)
    H.equal(es[1].dir,Grid.SOUTH); H.equal(es[2].dir,Grid.SOUTH)
end)
H.done("test_ends_turn")
