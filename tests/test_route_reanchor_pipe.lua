--RA1 is red on b08c8c1: gray + magenta grid 9 layered, legalcopilot-dev 2026-09-28 - a kept re-route replaced the
--molten-iron pipe that casting-iron:4's binding named; binding_path walks belt headings only, the binding stayed
--dead, audit_route_work deleted it and the validator found the port with no binding (BP_V_PORT_UNREACHABLE).
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local key = Route._coordinate_key

H.test("RA1 a pipe binding whose segment was replaced re-anchors on the pipe at its sink port", function()
    local pipe = {segment_id = "new", kind = "pipe", flow_id = "fluid/m", allocations = {}}
    local work = {segments = {pipe}, segments_by_cell = {[key(40, 49)] = pipe},
        endpoint_by_id = {src = {x = 18, y = 20, port_id = "src"}, sink = {x = 40, y = 49, port_id = "sink"}},
        bindings = {{flow_id = "fluid/m", source_port_id = "src", sink_port_id = "sink", segment_id = "gone"}}}
    Route._test.reanchor_bindings(work)
    H.equal(work.bindings[1].segment_id, "new")
    io.write("RA1\n")
end)
H.test("RA2 a dead binding with a foreign segment on its sink stays dead", function()
    local other = {segment_id = "x", kind = "pipe", flow_id = "fluid/w", allocations = {}}
    local work = {segments = {other}, segments_by_cell = {[key(40, 49)] = other},
        endpoint_by_id = {src = {x = 18, y = 20, port_id = "src"}, sink = {x = 40, y = 49, port_id = "sink"}},
        bindings = {{flow_id = "fluid/m", source_port_id = "src", sink_port_id = "sink", segment_id = "gone"}}}
    Route._test.reanchor_bindings(work)
    H.equal(work.bindings[1].segment_id, "gone")
    io.write("RA2\n")
end)
H.done("test_route_reanchor_pipe")
