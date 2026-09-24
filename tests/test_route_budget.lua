--Route work is measured in deterministic search operations, never in host time.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local FROZEN = "tests/fixtures/routing/player_chain_first_candidate.lua"

local function error_code(state)
    return state.errors and state.errors[1] and state.errors[1].code
end

local function run(input, slice)
    local state = Route.begin(input)
    local spent, ticks = 0, 0
    while not state.done and ticks < 200000 do
        ticks = ticks + 1
        local budget = {ops = slice}
        Route.step(state, budget)
        spent = spent + slice - budget.ops
    end
    H.equal(state.done, true, "route finishes within the tick bound")
    return state, spent
end

local function unroutable_input()
    return {
        grid = Grid.new(12, 5),
        max_expansions = 500,
        catalog = {belt = {belt = "basic-belt", items_per_second = 10}},
        obstacles = {{x = 5, y = 0, w = 1, h = 5, owner = "wall"}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 2, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/wall", rate_per_second = 1,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
            }},
            {block_id = "consumer", machines = {{step_id = "consumer"}}, x = 8, y = 2, w = 1, h = 1, ports = {
                {port_id = "consumer-in", role = "in", kind = "item", flow_id = "item/wall", rate_per_second = 1,
                    attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST},
            }},
        },
        flows = {{flow_id = "item/wall", is_fluid = false,
            producers = {{step_id = "source", share_per_second = 1}},
            consumers = {{step_id = "consumer", share_per_second = 1}}}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RB1 the frozen candidate routes inside its measured operation bound", function()
        local input = dofile(FROZEN)
        local state, spent = run(input, 1000000)
        H.equal(state.ok, true, "frozen candidate routes")
        H.equal(state.counters ~= nil, true, "route exposes deterministic counters")
        --Measured replay is 10644 operations on the lane host; this bound leaves room for harmless ordering
        --changes while detecting a return to the multi-million-operation sweep.
        H.equal(spent <= 20000, true, "frozen candidate stays within the measured operation bound")
        H.equal(state.counters.expansions <= state.work.max_expansions, true,
            "frozen expansion counter stays within the run budget")
        H.equal(state.counters.expansions, state.work.expansions, "work and public expansion counters agree")
    end)

    H.test(shape .. " RB2 sliced and unsliced route steps commit the same result", function()
        local fast = run(dofile(FROZEN), 1000000)
        local sliced = run(dofile(FROZEN), 1)
        H.deep_equal(sliced.result, fast.result, "slice size does not change the committed route")
        H.equal(sliced.counters.expansions, fast.counters.expansions,
            "slice size does not change measured expansions")
        H.equal(sliced.counters.restarts, fast.counters.restarts,
            "slice size does not change restart count")
    end)

    H.test(shape .. " RB3 the expansion budget is cumulative across retries and restarts", function()
        local state = run(unroutable_input(), 1000000)
        H.equal(state.ok, false, "the wall-separated demand is rejected")
        H.equal(error_code(state), "BP_R_EXPANSIONS", "the cumulative budget has its own outcome")
        H.equal(state.counters.expansions <= state.work.max_expansions, true,
            "total expansions never exceed the configured budget")
        H.equal(state.counters.expansions, state.work.max_expansions,
            "the budget outcome consumes exactly the available expansions")
        H.equal(state.work.expansions, state.counters.expansions,
            "the internal expansion count is not reset by a retry")
        H.equal(state.counters.restarts > 0, true, "the case exercised a demand-order restart")
        H.equal(state.counters.searches_abandoned.expansions > 0, true,
            "the exhausted search is counted by reason")
    end)

    H.test(shape .. " RB4 cancellation clears every half-written segment list", function()
        local state = Route.begin(dofile(FROZEN))
        --Demand pairing now consumes route operations before the first geometry is searched.
        --Advance until routing has published a partial segment, then exercise cancellation.
        local ticks = 0
        while #state.work.segments == 0 and not state.done and ticks < 2000 do
            ticks = ticks + 1
            Route.step(state, {ops = 500})
        end
        H.equal(#state.work.segments > 0, true, "the cancellation starts after route work exists")
        Route.cancel(state)
        H.equal(state.done, true, "cancelled route is terminal")
        H.equal(state.ok, false, "cancelled route does not commit")
        H.equal(state.result, nil, "cancelled route has no result")
        H.equal(#state.work.segments, 0, "cancelled route has no working segments")
        H.equal(#state.work.entities, 0, "cancelled route has no working entities")
    end)
end

H.done("test_route_budget")
