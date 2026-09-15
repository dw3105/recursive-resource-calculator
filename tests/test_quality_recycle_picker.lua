--The loop's recycle recipe control: it lists only recipes that can recycle the item, and excess rows of a loop's own item hold that control
--instead of a consumer or burner control
local H = require "tests.harness"

local M = {} --modules loaded after each new world

--Two qualities (normal, uncommon). A -> X in an assembler; X -> 0.25 A in a recycler (category recycling); X -> gold (category sorting, a second
--eligible category); the recycler building takes X and Y (category crafting: takes X, cannot recycle it). Z -> made from A, consumed only with Y.
local function picker_world(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    world.add_item("A")
    world.add_item("X", options.x_fuel and {value = 1000000, category = "chemical"} or nil)
    world.add_item("Y")
    world.add_item("Z")
    world.add_item("gold")
    world.add_item("recycler-item")
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4})
    world.add_machine({name = "sorter", categories = {"sorting"}, speed = 1, energy_kw = 50, module_slots = 0})
    world.add_recipe({name = "X", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-recycling", category = "recycling", energy = 0.5, hidden = true, ingredients = {{name = "X", amount = 1}},
        products = {{name = "A", amount = 1, p = 0.25}}})
    world.add_recipe({name = "X-sorting-2", category = "sorting", energy = 1, ingredients = {{name = "X", amount = 1}}, products = {{name = "gold", amount = 1}}})
    world.add_recipe({name = "recycler-building", category = "crafting", energy = 1, ingredients = {{name = "X", amount = 1}, {name = "Y", amount = 1}},
        products = {{name = "recycler-item", amount = 1}}})
    world.add_recipe({name = "Z", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}}, products = {{name = "Z", amount = 1}}})
    world.add_recipe({name = "Z-plus", category = "crafting", energy = 1, ingredients = {{name = "Z", amount = 1}, {name = "Y", amount = 1}},
        products = {{name = "gold", amount = 1}}})
    world.add_recipe({name = "A-mining", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_recipe({name = "Y-mining", category = "mining", ingredients = {}, products = {{name = "Y", amount = 1}}})
    if options.x_fuel then
        world.add_burner({name = "tower", type = "reactor", energy_kw = 1000, emissions_per_joule = {}, burner = {fuel_categories = {"chemical"}}})
    end
    world.add_player(1)
    world.init()
    M.QualityId = require "logic.quality_id"
    M.QualityLoops = require "logic.quality_loops"
    M.Sheet = require "gui.sheet"
    require "gui.calculator" --registers the report's handlers
    return world
end

local function four(name)
    return {{name = name}, {name = name}, {name = name}, {name = name}}
end

--Stores the valid configuration of an item's loop with four q modules on every craft tier and the recycler pool
local function configure(item, quality)
    local key = M.QualityId.encode(item, quality)
    M.QualityLoops.store(1, key, M.QualityLoops.normalized(1, key, {type = "item", name = item, quality = quality}))
    local loop = storage[1].quality_loops_by_key[key]
    for _, settings in pairs(loop.crafts) do settings.setup.modules = four("q") end
    loop.recycle.setup.modules = four("q")
    return key
end

H.test("2.0 QM-1 the recycler pool's recipe control lists only recipes that can recycle the item", function()
    picker_world("2.0")
    local key = configure("X", "uncommon")
    local report = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local button = report.loops[key].pool.recycle_button
    H.equal(button.name, "hxrrc_choose_recycle_recipe_button", "pool recycle control")
    H.deep_equal(H.recipes_matching(button.elem_filters), {"X-recycling", "X-sorting-2"}, "listed recipes")
    H.equal(button.enabled, true, "enabled")
    H.equal(button.elem_value, "X-recycling", "default recycle recipe still shown")
end)

H.test("2.0 QM-2 an item no recipe can recycle: the pool's recipe control is disabled with a hint", function()
    picker_world("2.0")
    local key = configure("Z", "uncommon")
    local report = H.run_sheet({{item = "Z", quality = "uncommon", rate = 1, unit = "/s"}})
    local button = report.loops[key].pool.recycle_button
    H.equal(button.enabled, false, "disabled")
    H.deep_equal(button.tooltip, {"hxrrc.no_recycle_recipe_tooltip"}, "hint")
    H.equal(button.elem_value, nil, "no recycle recipe")
end)

M.picker_world, M.configure = picker_world, configure

H.done("test_quality_recycle_picker")
