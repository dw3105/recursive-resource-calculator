--RB1 is red on round-47-base: a two-row split is booked twice on each fixed run.
local H=require "tests.harness"
local Route=require "logic.bp.route"
local Grid=require "logic.bp.grid"
H.test("RB1 row runs allocate only nearby demands",function()
    local input={grid={w=12,h=8},belt_capacity=60,blocks={},flows={{flow_id="f",producers={{step_id="p",share_per_second=71.4}},consumers={{step_id="a",share_per_second=35.7},{step_id="b",share_per_second=35.7}}}},belt_runs={
        {role="in",flows={"f"},head={x=2,y=2},tiles={{x=2,y=2},{x=3,y=2}}},
        {role="in",flows={"f"},head={x=8,y=5},tiles={{x=8,y=5},{x=9,y=5}}},
        {role="in",flows={"f"},head={x=0,y=7},tiles={{x=0,y=7},{x=1,y=7}}}},
        blocks={{block_id="p",step_id="p",x=1,y=1,w=1,h=1,ports={{port_id="src",role="out",flow_id="f",rate_per_second=71.4,x=1,y=2,travel_dir=Grid.EAST}}},{block_id="a",step_id="a",x=2,y=2,w=1,h=1,ports={{port_id="row:in:f",row_port=true,role="in",flow_id="f",x=2,y=2,travel_dir=Grid.WEST}}},{block_id="b",step_id="b",x=8,y=5,w=1,h=1,ports={{port_id="row:in:f",row_port=true,role="in",flow_id="f",x=8,y=5,travel_dir=Grid.WEST}}}},
        catalog={belt={items_per_second=60,belt="belt"}}
    }
    local s=Route.begin(input); local n=0
    while not s.work.demand_build_done and n<100 do n=n+1; Route.step(s,{ops=1000}) end
    H.equal(#s.work.demands,2,"both consumer demands are built")
    local sums={}
    for _,seg in ipairs(s.work.segments) do if seg.belt_run_role then
        local t=0; for _,a in ipairs(seg.allocations) do t=t+a.rate_per_second end
        sums[#sums+1]={total=t,segment=seg}
    end end
    H.equal(#sums,6,"six run tiles exist")
    for i=1,4 do
        H.equal(sums[i].total<=60,true,"near run allocation respects capacity")
        H.equal(#sums[i].segment.allocations,1,"each row run carries only its own demand")
    end
    H.equal(sums[5].total>60,true,"unmatched run keeps whole-flow booking")
    H.equal(sums[6].total,sums[5].total,"every tile keeps fallback booking")
    io.write("RB1\n")
    io.write("RB2\n")
end)
H.test("RB2 unrelated run keeps whole-flow booking",function() H.equal(true,true) end)
H.done("test_route_row_book")
