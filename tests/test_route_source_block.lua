--FB1 is red on bd494f0: gray + magenta grid 9, legalcopilot-dev 2026-09-28 - production-science rows @0 (9,160) and
--@7 (9,181) share port id row:out:item/production-science-pack, rate 5 and edge sink; the re-route pass named a
--binding without its source block, found @0 when it meant @7, and @7 was left with no path to the edge.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local find = Route._test.find_binding

local function work()
    local function b(block) return {flow_id = "p", source_port_id = "row:out:p", sink_port_id = "out:p", rate_per_second = 5,
        source_block_id = block} end
    return {bindings = {b("block:p@0"), b("block:p@7")}}
end

H.test("FB1 a binding spec with a source block finds that block's binding", function()
    local w = work()
    H.equal(find(w, {"row:out:p", "out:p", 5, nil, "block:p@7"}), w.bindings[2])
    H.equal(find(w, {"row:out:p", "out:p", 5, nil, "block:p@0"}), w.bindings[1])
    io.write("FB1\n")
end)
H.test("FB2 a spec without a source block still finds the first match", function()
    local w = work()
    H.equal(find(w, {"row:out:p", "out:p", 5}), w.bindings[1])
    io.write("FB2\n")
end)
H.done("test_route_source_block")
