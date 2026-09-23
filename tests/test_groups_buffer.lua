--Buffer-zone guarantees on grouped production blocks.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Buffer = require "logic.bp.buffer"

local catalog = {recipe = {
    two = {ingredients = {{name = "a"}, {name = "b"}}},
    three = {ingredients = {{name = "a"}, {name = "b"}, {name = "c"}}},
    five = {ingredients = {{name = "a"}, {name = "b"}, {name = "c"}, {name = "d"}, {name = "e"}}},
}}

local function plan(steps)
    return {steps = steps, flows = {}, ports = {}}
end

local function finish(input)
    local state = Groups.begin(input)
    for _ = 1, 600 do
        if state.done then return state end
        Groups.step(state, {ops = 1})
    end
    error("grouping did not finish")
end

local function first_candidate(input)
    local state = finish(input)
    H.equal(state.result ~= nil, true, "grouping publishes a result")
    H.equal(#state.result.candidates > 0, true, "grouping has a candidate")
    return state.result.candidates[1]
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " GB1 two same-recipe machines have compatible buffer zones", function()
        local candidate = first_candidate({plan = plan({
            {step_id = "pair", machine = "assembler", recipe = "two", machine_count = 2},
        }), catalog = catalog})
        H.equal(#candidate.blocks, 1, "one step is one block")
        local block = candidate.blocks[1]
        H.equal(#block.buffer_zones, 2, "each machine has a zone")
        for _, zone in ipairs(block.buffer_zones) do
            H.equal(zone.ring, 2, "two ingredients use ring 2")
            H.equal(zone.key, Buffer.key("assembler", "two"), "zone key uses machine and step recipe")
        end
        local a, b = block.buffer_zones[1], block.buffer_zones[2]
        H.equal(a.y == b.y or a.x == b.x, true, "same row or column")
        H.equal(Buffer.conflict({rect = a, ring = a.ring, key = a.key},
            {rect = b, ring = b.ring, key = b.key}), false, "same-line machines may share the ring")
    end)

    H.test(shape .. " GB2 ingredient count selects ring 3 and ring 4", function()
        for _, item in ipairs({{"three", 3}, {"five", 4}}) do
            local candidate = first_candidate({plan = plan({
                {step_id = item[1], machine = "assembler", recipe = item[1], machine_count = 1},
            }), catalog = catalog})
            H.equal(candidate.blocks[1].buffer_zones[1].ring, item[2], item[1] .. " ring width")
        end
    end)

    H.test(shape .. " GB3 different recipes always occupy separate blocks", function()
        local candidate = first_candidate({plan = plan({
            {step_id = "first", machine = "assembler", recipe = "two", machine_count = 1},
            {step_id = "second", machine = "assembler", recipe = "three", machine_count = 1},
        }), catalog = catalog})
        H.equal(#candidate.blocks, 2, "different recipes cannot share a block")
        for _, block in ipairs(candidate.blocks) do
            H.equal(#block.machines, 1, "one recipe per block")
            H.equal(#block.buffer_zones, 1, "zone exists for its machine")
        end
    end)
end

H.done("test_groups_buffer")
