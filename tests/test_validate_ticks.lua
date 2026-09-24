-- Regression for validation work that used to scan every entity pair in one call.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"

local entities = {}
for i = 1, 300 do
    entities[#entities + 1] = {id = "belt-" .. i, kind = "belt", name = "belt", x = i * 2, y = 0, w = 1, h = 1}
end
for i = 1, 40 do
    entities[#entities + 1] = {id = "hand-" .. i, kind = "inserter", name = "hand", x = 1000 + i * 2, y = 0, w = 1, h = 1}
end
local input = {grid = {w = 2000, h = 10}, catalog = {belt = {items_per_second = 1},
    inserter = {items_per_second = 1}}, entities = entities}

local function run(ops)
    local state = Validate.begin(input)
    while not state.done do Validate.step(state, {ops = ops}) end
    return state
end

H.test("validation calls respect the game tick budget and preserve errors", function()
    local reference = run(1000000000)
    local state = Validate.begin(input)
    local longest = 0
    while not state.done do
        local before = os.clock()
        Validate.step(state, {ops = 2000})
        longest = math.max(longest, os.clock() - before)
    end
    H.deep_equal(state.errors, reference.errors, "budgeted and one-call errors match")
    H.equal(longest <= 0.03, true, "no validation step takes over 30 ms")
end)

H.done("test_validate_ticks")
