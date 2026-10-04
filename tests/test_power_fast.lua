-- Regression tests for lane 311. These assertions fail on round-56-base (2026-10-04).
local H = require "tests.harness"
H.new_world("2.0")
local Power = require "logic.bp.power"
local graph_dump = require "tools.lib.graph_dump"

H.test("PF1 power fixture fast path preserves the base result", function()
    local input_file = assert(io.open("tests/fixtures/r56/blue_bound_power.json", "r"))
    local input = helpers.json_to_table(input_file:read("*a")); input_file:close()
    local state, calls = Power.begin(input), 0
    while not state.done and calls < 1000000 do Power.step(state, {ops = 2000}); calls = calls + 1 end
    H.equal(state.done, true, "fixture power completes")
    local expected_file = assert(io.open("tests/fixtures/r56/311/power_base.json", "r"))
    local expected = expected_file:read("*a"); expected_file:close()
    H.equal(helpers.table_to_json(state.result), expected, "power result matches round-56-base")
    local drawn = graph_dump.load("tests/fixtures/power_r10s_drawn_state.lua.gz")
    calls = 0
    while not drawn.done and calls < 1000000 do Power.step(drawn, {ops=2000}); calls=calls+1 end
    H.equal(drawn.done, true, "drawn power checkpoint completes")
    local drawn_file = assert(io.open("tests/fixtures/r56/311/r10_base.json", "r"))
    local drawn_expected = drawn_file:read("*a"); drawn_file:close()
    H.equal(helpers.table_to_json(drawn.result), drawn_expected, "drawn state result matches round-56-base")
    print("PF1")
end)

H.test("PF2 consumer coverage bills one op per consumer", function()
    local state = Power.begin({grid_w=1, grid_h=1, consumers={}, pole={name="pole",tile_w=1,tile_h=1,
        supply_w=1,supply_h=1,wire_reach=1}})
    local candidate = {spec_index=1, name="pole", quality="normal", rect={x=0,y=0,w=1,h=1},
        supply_w=1,supply_h=1,covers={}}
    local consumers = {}
    for i=1,4 do consumers[i]={id="c"..i,rect={x=0,y=0,w=1,h=1}} end
    state._work.consumers = consumers
    state._work.candidate_eval = {candidate=candidate, consumer_index=1}
    state.cursor = {phase="candidate_coverage"}
    local budget={ops=1}; Power.step(state,budget)
    H.equal(state._work.candidate_eval.consumer_index, 2, "one consumer was covered")
    H.equal(state.ops_used, 1, "one charged op per consumer")
    print("PF2")
end)

H.test("PF4 blocked-candidate scan is charged: every red-green power step fits the 50 ms model", function()
    --Round 56 gate 2026-10-04: base 3722854 weighted (one unit walked all 129 consumers for 4 ops), 75 ms ticks.
    local pipe = assert(io.popen("lua5.2 tests/fixtures/r56/311/power_tick_cost.lua tests/fixtures/r56/rg_power_t312.lua.gz 4000 2>&1"))
    local out = pipe:read("*a"); pipe:close()
    local worst = tonumber(out:match("WORST (%d+)"))
    H.equal(worst ~= nil and worst <= 2440000, true, "every power step fits the 50 ms model: " .. tostring(worst) .. " " .. out)
    H.equal(out:match("SAME (%a+)"), "true", "sliced result equals one-shot result")
    print("PF4")
end)

H.test("PF3 publish finish resumes and matches one-shot output", function()
    local function finish(slice)
        local state = {done=false, cursor={phase="publish_finish"}, progress={done_units=0,total_units=9},
            ops_used=0, _work={connect={components=1}, publish={entities={},wires={},uncovered={},errors={}}}}
        local calls=0
        while not state.done and calls < 20 do Power.step(state,{ops=slice}); calls=calls+1 end
        H.equal(state.done,true,"publish completes")
        return state,calls
    end
    local sliced,calls=finish(1); local whole=finish(2000)
    H.equal(calls > 1,true,"publish finish is sliced")
    H.deep_equal(sliced.result,whole.result,"slicing preserves the result")
    print("PF3")
end)
H.done("test_power_fast")
