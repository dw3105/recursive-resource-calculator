--Round 54 integrator: foundry casting x4 Turn 4 in Factorio 2.0.77 delivered 7.5/s of 9.99/s: every branch
--side-loaded the trunk from one side, 14 hands on one lane. With `lane_cap` (the retry the search starts after
--BP_V_LANE_OVERLOAD) the router counts each lane and never returns a route with a lane above half a belt.
local H = require "tests.harness"
local function routed(lane_cap)
    H.new_world("2.0")
    local Route = require "logic.bp.route"
    local f = assert(io.open("tests/fixtures/route_foundry4_lane.json"))
    local input = helpers.json_to_table(f:read("*a")); f:close()
    input.lane_cap = lane_cap
    local state = Route.begin(input); local ticks = 0
    while not state.done and ticks < 200000 do ticks = ticks + 1; Route.step(state, {ops = 10000}) end
    H.equal(state.done, true, "route finishes")
    return state, Route._lane_recompute(state.work)
end
H.test("LC1 first routing puts fourteen foundry hands on one lane", function()
    local state, worst = routed(nil)
    H.equal(state.ok, true, "route succeeds")
    H.equal(worst > 7.5 + 1e-6, true, "a lane above 7.5/s without the rule, got " .. tostring(worst))
end)
H.test("LC2 the lane-capacity retry never returns a lane above half a belt", function()
    local state, worst = routed(true)
    H.equal(state.ok ~= true or worst <= 7.5 + 1e-6, true,
        "ok=" .. tostring(state.ok) .. " with worst lane " .. tostring(worst))
end)
H.done("test_route_lane_cap")
