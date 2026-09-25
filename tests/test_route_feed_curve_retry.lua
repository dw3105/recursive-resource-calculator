--Round 36 (red science 10/s, 2026-09-25): the science row's gear side feed is entered straight from behind in first
--routing, by an underground under the machines. The output-side beacon row now sits where that underground had to
--start, so both gear demands died BP_R_NO_PATH and all ten assemblers starved. A row feed demand with no path now
--gets one restart with the curve in from the side allowed (logic/bp/route.lua fail_demand, d275988).
--The fixture is route's exact input for red-10s attempt 1, frozen by
--`lua5.2 tools/capture_stage_input.lua tests/golden/cases/player-red-science-10s/prepared_input.json <out> route`;
--with route.lua from d275988^ both gear demands stay BP_R_NO_PATH and this test fails.
local H = require "tests.harness"

H.test("FC1 a row side feed with no straight way in is routed by a curve instead of written off", function()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/route_red10s_attempt1.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Route = require "logic.bp.route"
    local state = Route.begin(root)
    while not state.done do Route.step(state, {ops = 100000}) end
    H.equal(state.ok, true, "route finishes")
    local gear, routed = 0, 0
    for _, demand in ipairs((state.work or state._work).demands or {}) do
        if demand.flow_id == "item/iron-gear-wheel" then
            gear = gear + 1
            if demand.unroutable == nil then routed = routed + 1 end
            H.equal(demand.unroutable, nil, "gear demand into " .. tostring(demand.sink and demand.sink.port_id) .. " is routed")
        end
    end
    H.equal(gear, 2, "both gear producer hands have a demand")
    H.equal(routed, 2, "both gear demands reach the science row")
end)

H.done("test_route_feed_curve_retry")
