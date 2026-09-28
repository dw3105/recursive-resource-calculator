-- VP1 is red on base: repeated row port ids on different block owners must survive collection.
local H=require "tests.harness"
local Validate=require "logic.bp.validate"
local function run(ports)
    local blocks={}
    for i=1,2 do blocks[i]={block_id="block-"..i,ports={ports[i]}} end
    local input={grid={w=10,h=10},catalog={entity={}},blocks=blocks,
        plan={steps={{step_id="step-1"},{step_id="step-2"}}},flows={{flow_id="item-a",producers={{step_id="step-1",share_per_second=1}},consumers={{step_id="step-2",share_per_second=1}}}},
        bindings={{source_port_id="row:in:item-a",sink_port_id="row:in:item-a",source_block_id="block-1",sink_block_id="block-2",flow_id="item-a"}}}
    local state=Validate.begin(input); while not state.done do Validate.step(state,{ops=2000}) end; return state
end
H.test("VP1 each row block keeps its repeated port id",function()
    local s=run({{port_id="row:in:item-a",block_id="block-1",step_id="step-1",member_id="m1",role="out",flow_id="item-a"},
        {port_id="row:in:item-a",block_id="block-2",step_id="step-2",member_id="m2",role="in",flow_id="item-a"}})
    H.equal(#s._work.ports,2)
    for _,e in ipairs(s.errors) do H.equal(e.code=="BP_V_ROUTE_DISCONTINUOUS" and tostring(e.detail and e.detail.reason or ""):find("own port",1,true)~=nil,false) end
end)
H.test("VP2 identical owner port duplicate still collapses",function()
    local p={port_id="row:in:item-a",block_id="block-1",step_id="step-1",member_id="m1",role="out",flow_id="item-a"}
    local s=run({p,p}); H.equal(#s._work.ports,1)
end)
io.write("VP1 VP2\n")
H.done("test_validate_row_ports")
