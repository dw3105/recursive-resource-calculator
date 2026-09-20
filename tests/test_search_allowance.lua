--The derived search allowance covers the bounded pipeline and is independent of any one candidate's outcome.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Pack = require "logic.bp.pack"
local Route = require "logic.bp.route"
local Power = require "logic.bp.power"
local Search = require "logic.bp.search"
local Serialize = require "logic.bp.serialize"
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

local function stage()
    return {done = false, ok = nil, result = nil, cursor = {}, progress = {}}
end

local function plan()
    return {steps = {{step_id = "one", machine = "assembler", machine_count = 1}}, flows = {}, ports = {}}
end

local function candidate(id)
    return {id = id, blocks = {{id = id, block_id = id, w = 1, h = 1, port_sides = {}}},
        physical_beacon_count = 1, beacon_count = 1}
end

local function input_for(extra)
    local input = {plan_result = plan(), grids = {{w = 2, h = 2}, {w = 3, h = 3}}, include_roboports = false,
        max_search_grids = 2}
    for key, value in pairs(extra or {}) do input[key] = value end
    return input
end

local function install(candidates, counts)
    local originals = {
        groups_begin = Groups.begin, groups_step = Groups.step, materialize = Groups.materialize,
        pack_begin = Pack.begin, pack_step = Pack.step,
        route_begin = Route.begin, route_step = Route.step,
        power_begin = Power.begin, power_step = Power.step,
        validate_begin = Validate.begin, validate_step = Validate.step,
        serialize_begin = Serialize.begin, serialize_step = Serialize.step,
    }
    local function finish(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1; state.done, state.ok = true, true end
        return state
    end
    Groups.begin = function() return stage() end
    Groups.step = function(state, budget)
        counts.groups = counts.groups + 1
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {candidates = clone(candidates)}
            state.done, state.ok = true, true
        end
        return state
    end
    Groups.materialize = function(block, placement)
        return {envelope = {x = placement.x, y = placement.y, w = block.w, h = block.h, dir = 0},
            entities = {{id = block.id .. ":machine", name = "assembler", x = placement.x, y = placement.y,
                w = 1, h = 1}}, ports = {}}
    end
    Pack.begin = function(input)
        local state = stage()
        local block = input.blocks[1]
        state.placement = {block_id = block.block_id or block.id, x = 0, y = 0, w = block.w, h = block.h}
        return state
    end
    Pack.step = function(state, budget)
        counts.pack = counts.pack + 1
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {placements = {state.placement}}
            state.done, state.ok = true, true
        end
        return state
    end
    Route.begin = function() return stage() end
    Route.step = function(state, budget)
        counts.route = counts.route + 1
        state.result = {entities = {}, wires = {}, segments = {}, bindings = {}}
        return finish(state, budget)
    end
    Power.begin = function() return stage() end
    Power.step = function(state, budget)
        counts.power = counts.power + 1
        state.result = {entities = {}, wires = {}}
        return finish(state, budget)
    end
    Validate.begin = function(input)
        local state = stage()
        state.score = {beacon_count = input.candidate.grid_w == 2 and 2 or 1, footprint_area = 1, pole_count = 1}
        return state
    end
    Validate.step = function(state, budget)
        counts.validate = counts.validate + 1
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {score = state.score, metrics = {}}
            state.done, state.ok = true, true
        end
        return state
    end
    Serialize.begin = function() counts.serialize_begin = counts.serialize_begin + 1; return stage() end
    Serialize.step = function(state, budget)
        counts.serialize = counts.serialize + 1
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {entities = {}}
            state.done, state.ok = true, true
        end
        return state
    end
    return function()
        Groups.begin, Groups.step, Groups.materialize = originals.groups_begin, originals.groups_step, originals.materialize
        Pack.begin, Pack.step = originals.pack_begin, originals.pack_step
        Route.begin, Route.step = originals.route_begin, originals.route_step
        Power.begin, Power.step = originals.power_begin, originals.power_step
        Validate.begin, Validate.step = originals.validate_begin, originals.validate_step
        Serialize.begin, Serialize.step = originals.serialize_begin, originals.serialize_step
    end
end

local function finish(state, slice)
    local ticks = 0
    while not state.done and ticks < 10000 do
        ticks = ticks + 1
        Search.step(state, {ops = slice or 1000})
    end
    H.equal(state.done, true, "the allowance test reaches a terminal state")
    return state
end

local function counts()
    return {groups = 0, pack = 0, route = 0, power = 0, validate = 0, serialize = 0, serialize_begin = 0}
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " an allowance covers one full grid and several candidates", function()
        local candidates, used = {candidate("one"), candidate("two"), candidate("three")}, counts()
        local restore = install(candidates, used)
        local state = finish(Search.begin(input_for()))
        restore()
        H.equal(type(state.max_ops), "number", "the derived allowance is finite")
        H.equal(state.max_ops < math.huge, true, "the derived allowance is bounded")
        H.equal(state.ok, true, "the complete pipeline publishes")
        H.equal(used.pack >= #candidates, true, "several candidates are packed")
        H.equal(used.route >= #candidates, true, "several candidates are routed")
        H.equal(used.power >= #candidates, true, "several candidates reach power")
        H.equal(used.validate >= #candidates, true, "several candidates are validated")
        H.equal(used.serialize_begin, 1, "publication is entered once")
    end)

    H.test(shape .. " an exhausted allowance keeps and serializes its incumbent", function()
        local candidates, used = {candidate("one"), candidate("two")}, counts()
        local restore = install(candidates, used)
        local state = Search.begin(input_for{max_search_grids = 1})
        local ticks = 0
        while state.incumbent == nil and not state.done and ticks < 100 do
            ticks = ticks + 1
            Search.step(state, {ops = 1})
        end
        H.equal(state.incumbent ~= nil, true, "the incumbent is complete before the forced exhaustion")
        state.max_ops = state.ops_used
        finish(state, 100)
        restore()
        H.equal(state.ok, true, "serialization completes after exhaustion")
        H.equal(state.result ~= nil, true, "the incumbent is serialized")
        H.equal(state.errors, nil, "the incumbent is never converted to a failure")
    end)

    H.test(shape .. " an allowance exhausted without an incumbent reports search budget", function()
        local candidates, used = {candidate("only")}, counts()
        local restore = install(candidates, used)
        local state = Search.step(Search.begin(input_for{grids = {{w = 2, h = 2}}, max_search_grids = 1, max_ops = 1}),
            {ops = 100})
        restore()
        H.equal(state.done, true, "the explicit allowance ends the run")
        H.equal(state.ok, false, "the run has no incumbent")
        H.equal(state.errors[1].code, "BP_FAIL_SEARCH_BUDGET", "the explicit allowance is the budget cause")
    end)

    H.test(shape .. " identical inputs derive identical allowances", function()
        local function derive()
            local candidates, used = {candidate("one"), candidate("two"), candidate("three")}, counts()
            local restore = install(candidates, used)
            local state = Search.begin(input_for())
            while not state.work.allowance_declared and not state.done do Search.step(state, {ops = 1}) end
            local allowance = state.max_ops
            restore()
            return allowance
        end
        H.equal(derive(), derive(), "the same problem derives the same allowance")
    end)
end

H.done("test_search_allowance")
