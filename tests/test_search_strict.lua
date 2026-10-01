--ST1 red on round-49-base: belt-shape validation must restart the same grid with strict route ends.
local H = require "tests.harness"
local Search = require "logic.bp.search"
local D = require "tests.fixtures.search_doubles"
local Route = require "logic.bp.route"
local Validate = require "logic.bp.validate"

local function scenario(codes, always_fail)
    local route_inputs, validations = {}, 0
    local originals = {Route.begin, Route.step, Validate.begin, Validate.step}
    local function restore()
        Route.begin, Route.step, Validate.begin, Validate.step = originals[1], originals[2], originals[3], originals[4]
    end
    local ok, state = pcall(function()
        return D.run({}, function()
            Route.begin = function(input)
                route_inputs[#route_inputs + 1] = {strict_ends = input.strict_ends, grid = input.grid}
                return {done = true, ok = true, result = {entities = {}, wires = {}, segments = {}, bindings = {}}, cursor = {}, progress = {}}
            end
            Route.step = function(s) return s end
            Validate.begin = function(input)
                validations = validations + 1
                local code = codes[validations] or (always_fail and "BP_V_BELT_BLEED")
                return {done = true, ok = code == nil, errors = code and {{code = code}} or nil,
                    result = {score = {beacon_count = 0}, metrics = {}}, cursor = {}, progress = {}}
            end
            Validate.step = function(s) return s end
            local result = Search.begin(D.input())
            local ticks = 0
            while not result.done and ticks < 600 do ticks = ticks + 1; Search.step(result, {ops = 100}) end
            return result
        end)
    end)
    restore()
    if not ok then error(state, 0) end
    -- D.run returns state, log; pcall callback result preserves only first return.
    return state, route_inputs
end

local function bounded_finish(state, phase)
    local ticks = 0
    while not state.done and ticks < 600 do ticks = ticks + 1; Search.step(state, {ops = 100}) end
    H.equal(state.done, true, "not stuck in phase " .. tostring(state.phase or phase))
    return state
end

H.test("ST1 belt refusal reroutes same grid strictly and delivers", function()
    local state, routes = scenario({[1] = "BP_V_BELT_BLEED"})
    H.equal(state.ok, true, "delivered")
    H.equal(#routes, 2, "two route inputs")
    H.equal(routes[1].strict_ends, nil, "first route non-strict")
    H.equal(routes[2].strict_ends, true, "redo strict")
    H.equal(routes[1].grid.w, routes[2].grid.w, "same grid")
end)

H.test("ST2 non-shape refusal follows ordinary retry", function()
    local state, routes = scenario({[1] = "BP_V_COLLISION"})
    H.equal(state.ok, true, "eventually delivered")
    H.equal(routes[1].strict_ends, nil, "initial route non-strict")
    H.equal(routes[2].strict_ends, nil, "next candidate remains non-strict")
end)

H.test("ST3 each belt refusal gets one strict redo then next candidate starts non-strict", function()
    local state, routes = scenario({}, true)
    state = bounded_finish(state, state.phase)
    H.equal(state.ok, false, "search fails")
    H.equal(state.errors[1].code, "BP_FAIL_NO_LAYOUT", "no layout")
    --Round 54: three last-resort inset rounds (3, 6, 9) follow the four ordinary candidates, each routed twice too.
    H.equal(#routes, 14, "four candidates and three inset rounds each route twice")
    for i = 1, #routes, 2 do
        H.equal(routes[i].strict_ends, nil, "candidate starts non-strict " .. i)
        H.equal(routes[i + 1].strict_ends, true, "strict redo " .. (i + 1))
    end
end)

print("ST1 ST2 ST3")
H.done("test_search_strict")
