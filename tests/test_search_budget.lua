--Focused search-policy tests.  The stage doubles below keep the cases about grid breadth and
--publication, rather than making them depend on the route and pole searcher's current cost.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Pack = require "logic.bp.pack"
local Power = require "logic.bp.power"
local Route = require "logic.bp.route"
local Search = require "logic.bp.search"
local Validate = require "logic.bp.validate"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function plan()
    return {steps = {{step_id = "one", machine = "assembler", machine_count = 1}}, flows = {}, ports = {}}
end

local function stage()
    return {done = false, ok = nil, result = nil, cursor = {}, progress = {}}
end

local function run_with_stages(options, callback)
    local candidates = options.candidates
    local score_for = options.score_for
    local originals = {
        groups_begin = Groups.begin, groups_step = Groups.step, materialize = Groups.materialize,
        pack_begin = Pack.begin, pack_step = Pack.step,
        route_begin = Route.begin, route_step = Route.step,
        power_begin = Power.begin, power_step = Power.step,
        validate_begin = Validate.begin, validate_step = Validate.step,
    }

    Groups.begin = function()
        return stage()
    end
    Groups.step = function(state, budget)
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {candidates = clone(candidates)}
            state.done, state.ok = true, #candidates > 0
        end
        return state
    end
    Groups.materialize = function(block, placement)
        return {
            envelope = {x = placement.x, y = placement.y, w = block.w, h = block.h, dir = 0},
            entities = {{id = block.id .. ":machine", name = "assembler", x = placement.x, y = placement.y,
                w = 1, h = 1}}, ports = {},
        }
    end

    Pack.begin = function(input)
        local block = input.blocks[1]
        local result = stage()
        result.placement = {block_id = block.id, x = 0, y = 0, w = block.w, h = block.h}
        return result
    end
    Pack.step = function(state, budget)
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {placements = {state.placement}}
            state.done, state.ok = true, true
        end
        return state
    end

    local function empty_stage()
        local result = stage()
        result.result = {entities = {}, wires = {}, segments = {}, bindings = {}}
        return result
    end
    Route.begin = function() return empty_stage() end
    Route.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1; state.done, state.ok = true, true end
        return state
    end
    Power.begin = function() return empty_stage() end
    Power.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1; state.done, state.ok = true, true end
        return state
    end

    Validate.begin = function(input)
        local result = stage()
        result.score = clone(score_for(input.candidate))
        return result
    end
    Validate.step = function(state, budget)
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {score = state.score, metrics = {}}
            state.done, state.ok = true, true
        end
        return state
    end

    local ok, result = pcall(callback)

    Groups.begin, Groups.step, Groups.materialize = originals.groups_begin, originals.groups_step, originals.materialize
    Pack.begin, Pack.step = originals.pack_begin, originals.pack_step
    Route.begin, Route.step = originals.route_begin, originals.route_step
    Power.begin, Power.step = originals.power_begin, originals.power_step
    Validate.begin, Validate.step = originals.validate_begin, originals.validate_step

    if not ok then error(result, 0) end
    return result
end

local function candidate(id, w, physical_beacons)
    return {id = id, blocks = {{id = id, w = w, h = w, port_sides = {}}},
        physical_beacon_count = physical_beacons, beacon_count = physical_beacons}
end

local function search_input(grids, candidates, extra)
    local input = {plan_result = plan(), grids = grids, include_roboports = false}
    for key, value in pairs(extra or {}) do input[key] = value end
    return input, candidates
end

local function finish(state, slice)
    local ticks = 0
    while not state.done and ticks < 10000 do
        ticks = ticks + 1
        Search.step(state, {ops = slice or 1000})
    end
    H.equal(state.done, true, "search finishes within the bounded test ticks; phase " .. tostring(state.phase))
    return state
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " search visits a larger grid for a lower-beacon candidate", function()
        local high = candidate("high", 1, 2)
        local low = candidate("low", 3, 1)
        local input, candidates = search_input({{w = 2, h = 2}, {w = 3, h = 3}}, {high, low})
        local state = run_with_stages({candidates = candidates, score_for = function(value)
            return value.grid_w == 2 and {beacon_count = 2, footprint_area = 1, pole_count = 1}
                or {beacon_count = 1, footprint_area = 2, pole_count = 1}
        end}, function()
            return finish(Search.begin(input))
        end)
        H.equal(state.ok, true, "the larger-grid search publishes a layout")
        H.equal(state.incumbent.score.beacon_count, 1, "the larger grid's lower beacon count wins")
        H.equal(state.incumbent.candidate.grid_w, 3, "the lower-beacon candidate came from the larger grid")
    end)

    H.test(shape .. " equal-score layouts are deterministic", function()
        local first_candidate = candidate("first", 1, 0)
        local second_candidate = candidate("second", 1, 0)
        local function execute()
            local input, candidates = search_input({{w = 2, h = 2}}, {first_candidate, second_candidate})
            return run_with_stages({candidates = candidates, score_for = function()
                return {beacon_count = 1, footprint_area = 1, pole_count = 1, route_length = 0,
                    entity_count = 1, coord_key = "equal"}
            end}, function() return finish(Search.begin(input)) end)
        end
        local first, second = execute(), execute()
        H.deep_equal(first.result, second.result, "equal-score runs publish the same layout")
        H.equal(first.incumbent.candidate.blocks[1].id, "first", "the deterministic first layout wins the tie")
    end)

    H.test(shape .. " different tick slices publish the same result", function()
        local function execute(slice)
            local high = candidate("high", 1, 2)
            local low = candidate("low", 3, 1)
            local input, candidates = search_input({{w = 2, h = 2}, {w = 3, h = 3}}, {high, low})
            return run_with_stages({candidates = candidates, score_for = function(value)
                return value.grid_w == 2 and {beacon_count = 2, footprint_area = 1, pole_count = 1}
                    or {beacon_count = 1, footprint_area = 2, pole_count = 1}
            end}, function() return finish(Search.begin(input), slice) end)
        end
        local small_slice, large_slice = execute(1), execute(1000)
        H.deep_equal(small_slice.result, large_slice.result, "tick slicing does not change publication")
    end)

    H.test(shape .. " budget exhaustion with an incumbent publishes it", function()
        local high = candidate("high", 1, 2)
        local extra = candidate("extra", 1, 0)
        local input, candidates = search_input({{w = 2, h = 2}, {w = 3, h = 3}}, {high, extra})
        local state = run_with_stages({candidates = candidates, score_for = function(value)
            local block_id = value.blocks[1] and value.blocks[1].block_id
            return block_id == "high" and {beacon_count = 2, footprint_area = 1, pole_count = 1}
                or {beacon_count = 1, footprint_area = 1, pole_count = 1}
        end}, function()
            local current = Search.begin(input)
            local ticks = 0
            while current.incumbent == nil and not current.done and ticks < 100 do
                ticks = ticks + 1
                Search.step(current, {ops = 1})
            end
            H.equal(current.incumbent ~= nil, true, "the bounded run first obtains a complete incumbent")
            H.equal(current.done, false, "the incumbent is found before the work bound ends")
            current.max_ops = current.ops_used
            Search.step(current, {ops = 1})
            H.equal(current.done, false, "publication has a reserved serialization phase")
            finish(current, 1000)
            return current
        end)
        H.equal(state.ok, true, "the incumbent survives search-budget exhaustion")
        H.equal(state.result ~= nil, true, "the incumbent is serialized after exhaustion")
        H.equal(state.errors, nil, "publishing an incumbent is not reported as a search failure")
        H.equal(state.incumbent.score.beacon_count, 2, "the fully validated incumbent remains selected")
    end)

    H.test(shape .. " budget exhaustion without an incumbent reports the budget code", function()
        local only = candidate("only", 1, 0)
        local input, candidates = search_input({{w = 2, h = 2}}, {only}, {max_ops = 1})
        local state = run_with_stages({candidates = candidates, score_for = function()
            return {beacon_count = 0, footprint_area = 1, pole_count = 1}
        end}, function() return Search.step(Search.begin(input), {ops = 100}) end)
        H.equal(state.done, true, "the no-incumbent budget run ends")
        H.equal(state.ok, false, "the no-incumbent budget run fails")
        H.equal(state.errors[1].code, "BP_FAIL_SEARCH_BUDGET", "work exhaustion has the budget code")
        H.equal(state.errors[1].code == "BP_FAIL_NO_LAYOUT_GRID_LIMIT", false,
            "work exhaustion never claims an unsupported sheet")
    end)
end

H.done("test_search_budget")
