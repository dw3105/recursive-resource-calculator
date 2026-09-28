-- FA1 and FA2 are red on base: surface pipe beside a buried span and head-on belt ends are disconnected.
local H=require "tests.harness"
local Validate=require "logic.bp.validate"
local G=require "logic.bp.grid"
local function run(entities)
    local s=Validate.begin({grid={w=20,h=20},catalog={entity={},belt={underground_max_distance=10},pipe={underground_max_distance=10}},entities=entities})
    while not s.done do Validate.step(s,{ops=2000}) end; return s
end
local function has(s,code) for _,e in ipairs(s.errors or {}) do if e.code==code then return true end end return false end
local function b(id,x,y,d,extra) local e={id=id,kind="belt",name="transport-belt",x=x,y=y,w=1,h=1,dir=d,flow_id="a"}; for k,v in pairs(extra or {}) do e[k]=v end; return e end
H.test("FA1 surface pipe beside pipe-to-ground span is not an alarm",function()
    local s=run({
        {id="pi",kind="pipe",name="pipe-to-ground",x=2,y=4,w=1,h=1,dir=G.WEST,type="input",ug_role="input",ug_pair_id="po",flow_id="water"},
        {id="po",kind="pipe",name="pipe-to-ground",x=7,y=4,w=1,h=1,dir=G.EAST,type="output",ug_role="output",ug_pair_id="pi",flow_id="water"},
        {id="surface",kind="pipe",name="pipe",x=4,y=4,w=1,h=1,flow_id="water"}})
    H.equal(has(s,"BP_V_UNDERGROUND_UNPAIRED"),false)
end)
H.test("FA2 opposing belt ends do not form a loop",function()
    H.equal(has(run({b("east",4,5,G.EAST),b("west",5,5,G.WEST)}),"BP_V_ROUTE_LOOP"),false)
end)
H.test("FA3 genuine square belt loop is reported",function()
    local s=run({b("a",5,5,G.EAST),b("b",6,5,G.SOUTH),b("c",6,6,G.WEST),b("d",5,6,G.NORTH)})
    H.equal(has(s,"BP_V_ROUTE_LOOP"),true)
end)
H.test("FA4 belt beside belt underground span still reports",function()
    local s=run({b("input",3,5,G.EAST,{name="underground-belt",ug_role="input",ug_pair_id="output"}),
        b("output",7,5,G.EAST,{name="underground-belt",ug_role="output",ug_pair_id="input"}),b("middle",5,5,G.EAST)})
    H.equal(has(s,"BP_V_UNDERGROUND_UNPAIRED"),true)
end)
io.write("FA1 FA2 FA3 FA4\n")
H.done("test_validate_false_alarms")
