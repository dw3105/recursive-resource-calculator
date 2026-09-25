--Round 37 (2026-09-25): the twin-edge fold (one edge belt + splitter, player rule "1 input item = 1 source") ran
--inside result_for at the end of FIRST routing and rewrote route's working segments; tidy then carried on from that
--half-folded state and dropped the splitter, so the foundry hand picking at the splitter tile saw empty ground and red
--science 10/s gave no blueprint. The fold now runs only in tidy's final result. Fixture: red-10s route call 3 on
--int/r37 (`tools/capture_stage_input.lua ... route 3`). With route.lua folding in first routing this test fails.
local H = require "tests.harness"

H.test("TS1 fold splitter survives tidy and one edge input remains per flow", function()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/route_red10s_twin_call3.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Route = require "logic.bp.route"
    local state = Route.begin(root)
    while not state.done do Route.step(state, {ops = 100000}) end
    H.equal(state.ok, true, "route finishes")
    local tidy = Route.tidy_begin(state, {})
    while not tidy.done do Route.tidy_step(tidy, {ops = 100000}) end
    local grid_w = root.grid and root.grid.w
    local splitters, edge_by_flow = 0, {}
    for _, e in ipairs(tidy.result.entities or {}) do
        if not e._route_removed then
            if tostring(e.name):find("splitter", 1, true) and e.position.x < 3 then splitters = splitters + 1 end
            local x = math.floor(e.position.x)
            if x == 0 and tostring(e.name):find("belt", 1, true) then
                local flow = tostring(e.flow_id)
                edge_by_flow[flow] = (edge_by_flow[flow] or 0) + 1
            end
        end
    end
    H.equal(splitters >= 1, true, "the edge splitter is still there after tidy")
    for flow, count in pairs(edge_by_flow) do H.equal(count, 1, "one edge belt for " .. flow) end
end)

H.done("test_route_twin_survives_tidy")
