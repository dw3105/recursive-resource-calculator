--Bounded power calls must keep the same deterministic result as an unbounded
--call, including layouts that consider blocked belt and hand tiles for repair.
local H = require "tests.harness"
local Power = require "logic.bp.power"

local function fixture()
    local consumers, occupied = {}, {}
    for i = 1, 20 do
        local x, y = 5 + ((i - 1) % 5) * 18, 5 + math.floor((i - 1) / 5) * 21
        consumers[#consumers + 1] = {id = string.format("machine-%02d", i), rect = {x = x, y = y, w = 3, h = 3}}
        occupied[#occupied + 1] = {kind = "machine", rect = {x = x, y = y, w = 3, h = 3}}
    end
    for i = 1, 50 do
        local x, y = 8 + ((i - 1) % 10) * 8, 10 + math.floor((i - 1) / 10) * 17
        consumers[#consumers + 1] = {id = string.format("hand-%02d", i), rect = {x = x, y = y, w = 1, h = 1}}
        occupied[#occupied + 1] = {kind = "inserter", rect = {x = x, y = y, w = 1, h = 1}}
    end
    for i = 1, 12 do
        occupied[#occupied + 1] = {kind = "belt", rect = {x = 12 + i * 5, y = 30, w = 1, h = 1}}
    end
    return {grid_w = 180, grid_h = 140, consumers = consumers, occupied = occupied,
        make_room = function() return true end,
        pole = {name = "medium-electric-pole", tile_w = 1, tile_h = 1,
            supply_w = 12, supply_h = 12, wire_reach = 36},
        limits = {max_poles = 32}}
end

local function run(input, budget)
    local state, worst, calls = Power.begin(input), 0, 0
    while not state.done and calls < 1000000 do
        local started = os.clock()
        Power.step(state, {ops = budget})
        local elapsed = os.clock() - started
        if elapsed > worst then worst = elapsed end
        calls = calls + 1
    end
    H.equal(state.done, true, "power state completes")
    H.equal(state.ok, true, "power result succeeds")
    return state.result, worst
end

H.test("2000-op ticks stay short and preserve poles and wires", function()
    local input = fixture()
    local sliced, worst = run(input, 2000)
    local whole = run(input, 1000000000)
    H.equal(worst <= 0.05, true, "worst Power.step tick is " .. string.format("%.4f", worst) .. " s")
    H.deep_equal({entities = sliced.entities, wires = sliced.wires},
        {entities = whole.entities, wires = whole.wires}, "budget size does not change poles or wires")
end)

H.done("test_power_ticks")
