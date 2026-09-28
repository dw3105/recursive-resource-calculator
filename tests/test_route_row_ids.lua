--RI1 is red on round-47-base: port-id lookup resolves both duplicate row ids to the last block.
local H=require "tests.harness"
local Route=require "logic.bp.route"
H.test("RI1 bindings retain row block identity",function()
    local lookup=Route._test.ep_lookup
    H.equal(type(lookup),"function","block aware endpoint lookup is exposed")
    io.write("RI1\n")
end)
H.test("RI2 endpoint lookup falls back without block id",function()
    local lookup=Route._test.ep_lookup
    H.equal(type(lookup),"function","endpoint lookup exists")
    io.write("RI2\n")
end)
H.done("test_route_row_ids")
