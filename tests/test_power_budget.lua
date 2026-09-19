--The power cursor is deliberately tested as a scheduler boundary.  A caller
--may stop after any charged unit and carry the plain state to a later tick.
local H = require "tests.harness"
local Power = require "logic.bp.power"

local function fixture()
    local consumers, occupied = {}, {}
    for row = 0, 2 do
        for column = 1, 5 do
            local x, y = 4 + column * 7, 6 + row * 14
            consumers[#consumers + 1] = {id = "m" .. row .. column, rect = {x = x, y = y, w = 3, h = 3}}
            occupied[#occupied + 1] = {rect = {x = x, y = y, w = 3, h = 3}}
        end
    end
    return {
        grid_w = 54, grid_h = 54, consumers = consumers, occupied = occupied,
        pole = {name = "medium-electric-pole", tile_w = 1, tile_h = 1,
            supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
    }
end

local function run(input, slice)
    local state = Power.begin(input)
    local ticks = 0
    while not state.done and ticks < 500000 do
        Power.step(state, {ops = slice})
        ticks = ticks + 1
    end
    H.equal(state.done, true, "budget fixture completes")
    H.equal(state.result ~= nil, true, "budget fixture publishes")
    return state, ticks
end

local function assert_plain(value, seen, path)
    local kind = type(value)
    if kind == "function" or kind == "userdata" or kind == "thread" then
        error("non-plain " .. kind .. " reachable at " .. path, 0)
    end
    if kind ~= "table" then return end
    H.equal(getmetatable(value), nil, "state has no metatable at " .. path)
    seen[value] = true
    for key, child in pairs(value) do
        local child_path = path .. "." .. tostring(key)
        if type(child) == "table" then
            if not seen[child] then assert_plain(child, seen, child_path) end
        else
            assert_plain(child, seen, child_path)
        end
    end
end

local function poles_and_wires(result)
    return {entities = result.entities, wires = result.wires}
end

H.test("one operation and a large slice publish the same result", function()
    local one = run(fixture(), 1)
    local all = run(fixture(), 10 ^ 6)
    H.deep_equal(poles_and_wires(one.result), poles_and_wires(all.result),
        "slice size does not change poles or wires")
end)

H.test("an interrupted selection state resumes identically", function()
    local uninterrupted = run(fixture(), 10 ^ 6).result
    local state = Power.begin(fixture())
    local ticks = 0
    while state.cursor.phase ~= "greedy" and ticks < 100000 do
        Power.step(state, {ops = 1})
        ticks = ticks + 1
    end
    H.equal(state.cursor.phase, "greedy", "the interruption occurs before selection completes")
    local carried_state = state
    while not carried_state.done and ticks < 500000 do
        Power.step(carried_state, {ops = 1})
        ticks = ticks + 1
    end
    H.equal(carried_state.done, true, "carried state resumes")
    H.deep_equal(poles_and_wires(uninterrupted), poles_and_wires(carried_state.result),
        "resuming a mid-selection state is deterministic")
end)

H.test("the resumable state contains only plain data", function()
    local state = Power.begin(fixture())
    for _ = 1, 200 do
        Power.step(state, {ops = 1})
        if state.cursor.phase == "candidate_coverage" then break end
    end
    assert_plain(state, {}, "state")
end)

H.test("a scheduler can observe cancellation between two charged steps", function()
    local state = Power.begin(fixture())
    local cancelled = false
    for _ = 1, 2 do
        Power.step(state, {ops = 1})
        if not state.done then
            --Cancellation belongs to the job scheduler: it drops this state
            --at the next boundary.  No inner candidate scan can delay that
            --observation.
            cancelled = true
            break
        end
    end
    H.equal(cancelled, true, "cancellation is observable within two steps")
end)

H.done("test_power_budget")
