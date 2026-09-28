--PO1 is red on 4a301d4: gray + magenta grid 9 layered, legalcopilot-dev 2026-09-28 - production-science row blocks @0
--and @7 both expose row:in:item/rail; the published port has member_id but no block_id, port_owner matched the id
--alone and placed both on @7, so rail:1/2 (feeding @0) read as BP_V_ROUTE_DISCONTINUOUS.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local owner = Validate._test.port_owner

local function work()
    return {placements = {}, blocks = {
        {block_id = "p@7", x = 20, y = 200, ports = {{port_id = "row:in:rail", member_id = "m8"}}},
        {block_id = "p@0", x = 40, y = 240, ports = {{port_id = "row:in:rail", member_id = "m1"}}}}}
end

H.test("PO1 a row port with no block id resolves to the block holding its member", function()
    H.equal(owner(work(), {port_id = "row:in:rail", member_id = "m1"}).block_id, "p@0")
    H.equal(owner(work(), {port_id = "row:in:rail", member_id = "m8"}).block_id, "p@7")
    io.write("PO1\n")
end)
H.test("PO2 a port with no member still resolves by id; a block id wins outright", function()
    H.equal(owner(work(), {port_id = "row:in:rail"}).block_id, "p@7")
    H.equal(owner(work(), {port_id = "row:in:rail", member_id = "m8", block_id = "p@0"}).block_id, "p@0")
    io.write("PO2\n")
end)
H.done("test_validate_port_owner")
