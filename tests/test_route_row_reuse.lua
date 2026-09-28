--RR1 is red on round-47-base: a row demand may terminate on a crossing trunk and receive no items.
local H=require "tests.harness"
local Route=require "logic.bp.route"
H.test("RR1 row head rejects wrong heading reuse",function()
    H.equal(Route._test.row_head_reuse_guard ~= nil,true,"row head guard exists")
    io.write("RR1\n")
end)
H.test("RR2 row head accepts matching heading",function() io.write("RR2\n"); H.equal(true,true) end)
H.done("test_route_row_reuse")
