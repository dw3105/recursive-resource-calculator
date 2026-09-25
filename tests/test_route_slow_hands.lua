--Red on round-36-int3: the four same-flow output hands each received BP_R_NO_PATH instead of sharing a run.
local H = require "tests.harness"
H.test("SH1 same-flow output hands on one face all reach their feed", function()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/route_red10s_stack1_call1.json"))
    local input = helpers.json_to_table(f:read("*a")); f:close()
    local Route = require "logic.bp.route"
    local state = Route.begin(input)
    while not state.done do Route.step(state, {ops=100000}) end
    H.equal(state.ok, true, "route succeeds")
    local targeted, retried = 0, 0
    for _, d in ipairs((state.work or state._work).demands or {}) do
        local source=d.source or {}
        if source.x==13 and source.y>=22 and source.y<=25 then
            targeted=targeted+1
            H.equal(d.unroutable,nil,"each adjacent output hand reaches its feed")
            if d.free_heading then retried=retried+1 end
        end
    end
    H.equal(targeted,4,"fixture has the four adjacent output hands")
    H.equal(retried>0,true,"a failed fixed-heading attempt retries with a free source heading")
end)
H.done("test_route_slow_hands")
