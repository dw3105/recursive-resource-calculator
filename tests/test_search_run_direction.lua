local H = require "tests.harness"
local Search = require "logic.bp.search"
local Grid = require "logic.bp.grid"

local function block()
    return {id="row",w=5,h=3,row={first_x=0,last_x=4},ports={
        {port_id="row:out:science",row_port=true,role="out",flow_id="science",attach_dx=5,attach_dy=1,normal_dir=Grid.WEST,travel_dir=Grid.EAST},
        {port_id="row:in:ore",row_port=true,role="in",flow_id="ore",attach_dx=-1,attach_dy=1,normal_dir=Grid.EAST,travel_dir=Grid.EAST,rear=true}},
        belt_runs={{role="out",flows={"science"},tiles={{x=0,y=2},{x=1,y=2},{x=2,y=2},{x=3,y=2},{x=4,y=2}},dir=Grid.EAST,port={x=5,y=2,travel_dir=Grid.EAST}},
            {role="in",flows={"ore"},tiles={{x=0,y=0},{x=1,y=0},{x=2,y=0},{x=3,y=0},{x=4,y=0}},dir=Grid.EAST,head={x=0,y=0}}}}
end
local function choose(consumer_x, input_producer_x, blocked)
    local row=block(); local other={id="consumer",w=1,h=1}; local producer={id="producer",w=1,h=1}
    local rowp={x=10,y=10,dir=Grid.NORTH}; local placements={rowp,{x=consumer_x,y=11,dir=Grid.NORTH},{x=input_producer_x,y=9,dir=Grid.NORTH}}
    local grid={w=32,h=24}
    local blocks={row,other,producer}
    --The reversed output port lands at world (9,11); a block covering it must keep the run as built.
    if blocked then blocks[4]={id="blocker",w=2,h=1}; placements[4]={x=8,y=11,dir=Grid.NORTH} end
    return Search._choose_row_runs(row,rowp,blocks,placements,grid,
        {{flow_id="science",consumers={{step_id="consumer"}}},{flow_id="ore",producers={{step_id="producer"}}}},"left","top")
end
H.test("SD1 west consumer reverses output run",function()
    local b=choose(2,20); local p=b.ports[1]; H.equal(p.attach_dx,-1,"output port moves to left edge")
end)
H.test("SD2 east consumer keeps output run",function()
    local b=choose(20,2); H.equal(b.ports[1].attach_dx,5,"output port stays at right edge")
end)
H.test("SD3 blocked approach keeps output run",function()
    local b=choose(2,20,true); H.equal(b.ports[1].attach_dx,5,"blocked reversal rejected")
end)
H.test("SD4 input direction is chosen independently",function()
    local b=choose(2,20); H.equal(b.ports[1].attach_dx,-1,"output reversed")
    H.equal(b.ports[2].attach_dx,5,"input points toward its producer")
end)
H.done("test_search_run_direction")
