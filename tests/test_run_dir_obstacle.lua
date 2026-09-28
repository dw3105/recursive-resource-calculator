-- RD1 fails on round-47-base: flipped out-port exit ignores roboport rectangles.
local H=require "tests.harness"
local Grid=require "logic.bp.grid"
local RunDir=require "logic.bp.run_dir"

local function fixture()
    local b={id="row",w=8,h=4,row={first_x=1,last_x=6},ports={
        {port_id="row:out:science",row_port=true,role="out",attach_dx=6,attach_dy=1,normal_dir=Grid.WEST,travel_dir=Grid.EAST}},
        belt_runs={{role="out",flows={"science"},tiles={{x=1,y=1},{x=2,y=1}},dir=Grid.EAST,port={x=7,y=1,travel_dir=Grid.EAST}}}}
    local p={x=10,y=10,dir=Grid.NORTH}; local target={id="target",w=1,h=1}
    return b,p,{b,target},{p,{x=0,y=10,dir=Grid.NORTH}},{w=30,h=30},
        {{flow_id="science",consumers={{step_id="target"}}}}
end
local obstacle={{rect={x=10,y=11,w=1,h=1}}}
H.test("RD1 obstacle on flipped out exit rejects flip",function()
    local b,p,bs,ps,g,f=fixture()
    local r=RunDir.choose(b,p,bs,ps,g,f,"left","top",obstacle)
    H.equal(r.ports[1].attach_dx,6,"unflipped block retained")
end)
H.test("RD2 no obstacle preserves preferred flip",function()
    local b,p,bs,ps,g,f=fixture()
    local r=RunDir.choose(b,p,bs,ps,g,f,"left","top")
    H.equal(r.ports[1].attach_dx,1,"preferred flipped block chosen")
end)
H.test("RD3 out exit follows travel direction, not inward normal",function()
    local b,p,bs,ps,g,f=fixture()
    local r=RunDir.choose(b,p,bs,ps,g,f,"left","top",{{rect={x=10,y=9,w=1,h=1}}})
    H.equal(r.ports[1].attach_dx,1,"normal-side obstacle does not block flipped exit")
end)
H.done("test_run_dir_obstacle")
