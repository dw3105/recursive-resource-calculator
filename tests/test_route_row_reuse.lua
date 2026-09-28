--RR1 is red on round-47-base: a row demand may terminate on a crossing trunk and receive no items.
local H=require "tests.harness"
local Route=require "logic.bp.route"
H.test("RR1 row head rejects wrong heading reuse",function()
    local guard=Route._test.row_head_reuse_guard
    local demand={kind="belt",sink={row_port=true,role="in",travel_dir=4,x=5,y=5}}
    H.equal(guard(demand,{x=5,y=5},{direction=0},2,2),true,"crossing trunk at path end is rejected")
    io.write("RR1\n")
end)
H.test("RR2 row head accepts matching heading",function()
    local demand={kind="belt",sink={row_port=true,role="in",travel_dir=4,x=5,y=5}}
    H.equal(Route._test.row_head_reuse_guard(demand,{x=5,y=5},{direction=4},2,2),false,"matching direction is allowed")
    io.write("RR2\n")
end)
H.done("test_route_row_reuse")
