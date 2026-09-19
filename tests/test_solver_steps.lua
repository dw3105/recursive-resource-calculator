--The solver keeps its answers when a quality calculation is sliced one operation at a time, including a feed search.
local H = require "tests.harness"

local Steps
local Solver
local QualityId
local QualityLoops

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[copy(key)] = copy(child) end
    return result
end

local function modules(name, count)
    local result = {}
    for index = 1, count or 4 do result[index] = {name = name} end
    return result
end

local function world_for(shape, quality_source)
    local world = H.new_world(shape)
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    for _, item in ipairs({"A", "X"}) do world.add_item(item) end
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4})
    world.add_machine({name = quality_source and "miner" or "miner0", categories = {"mining"}, speed = 1, energy_kw = 50,
        module_slots = 0, base_quality = quality_source and 1 or nil})
    world.add_recipe({name = "X-craft", ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "A-make", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_player(1)
    world.init()
    world.bind("item/X", "X-craft")
    world.bind("item/A", "A-make")
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["X-craft"] = {name = "assembler"}
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["A-make"] = {name = quality_source and "miner" or "miner0"}
    Steps = require "logic.solver_steps"
    Solver = require "logic.solver"
    QualityId = require "logic.quality_id"
    QualityLoops = require "logic.quality_loops"
    return world
end

local function quality_input(quality_source)
    local key = QualityId.encode("X", "uncommon")
    local parts = {type = "item", name = "X", quality = "uncommon"}
    local config = QualityLoops.normalized(1, key, parts)
    config.crafts.normal.setup.modules = modules("q")
    config.crafts.uncommon.setup.modules = modules("q")
    QualityLoops.store(1, key, config)
    return {rates = {[key] = 1}, player_index = 1, product_parts = {[key] = parts}, options = nil}
end

local function step_to_end(state, operations)
    local count = 0
    while not state.done and count < 200000 do
        Steps.step(state, {ops = operations})
        count = count + 1
    end
    H.equal(state.done, true, "sliced solve completes")
    return state, count
end

local function answer(result)
    local columns = {}
    for index, column in ipairs(result.columns or {}) do
        local info = column.quality_loop
        columns[index] = {recipe_name = column.recipe_name, product_full_name = column.product_full_name,
            binding_full_name = column.binding_full_name, quality_loop = info and {
                key = info.key, item = info.item, quality = info.quality, reason = info.reason, forced = info.forced,
                craft_recipe_name = info.craft_recipe_name, recycle_recipe_name = info.recycle_recipe_name,
                start_leftovers = info.start_leftovers,
            } or nil}
    end
    return {status = result.status, recipe_rates = result.recipe_rates, solved_rates = result.solved_rates,
        unsolved_rates = result.unsolved_rates, reasons_by_column = result.reasons_by_column,
        product_parts = result.product_parts, feed_rounds = result.feed_rounds, columns = columns}
end

local function assert_same(reference, state, what)
    H.deep_equal(state.result and answer(state.result), answer(reference), what)
end

local function assert_plain(value, path, seen)
    local value_type = type(value)
    H.equal(value_type == "function" or value_type == "userdata", false, path .. " is plain")
    if value_type ~= "table" then return end
    H.equal(getmetatable(value), nil, path .. " has no metatable")
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        assert_plain(key, path .. ".<key>", seen)
        assert_plain(child, path .. "." .. tostring(key), seen)
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " S1 quality fixture has identical one-operation and unbounded answers", function()
        world_for(shape, false)
        local input = quality_input(false)
        local state, one_at_a_time = step_to_end(Steps.begin(copy(input)), 1)
        local unbounded_state, unbounded = step_to_end(Steps.begin(copy(input)), math.huge)
        local reference = Solver._solve_for_sync(input.rates, input.player_index, copy(input.product_parts), input.options)
        assert_same(reference, state, "quality answer")
        H.deep_equal(answer(state.result), answer(unbounded_state.result), "quality fixture fields")
        H.equal(one_at_a_time > unbounded, true, "one operation takes more steps")
        local work = 0
        for _, units in pairs(state.work) do work = work + units end
        H.equal(one_at_a_time <= work + 8, true, "one-operation steps stay bounded by recorded work")
    end)

    H.test(shape .. " S2 feed fixture preserves rates statuses recipe choices and feed rounds", function()
        world_for(shape, true)
        local input = quality_input(true)
        local state = step_to_end(Steps.begin(copy(input)), 1)
        local reference = Solver._solve_for_sync(input.rates, input.player_index, copy(input.product_parts), input.options)
        assert_same(reference, state, "feed answer")
        H.equal(state.result.feed_rounds, reference.feed_rounds, "feed rounds")
    end)

    H.test(shape .. " S3 sliced state is plain and survives a plain-data round trip", function()
        world_for(shape, true)
        local input = quality_input(true)
        local state = Steps.begin(copy(input))
        Steps.step(state, {ops = 1})
        assert_plain(state, "state")
        local resumed = copy(state)
        step_to_end(resumed, 1)
        local reference = Solver._solve_for_sync(input.rates, input.player_index, copy(input.product_parts), input.options)
        assert_plain(resumed, "resumed state")
        assert_same(reference, resumed, "round-tripped answer")
    end)

    H.test(shape .. " S4 infeasible and unsolvable sheets keep their statuses through slices", function()
        local world = H.new_world(shape)
        world.add_item("P")
        world.add_item("Q")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "backwards", ingredients = {{name = "P", amount = 2}}, products = {{name = "P", amount = 1}}})
        world.add_recipe({name = "same", ingredients = {}, products = {{name = "P", amount = 1}, {name = "Q", amount = 1}}})
        world.add_recipe({name = "same-2", ingredients = {}, products = {{name = "P", amount = 1}, {name = "Q", amount = 1}}})
        world.add_player(1)
        world.init()
        world.bind("item/P", "backwards")
        local infeasible = {rates = {["item/P"] = 1}, player_index = 1, product_parts = {}, options = nil}
        local infeasible_state = step_to_end(Steps.begin(copy(infeasible)), 1)
        local infeasible_reference = Solver._solve_for_sync(infeasible.rates, 1, {}, nil)
        assert_same(infeasible_reference, infeasible_state, "infeasible answer")

        world.bind("item/P", "same")
        world.bind("item/Q", "same-2")
        local unsolvable = {rates = {["item/P"] = 1, ["item/Q"] = 1}, player_index = 1, product_parts = {}, options = nil}
        local unsolvable_state = step_to_end(Steps.begin(copy(unsolvable)), 1)
        local unsolvable_reference = Solver._solve_for_sync(unsolvable.rates, 1, {}, nil)
        assert_same(unsolvable_reference, unsolvable_state, "unsolvable answer")
    end)
    --A calculated column is the sheet's own record of how a step was computed. Without the machine and the
    --module setup on the column, the debug export shows numbers nobody can check, and every later reader has to
    --guess the binding again.
    H.test(shape .. " S9 every calculated column carries the machine and setup it was computed with", function()
        world_for(shape, false)
        storage[1].module_setups_by_recipe_name["X-craft"] = {modules = {{name = "q", quality = "normal"}}, beacons = {}}
        local result = Solver._solve_for_sync({[ "item/X" ] = 1}, 1, {}, nil)
        local by_recipe = {}
        for _, column in ipairs(result.columns or {}) do by_recipe[column.recipe_name] = column end
        local craft = by_recipe["X-craft"]
        H.equal(craft ~= nil, true, "the craft column exists")
        H.equal(type(craft.machine), "table", "the craft column carries its machine")
        H.equal(craft.machine.name, "assembler", "and names the chosen machine")
        H.equal(type(craft.setup), "table", "the craft column carries its module setup")
        H.equal(craft.setup.modules[1] ~= nil and craft.setup.modules[1].name, "q", "with the chosen module")
        local mine = by_recipe["A-make"]
        H.equal(mine ~= nil and type(mine.machine), "table", "the mining column carries its machine")
        H.equal(mine.machine.name, "miner0", "and names the mining machine")
        assert_plain(craft.machine, "column.machine")
        assert_plain(craft.setup, "column.setup")
    end)
end

H.done("test_solver_steps")
