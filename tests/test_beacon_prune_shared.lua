-- BP1 fails on round-47-base: sharing same-signature beacons can erase one required coverage count.
local H=require "tests.harness"
local Prune=require "logic.bp.beacon_prune"
local function fixture()
    return {
        {id="M1",kind="machine",x=0,y=0,w=5,h=5},
        {id="M2",kind="machine",x=0,y=12,w=5,h=5},
        {id="X",kind="beacon",x=1,y=5,w=3,h=3,supply_w=4,supply_h=3,signature="S",required_for={"M1"}},
        {id="Y",kind="beacon",x=5,y=9,w=3,h=3,supply_w=4,supply_h=3,signature="S",required_for={"M1","M2"}},
        {id="Z",kind="beacon",x=9,y=5,w=3,h=3,supply_w=4,supply_h=3,signature="S",required_for={"M1"}},
    }
end
H.test("BP1 shared machine keeps all three required beacons",function()
    local entities=fixture(); Prune.share(entities,{}, {})
    local count=0
    for _,e in ipairs(entities) do if e.kind=="beacon" and e.signature=="S" then
        count=count+1; local has=false; for _,id in ipairs(e.required_for or {}) do if id=="M1" then has=true end end
        H.equal(has,true,"each remaining beacon retains M1 membership")
    end end
    H.equal(count,3,"M1 keeps three beacons")
end)
H.test("BP2 disjoint machine coverage can still merge",function()
    local entities={
        {id="A",kind="machine",x=0,y=0,w=5,h=5},{id="B",kind="machine",x=0,y=12,w=5,h=5},
        {id="X",kind="beacon",x=1,y=5,w=3,h=3,supply_w=4,supply_h=3,signature="S",required_for={"A"}},
        {id="Y",kind="beacon",x=5,y=9,w=3,h=3,supply_w=4,supply_h=3,signature="S",required_for={"B"}},
    }
    H.equal(Prune.share(entities,{},{}),1,"disjoint required machine ids merge")
end)
H.done("test_beacon_prune_shared")
